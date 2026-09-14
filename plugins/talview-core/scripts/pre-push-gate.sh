#!/usr/bin/env bash
# PreToolUse(Bash): the branch may only leave this machine when it can prove it is done.
#
# Standing policy replaces the per-push human confirmation: instead of asking, the
# gate verifies. It denies unless, for this branch:
#   - every artifact obligation is met (dod-check.sh clean), AND
#   - lint, typecheck and unit tests have a recorded PASS, AND
#   - none of those passes predates the newest source edit (no stale green).
#
# Untracked ad-hoc branches are not blocked, only annotated.

set -uo pipefail
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

TLV_INPUT="$(cat)"; export TLV_INPUT
tlv_have jq || exit 0

cmd="$(tlv_field '.tool_input.command')"
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)' || exit 0
# `gh stack submit` owns its own push path; let the stack tooling through.
printf '%s' "$cmd" | grep -q 'gh stack' && exit 0

root="$(tlv_repo_root)"; cd "$root" || exit 0
branch="$(tlv_branch)"

case "$branch" in
  develop|main|master)
    tlv_emit_deny "PreToolUse" "Refusing to push to protected branch '$branch' (CLAUDE.md Git Guardrails). Create a feature branch first."
    exit 0 ;;
esac

report="$("${CLAUDE_PLUGIN_ROOT}/scripts/dod-check.sh" 2>/dev/null)"; dod_rc=$?

run_file="$(tlv_run_file)" || run_file=""
tracked=0; [ -n "$run_file" ] && [ -f "$run_file" ] && tracked=1

ledger="$(tlv_state_dir)/runs/$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]._-').evidence.json"
stale=(); absent=(); failed=()
required="$(tlv_cfg '.push.requiredEvidence')"
[ -n "$required" ] || required='["lint","typecheck","test"]'

newest_src="$( { git diff --name-only --diff-filter=ACMR "$(tlv_merge_base)" 2>/dev/null; \
                 git ls-files --others --exclude-standard 2>/dev/null; } \
  | grep -E '\.(ts|tsx|js|jsx|json)$' \
  | while IFS= read -r f; do [ -f "$f" ] && { stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null; }; done \
  | sort -rn | head -1)"; newest_src="${newest_src:-0}"

while IFS= read -r chk; do
  [ -n "$chk" ] || continue
  if [ ! -f "$ledger" ]; then absent+=("$chk"); continue; fi
  st="$(jq -r --arg k "$chk" '.[$k].status // "absent"' "$ledger" 2>/dev/null)"
  mt="$(jq -r --arg k "$chk" '.[$k].sourceMtime // 0' "$ledger" 2>/dev/null)"
  case "$st" in
    absent) absent+=("$chk") ;;
    fail)   failed+=("$chk") ;;
    pass)   [ "${mt:-0}" -lt "$newest_src" ] 2>/dev/null && stale+=("$chk") ;;
  esac
done <<< "$(printf '%s' "$required" | jq -r '.[]' 2>/dev/null)"

problems=$(( dod_rc + ${#absent[@]} + ${#failed[@]} + ${#stale[@]} ))
[ "$problems" -eq 0 ] && exit 0

{
  echo "Push blocked — this branch cannot prove it is done."
  echo
  [ "$dod_rc" -ne 0 ] && { echo "$report"; }
  [ ${#absent[@]} -gt 0 ] && echo "Never run on this branch: ${absent[*]}"
  [ ${#failed[@]} -gt 0 ] && echo "Recorded as FAILING: ${failed[*]}"
  [ ${#stale[@]}  -gt 0 ] && echo "Passed, but source changed since: ${stale[*]} — re-run them."
  echo
  echo "Record each one after it genuinely passes:"
  echo "  \"\${CLAUDE_PLUGIN_ROOT}\"/scripts/evidence.sh record test pass 'pnpm --filter <pkg> run test'"
} > /tmp/tlv-push-gate.$$ 2>/dev/null

reason="$(cat /tmp/tlv-push-gate.$$)"; rm -f /tmp/tlv-push-gate.$$
[ "$tracked" -eq 1 ] && { tlv_emit_deny "PreToolUse" "$reason"; exit 0; }
tlv_emit_context "PreToolUse" "$reason"
exit 0
