#!/usr/bin/env bash
# PostToolUse(Write|Edit|NotebookEdit): run the repo's real ESLint on the file that
# was just written and hand any violations straight back to Claude.
#
# Why: the repo already encodes its architecture guardrails as ESLint rules
# (prefer-teserra-components, no-raw-console-paths, no-inline-gql, formatjs/*).
# Running them at commit time is too late — the model has moved on. Running them
# here closes the loop within one turn.
#
# Never blocks. Worst case it says nothing.

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

TLV_INPUT="$(cat)"; export TLV_INPUT
tlv_have jq || exit 0

file="$(tlv_field '.tool_input.file_path')"
[ -n "$file" ] || exit 0
case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

[ "$(tlv_cfg '.lint.enabled')" = "false" ] && exit 0

root="$(tlv_repo_root)"
rel="${file#"$root"/}"

# Only lint inside configured source roots.
top="${rel%%/*}"
if ! tlv_config | jq -e --arg t "$top" '.sourceRoots | index($t)' >/dev/null 2>&1; then
  exit 0
fi

timeout_s="$(tlv_cfg '.lint.timeoutSeconds')"; timeout_s="${timeout_s:-30}"
runner=""
tlv_have timeout && runner="timeout ${timeout_s}s"
tlv_have gtimeout && runner="gtimeout ${timeout_s}s"

out="$(cd "$root" && $runner pnpm exec eslint --format json "$rel" 2>/dev/null)" || exit 0
[ -n "$out" ] || exit 0

# Errors always surface. Warnings surface only for the repo's architecture rules —
# those are guardrails, not style preferences (CLAUDE.md "Coding Style").
report="$(printf '%s' "$out" | jq -r '
  [ .[]?.messages[]?
    | select(
        .severity == 2
        or (.ruleId // "" | test("^@dx/|^formatjs/|^jsx-a11y/|^no-console$|^react/forbid-elements$"))
      )
    | "  \(.line):\(.column)  \(.ruleId // "syntax")  \(.message)"
  ] | .[]' 2>/dev/null)" || exit 0

[ -n "$report" ] || exit 0

count="$(printf '%s\n' "$report" | grep -c . || true)"
msg="ESLint found ${count} guardrail violation(s) in ${rel}:

${report}

These are architecture guardrails from eslint.config.mjs, not style nits. Fix them now, in this file, before moving to the next file. Do not add an eslint-disable unless you can name the rule and give a '-- <reason>' suffix per CLAUDE.md."

tlv_emit_context "PostToolUse" "$msg"
exit 0
