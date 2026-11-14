#!/usr/bin/env bash
# Run-state for a tracked delivery run. State lives outside the target repo.
#
#   run.sh start <TICKET> <track>      begin a run on the current branch
#   run.sh phase <name>                move to a phase (this is what arms the gates)
#   run.sh gate <name> <status> [note] record a phase outcome
#   run.sh waive <key> <reason>        waive a definition-of-done obligation
#   run.sh adr <pr|thread|skip>        how this run records its decision (asked, not assumed)
#   run.sh stack init <count>          the stack is planned; <count> PRs agreed
#   run.sh stack pushed <pr-url>       current PR is up -> HOLD, the human reviews it
#   run.sh stack next                  the human said go; release the hold
#   run.sh stack show
#   run.sh show                        current state
#   run.sh next                        the phase that follows the current one

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
name="$(basename "$root" | tr -cd '[:alnum:]._-')"
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
slug="$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]._-')"
dir="${TLV_HOME:-$HOME}/.talview/${name:-workspace}/runs"
f="$dir/$slug.json"
MAP="${CLAUDE_PLUGIN_ROOT}/config/skill-map.json"
mkdir -p "$dir"

die() { echo "$1" >&2; exit 1; }
need_run() { [ -f "$f" ] || die "No run on branch '$branch'. Start one: run.sh start <TICKET> <track>"; }
save() { mv "$f.tmp" "$f"; }

case "${1:-show}" in
  start)
    ticket="${2:?ticket}"; track="${3:?track}"
    jq -e --arg t "$track" '.tracks[$t]' "$MAP" >/dev/null 2>&1 || die "Unknown track '$track'. Known: $(jq -r '.tracks|keys|join(", ")' "$MAP")"
    [ -f "$f" ] && die "A run already exists for '$branch' ($(jq -r .ticket "$f")). Use 'phase' to advance it."
    jq -n --arg tk "$ticket" --arg tr "$track" --arg br "$branch" \
      '{ticket:$tk, track:$tr, branch:$br, phase:"intake", gates:{}, waivers:{}, gateBlocks:0}' > "$f"
    echo "started $ticket on $branch (track: $track)"
    echo "phases: $(jq -r --arg t "$track" '.tracks[$t]|join(" -> ")' "$MAP")"
    ;;

  phase)
    need_run; p="${2:?phase}"
    jq -e --arg p "$p" '.phases[$p]' "$MAP" >/dev/null 2>&1 || die "Unknown phase '$p'"
    armed=false
    jq -e --arg p "$p" '.armedPhases | index($p)' "$MAP" >/dev/null 2>&1 && armed=true
    jq --arg p "$p" --argjson a "$armed" '.phase = $p | .armed = $a | .gateBlocks = 0' "$f" > "$f.tmp" && save
    echo "phase -> $p"
    [ "$armed" = "true" ] \
      && echo "definition-of-done gates ARMED: tests, stories, e2e and locale parity are now blocking." \
      || echo "gates idle (still building)."
    ;;

  gate)
    need_run; g="${2:?gate}"; st="${3:?status}"; note="${4:-}"
    jq --arg g "$g" --arg s "$st" --arg n "$note" \
      '.gates[$g] = {status:$s, note:$n}' "$f" > "$f.tmp" && save
    echo "gate $g = $st"
    ;;

  waive)
    need_run; k="${2:?key}"; r="${3:-}"
    [ -n "$r" ] || die "waive needs a reason — a waiver without one is just a skip"
    jq --arg k "$k" --arg r "$r" '.waivers[$k] = $r' "$f" > "$f.tmp" && save
    echo "waived $k: $r"
    ;;

  adr)
    need_run; m="${2:?pr|thread|skip}"
    case "$m" in pr|thread|skip) ;; *) die "adr mode must be pr, thread or skip" ;; esac
    jq --arg m "$m" '.adrMode = $m' "$f" > "$f.tmp" && save
    echo "adr mode: $m"
    [ "$m" = "skip" ] && echo "  the adr phase will be skipped; the decision still has to be stated somewhere — say it in the thread."
    ;;

  # A stack is a sequence of PRs a human reviews one at a time. The hold between them
  # is the point: running ahead to PR 3 while PR 1 is still being argued about wastes
  # the argument. `stack pushed` sets it; only a person clears it.
  stack)
    need_run; sub="${2:-show}"
    case "$sub" in
      init)
        n="${3:?count}"
        jq --argjson n "$n" '.stack = {total:$n, current:1, awaiting:false, prs:[]}' "$f" > "$f.tmp" && save
        echo "stack: $n PR(s) planned, on 1"
        ;;
      pushed)
        url="${3:?pr url}"
        jq --arg u "$url" '.stack.prs += [{n:(.stack.current // 1), url:$u}] | .stack.awaiting = true' "$f" > "$f.tmp" && save
        echo "PR $(jq -r '.stack.current // 1' "$f")/$(jq -r '.stack.total // "?"' "$f") is up: $url"
        echo "HOLD — the next PR is gated until you say go (run.sh stack next)."
        ;;
      next)
        [ "$(jq -r '.stack.awaiting // false' "$f")" = "true" ] || echo "note: no hold was set" >&2
        jq '.stack.current = ((.stack.current // 1) + 1) | .stack.awaiting = false' "$f" > "$f.tmp" && save
        c="$(jq -r '.stack.current' "$f")"; t="$(jq -r '.stack.total // "?"' "$f")"
        echo "released -> PR $c/$t"
        [ "$t" != "?" ] && [ "$c" -gt "$t" ] 2>/dev/null && echo "  that was the last planned PR."
        ;;
      show) jq -r '.stack // "no stack planned"' "$f" ;;
      *) die "usage: run.sh stack init|pushed|next|show" ;;
    esac
    ;;

  next)
    need_run
    track="$(jq -r .track "$f")"; cur="$(jq -r .phase "$f")"
    skip_adr="$(jq -r 'if .adrMode == "skip" then "adr" else "" end' "$f")"
    jq -r --arg t "$track" --arg c "$cur" --arg skip "$skip_adr" \
      '.tracks[$t] as $all
       | ($all | map(select(. != $skip))) as $ps
       | ($ps|index($c)) as $i
       | if $i == null then $ps[0] elif $i+1 < ($ps|length) then $ps[$i+1] else "done" end' "$MAP"
    ;;

  show)
    [ -f "$f" ] || { echo "no run on branch '$branch'"; exit 0; }
    jq . "$f"
    ;;

  path) echo "$f" ;;
  *) echo "usage: run.sh start|phase|gate|waive|adr|stack|next|show|path" >&2; exit 64 ;;
esac
