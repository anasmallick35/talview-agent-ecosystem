#!/usr/bin/env bash
# Stop hook: refuse to end the turn while a tracked run has unmet obligations.
# Scoped to tracked runs in an active phase; ad-hoc sessions are untouched.
# Escape hatches: do the work, record a waiver, or the loop breaker after N blocks.

set -uo pipefail
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

TLV_INPUT="$(cat)"; export TLV_INPUT
tlv_have jq || exit 0
[ "$(tlv_field '.stop_hook_active')" = "true" ] && exit 0

run_file="$(tlv_run_file)" || exit 0
[ -f "$run_file" ] || exit 0
# The track owns the phase vocabulary; core only asks whether gates are armed.
[ "$(jq -r '.armed // false' "$run_file" 2>/dev/null)" = "true" ] || exit 0

report="$("${CLAUDE_PLUGIN_ROOT}/scripts/dod-check.sh" 2>/dev/null)"
[ -z "$report" ] && {
  jq '.gateBlocks = 0' "$run_file" > "$run_file.tmp" 2>/dev/null && mv "$run_file.tmp" "$run_file"
  exit 0
}

blocks="$(jq -r '.gateBlocks // 0' "$run_file" 2>/dev/null)"; blocks=$((blocks + 1))
max="$(tlv_cfg '.dod.maxGateBlocks')"; max="${max:-4}"
jq --argjson n "$blocks" '.gateBlocks = $n' "$run_file" > "$run_file.tmp" 2>/dev/null && mv "$run_file.tmp" "$run_file"

{
  echo "DEFINITION-OF-DONE GATE FAILED (block ${blocks}/${max})."
  echo
  echo "$report"
  echo "Produce the missing artifacts now — do not summarise and do not ask."
  echo "If one is genuinely not applicable, waive it with a reason:"
  echo "  jq '.waivers.stories = \"<why>\"' \"$run_file\" > /tmp/w.json && mv /tmp/w.json \"$run_file\""
} >&2

if [ "$blocks" -ge "$max" ]; then
  echo "Loop breaker: ${max} consecutive blocks — releasing the turn. THESE GAPS REMAIN OPEN; report them to the user verbatim." >&2
  exit 0
fi
exit 2
