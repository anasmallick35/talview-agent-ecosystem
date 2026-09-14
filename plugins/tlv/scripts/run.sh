#!/usr/bin/env bash
# Run-state for a tracked delivery run. State lives outside the target repo.
#
#   run.sh start <TICKET> <track>      begin a run on the current branch
#   run.sh phase <name>                move to a phase (this is what arms the gates)
#   run.sh gate <name> <status> [note] record a phase outcome
#   run.sh waive <key> <reason>        waive a definition-of-done obligation
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

  next)
    need_run
    track="$(jq -r .track "$f")"; cur="$(jq -r .phase "$f")"
    jq -r --arg t "$track" --arg c "$cur" \
      '.tracks[$t] as $ps | ($ps|index($c)) as $i
       | if $i == null then $ps[0] elif $i+1 < ($ps|length) then $ps[$i+1] else "done" end' "$MAP"
    ;;

  show)
    [ -f "$f" ] || { echo "no run on branch '$branch'"; exit 0; }
    jq . "$f"
    ;;

  path) echo "$f" ;;
  *) echo "usage: run.sh start|phase|gate|waive|next|show|path" >&2; exit 64 ;;
esac
