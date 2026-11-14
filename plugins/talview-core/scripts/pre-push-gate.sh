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

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

TLV_INPUT="$(cat)"; export TLV_INPUT
tlv_have jq || exit 0

cmd="$(tlv_field '.tool_input.command')"
# `git push`, but also `git -C <dir> push` and `git --git-dir=... push`: global options
# sit between the binary and the subcommand, and a gate that only matches the bare form
# is a gate with a documented way around it.
printf '%s' "$cmd" \
  | grep -qE '(^|[;&|[:space:]])git([[:space:]]+(-[cC][[:space:]]*[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?|-[a-zA-Z]))*[[:space:]]+push([[:space:]]|$)' \
  || exit 0
# `gh stack submit` owns its own push path; let the stack tooling through.
printf '%s' "$cmd" | grep -q 'gh stack' && exit 0

# A command may push a DIFFERENT repository to the one the session is rooted in —
# `cd ../other-repo && git push` is ordinary. Honour a leading `cd` so the gate judges
# the branch it is actually about to push. Without this the gate reads the session's
# branch and refuses a push it was never asked about, which trains people to ignore it.
# grep -oE, not sed: BSD sed has no \b, so a word-boundary pattern silently never
# matches on macOS and the gate quietly judges the wrong repository.
target_dir=""
cd_arg="$(printf '%s' "$cmd" \
  | grep -oE '(^|[;&|[:space:]])cd[[:space:]]+[^;&|]+' \
  | tail -1 \
  | sed -e 's/^[^c]*cd[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//; s/"$//' -e "s/^'//; s/'$//")"
case "$cd_arg" in
  "~"|"~/"*) cd_arg="$HOME${cd_arg#\~}" ;;
esac
[ -n "$cd_arg" ] && [ -d "$cd_arg" ] && target_dir="$cd_arg"

root="$(tlv_repo_root)"
if [ -n "$target_dir" ]; then
  alt="$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$alt" ] && root="$alt"
fi
cd "$root" || exit 0
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"

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
