#!/usr/bin/env bash
# PreToolUse(Bash): while a stacked PR is under review, refuse to start the next one.
#
# The hold exists because review is a conversation. Running ahead to PR 3 while PR 1 is
# still being argued about means the argument lands after the code that ignored it —
# and the author then has to choose between re-doing three PRs or letting the point go.
# Asking the model to "wait" is L2 and will be forgotten mid-run; this is L1.
#
# Cleared only by a person: `run.sh stack next`. Scoped to tracked runs with a planned
# stack; everything else is untouched.

set -uo pipefail

: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

TLV_INPUT="$(cat)"; export TLV_INPUT
tlv_have jq || exit 0

cmd="$(tlv_field '.tool_input.command')"
[ -n "$cmd" ] || exit 0

# What "starting the next PR" looks like in a shell. Not an exhaustive list of ways to
# misbehave — a gate is a speed bump on the obvious path, not a sandbox.
printf '%s' "$cmd" | grep -qE '(gh[[:space:]]+pr[[:space:]]+create|gh[[:space:]]+stack[[:space:]]+submit|git[[:space:]]+checkout[[:space:]]+-b|git[[:space:]]+switch[[:space:]]+-c|git[[:space:]]+worktree[[:space:]]+add)' || exit 0

run_file="$(tlv_run_file)" || exit 0
[ -f "$run_file" ] || exit 0

awaiting="$(jq -r '.stack.awaiting // false' "$run_file" 2>/dev/null)"
[ "$awaiting" = "true" ] || exit 0

cur="$(jq -r '.stack.current // 1' "$run_file")"
tot="$(jq -r '.stack.total // "?"' "$run_file")"
url="$(jq -r '[.stack.prs[]? | select(.n == (.n))] | last | .url // "the open PR"' "$run_file" 2>/dev/null)"
[ "$url" = "null" ] && url="the open PR"

tlv_emit_deny "PreToolUse" "HOLD: PR ${cur}/${tot} is open and has not been released yet.

  ${url}

The run stops here on purpose. Review that PR, argue with it, and when you are satisfied
say so — then the hold clears:

  run.sh stack next

While the hold is on: answer review threads, make the changes they ask for, commit and
push to the SAME branch. Do not start the next PR, and do not open a new branch.

If you pushed back on something in this session and it was accepted or rejected, capture
it before moving on — that exchange is not on GitHub and nothing else will remember it:

  lesson.sh capture <slug> <adopted|rejected> \"<what you argued, in one line>\""
exit 0
