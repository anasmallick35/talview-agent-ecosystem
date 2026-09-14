#!/usr/bin/env bash
# SessionStart: tell Claude where this branch stands before it does anything.
# Without this, every session re-derives the state of the work from scratch — and
# often gets it wrong.

set -uo pipefail
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

TLV_INPUT="$(cat)"; export TLV_INPUT
tlv_have jq || exit 0

root="$(tlv_repo_root)"; cd "$root" || exit 0
branch="$(tlv_branch)"; [ -n "$branch" ] || exit 0

run_file="$(tlv_run_file)" || run_file=""
[ -n "$run_file" ] && [ -f "$run_file" ] || exit 0   # silent outside a tracked run

ticket="$(jq -r '.ticket // "unknown"' "$run_file")"
track="$(jq -r '.track  // "unknown"' "$run_file")"
phase="$(jq -r '.phase  // "unknown"' "$run_file")"

gaps="$("${CLAUDE_PLUGIN_ROOT}/scripts/dod-check.sh" 2>/dev/null)" || true
ledger="${run_file%.json}.evidence.json"
ev="none recorded"
[ -f "$ledger" ] && ev="$(jq -r 'to_entries|map("\(.key)=\(.value.status)")|join(", ")' "$ledger" 2>/dev/null)"

msg="Talview run in progress on this branch.
  ticket: ${ticket}   track: ${track}   phase: ${phase}
  evidence: ${ev}
  state file: ${run_file#"$root"/}
"
if [ -n "$gaps" ]; then
  msg="${msg}
Open definition-of-done gaps (the Stop gate will block on these):
${gaps}"
else
  msg="${msg}
Definition-of-done artifact checks are currently clean."
fi

tlv_emit_context "SessionStart" "$msg"
exit 0
