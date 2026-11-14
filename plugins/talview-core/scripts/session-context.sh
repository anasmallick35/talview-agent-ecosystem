#!/usr/bin/env bash
# SessionStart: tell Claude where this branch stands before it does anything.
# Without this, every session re-derives the state of the work from scratch — and
# often gets it wrong.

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"

TLV_INPUT="$(cat)"; export TLV_INPUT
tlv_have jq || exit 0

root="$(tlv_repo_root)"; cd "$root" || exit 0
branch="$(tlv_branch)"; [ -n "$branch" ] || exit 0

# Rules learned from past review, and PRs whose review is not harvested yet. These are
# NOT scoped to a tracked run: a rule that only applies during /tlv:start is a rule that
# does not apply. Kept short — this is injected into every session on this machine.
lessons_dir="${TLV_LESSONS_DIR:-${TLV_HOME:-$HOME}/.talview/lessons}"
learned=""
if [ -s "$lessons_dir/active-rules.md" ]; then
  rules="$(grep '^- ' "$lessons_dir/active-rules.md" 2>/dev/null | head -25)"
  [ -n "$rules" ] && learned="
Rules learned from review on earlier runs — these hold here too:
${rules}"
fi
if [ -f "$lessons_dir/harvest-queue.json" ]; then
  owed="$(jq -r '[.[] | select(.harvested == false)] | length' "$lessons_dir/harvest-queue.json" 2>/dev/null)"
  if [ "${owed:-0}" -gt 0 ]; then
    learned="${learned}

${owed} PR(s) raised by an earlier run have never had their review harvested. If you are
about to act on review comments, run /talview-learn:learn on that PR FIRST — the comment,
the pushback and the fix are only a lesson while all three are still visible."
  fi
fi

run_file="$(tlv_run_file)" || run_file=""
if [ -z "$run_file" ] || [ ! -f "$run_file" ]; then
  # No tracked run: still carry the learned rules, then stay out of the way.
  [ -n "$learned" ] && tlv_emit_context "SessionStart" "${learned# }"
  exit 0
fi

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

[ -n "$learned" ] && msg="${msg}
${learned}"

tlv_emit_context "SessionStart" "$msg"
exit 0
