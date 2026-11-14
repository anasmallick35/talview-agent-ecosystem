#!/usr/bin/env bash
# Evidence ledger. The pipeline records what it actually ran; the push gate reads it.
#
#   evidence.sh record <check> <pass|fail> "<command>" ["<note>"]
#   evidence.sh show
#
# Each entry stamps the time AND the branch's newest source mtime at that moment.
# If source is edited afterwards the entry goes stale and stops counting as proof —
# which is the whole point: "tests passed" only means something for the code that ran.

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TLV_INPUT='{}'
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
slug="$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]._-')"
ledger="$(tlv_state_dir)/runs/$slug.evidence.json"
mkdir -p "$(dirname "$ledger")"
[ -f "$ledger" ] || echo '{}' > "$ledger"

# Portable mtime. The GNU form is tried FIRST on purpose: on Linux `stat -f %m FILE`
# prints filesystem information to stdout and exits non-zero, so a `-f`-first fallback
# chain appends the epoch to that text and yields a multi-line value that every numeric
# comparison then fails, silently. `stat -c` on BSD fails cleanly with no stdout, so this
# order is the only one that is safe on both.
newest_source_mtime() {
  local mb; mb="$(git -C "$root" merge-base origin/"$(tlv_base_branch)" HEAD 2>/dev/null)"
  {
    git -C "$root" diff --name-only --diff-filter=ACMR "$mb" 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | grep -E '\.(ts|tsx|js|jsx|json)$' | while IFS= read -r f; do
        # Also fixes a precedence bug: with `[ -f ] && A || B`, a missing file ran B.
        [ -f "$root/$f" ] || continue
        stat -c %Y "$root/$f" 2>/dev/null || stat -f %m "$root/$f" 2>/dev/null
      done | sort -rn | head -1
}

case "${1:-}" in
  record)
    check="${2:?check name}"; status="${3:?pass|fail}"; cmd="${4:-}"; note="${5:-}"
    now="$(date +%s)"; src="$(newest_source_mtime)"; src="${src:-0}"
    jq --arg k "$check" --arg s "$status" --arg c "$cmd" --arg n "$note" \
       --argjson t "$now" --argjson m "$src" \
       '.[$k] = {status:$s, command:$c, note:$n, at:$t, sourceMtime:$m}' \
       "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
    echo "recorded: $check=$status"
    ;;
  show) cat "$ledger" ;;
  path) echo "$ledger" ;;
  *) echo "usage: evidence.sh record <check> <pass|fail> <command> [note] | show | path" >&2; exit 64 ;;
esac
