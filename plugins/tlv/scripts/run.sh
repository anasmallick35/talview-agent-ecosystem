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
#   run.sh stack next [--nothing-learned]
#                                      the human said go; release the hold. Refuses while
#                                      the round has taught nothing, unless you say so.
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
# Temp files carry $$ so two processes — two devpod containers sharing a mounted
# state dir, or two sessions on one machine — cannot write the same scratch path and
# hand each other a half-written file on rename.
save() { mv "$f.tmp.$$" "$f"; }

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
    jq --arg p "$p" --argjson a "$armed" '.phase = $p | .armed = $a | .gateBlocks = 0' "$f" > "$f.tmp.$$" && save
    echo "phase -> $p"
    [ "$armed" = "true" ] \
      && echo "definition-of-done gates ARMED: tests, stories, e2e and locale parity are now blocking." \
      || echo "gates idle (still building)."
    ;;

  gate)
    need_run; g="${2:?gate}"; st="${3:?status}"; note="${4:-}"
    jq --arg g "$g" --arg s "$st" --arg n "$note" \
      '.gates[$g] = {status:$s, note:$n}' "$f" > "$f.tmp.$$" && save
    echo "gate $g = $st"
    ;;

  waive)
    need_run; k="${2:?key}"; r="${3:-}"
    [ -n "$r" ] || die "waive needs a reason — a waiver without one is just a skip"
    jq --arg k "$k" --arg r "$r" '.waivers[$k] = $r' "$f" > "$f.tmp.$$" && save
    echo "waived $k: $r"
    ;;

  adr)
    need_run; m="${2:?pr|thread|skip}"
    case "$m" in pr|thread|skip) ;; *) die "adr mode must be pr, thread or skip" ;; esac
    jq --arg m "$m" '.adrMode = $m' "$f" > "$f.tmp.$$" && save
    echo "adr mode: $m"
    if [ "$m" = "skip" ]; then
      echo "  the adr phase will be skipped; the decision still has to be stated somewhere — say it in the thread."
    fi
    ;;

  # A stack is a sequence of PRs a human reviews one at a time. The hold between them
  # is the point: running ahead to PR 3 while PR 1 is still being argued about wastes
  # the argument. `stack pushed` sets it; only a person clears it.
  stack)
    need_run; sub="${2:-show}"
    case "$sub" in
      init)
        n="${3:?count}"
        jq --argjson n "$n" '.stack = {total:$n, current:1, awaiting:false, prs:[]}' "$f" > "$f.tmp.$$" && save
        echo "stack: $n PR(s) planned, on 1"
        ;;
      pushed)
        url="${3:?pr url}"
        jq --arg u "$url" --argjson t "$(date +%s)" \
          '.stack.prs += [{n:(.stack.current // 1), url:$u}] | .stack.awaiting = true | .stack.holdAt = $t' "$f" > "$f.tmp.$$" && save
        echo "PR $(jq -r '.stack.current // 1' "$f")/$(jq -r '.stack.total // "?"' "$f") is up: $url"
        echo "HOLD — the next PR is gated until you say go (run.sh stack next)."
        ;;
      next)
        [ "$(jq -r '.stack.awaiting // false' "$f")" = "true" ] || echo "note: no hold was set" >&2
        # A review round that taught nothing is possible but uncommon. Far more common is
        # a round that taught something nobody wrote down — the argument happened in a
        # chat window and left with it. The hold release is the one moment the round is
        # unambiguously over, so it is where the question gets asked.
# Portable mtime. The GNU form is tried FIRST on purpose: on Linux `stat -f %m FILE`
# prints filesystem information to stdout and exits non-zero, so a `-f`-first fallback
# chain appends the epoch to that text and yields a multi-line value that every numeric
# comparison then fails, silently. `stat -c` on BSD fails cleanly with no stdout, so this
# order is the only one that is safe on both.
        if [ "${3:-}" != "--nothing-learned" ]; then
          held="$(jq -r '.stack.holdAt // 0' "$f")"
          if [ -n "${TLV_LESSONS_DIR:-}" ]; then lessons="$TLV_LESSONS_DIR"
          elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then lessons="$CLAUDE_CONFIG_DIR/talview/lessons"
          else lessons="${TLV_HOME:-$HOME}/.talview/lessons"; fi
          fresh=0
          if [ "$held" -gt 0 ] 2>/dev/null && [ -d "$lessons" ]; then
            for l in "$lessons"/*.md; do
              [ -f "$l" ] || continue
              case "$(basename "$l")" in active-rules.md) continue ;; esac
              m="$(stat -c %Y "$l" 2>/dev/null || stat -f %m "$l" 2>/dev/null || echo 0)"
              [ "$m" -ge "$held" ] 2>/dev/null && { fresh=$((fresh+1)); }
            done
          fi
          [ "$fresh" -eq 0 ] && die "This round recorded nothing.

Review happened and the ledger did not move. If something was argued — on the PR or in
the session — capture it before the context is gone:

  lesson.sh capture <slug> <adopted|rejected> \"<what was argued, one line>\"
  lesson.sh add <slug> <destination> <pr-url>   # for a reviewer's comment

If the round genuinely taught nothing — a typo fix, a rename — say so explicitly:

  run.sh stack next --nothing-learned"
        fi
        jq --arg nl "${3:-}" \
          '.stack.current = ((.stack.current // 1) + 1)
           | .stack.awaiting = false
           | if $nl == "--nothing-learned"
             then .stack.nothingLearned = ((.stack.nothingLearned // []) + [(.stack.current - 1)])
             else . end' "$f" > "$f.tmp.$$" && save
        c="$(jq -r '.stack.current' "$f")"; t="$(jq -r '.stack.total // "?"' "$f")"
        echo "released -> PR $c/$t"
        if [ "$t" != "?" ] && [ "$c" -gt "$t" ] 2>/dev/null; then
          echo "  that was the last planned PR."
        fi
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
