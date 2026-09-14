#!/usr/bin/env bash
# Pull every review comment off a PR, with the code it was attached to.
#   harvest.sh <pr-number> [--exclude-self] [--repo <owner/name>]
#
# Self-authored comments are INCLUDED by default and labelled. In this workspace the
# code-review skill posts via `gh pr review` under the human's own account, so filtering
# by author would discard most of the review signal on their own PRs. Bots are dropped.

set -uo pipefail
pr="${1:?pr number}"; shift || true
exclude_self=0; repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude-self) exclude_self=1; shift ;;
    --repo) repo="${2:?}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
me="$(gh api user -q .login 2>/dev/null)"

flt() {
  if [ "$exclude_self" -eq 1 ]; then jq --arg me "$me" '[.[] | select(.user.type != "Bot") | select(.user.login != $me)]'
  else jq '[.[] | select(.user.type != "Bot")]'; fi
}
label() { [ "$1" = "$me" ] && printf 'self-review' || printf 'reviewer'; }

echo "# PR #$pr — $repo"
[ "$exclude_self" -eq 0 ] && echo "_Self-authored comments included and marked \`self-review\` — the review tooling posts as the human._"
echo

echo "## Inline review threads"
gh api "repos/$repo/pulls/$pr/comments" --paginate 2>/dev/null | flt | jq -r --arg me "$me" '
  .[] | "### \(.path):\(.line // .original_line)  — @\(.user.login) [\(if .user.login == $me then "self-review" else "reviewer" end)]\n\n\(.body)\n\n```diff\n\(.diff_hunk // "")\n```\n"'

echo "## Review summaries"
gh api "repos/$repo/pulls/$pr/reviews" --paginate 2>/dev/null | flt | jq -r --arg me "$me" '
  .[] | select(.body != "")
  | "- **@\(.user.login)** [\(if .user.login == $me then "self-review" else "reviewer" end)] (\(.state)): \(.body)"'
echo

echo "## Issue-level comments"
gh api "repos/$repo/issues/$pr/comments" --paginate 2>/dev/null | flt | jq -r --arg me "$me" '
  .[] | "- **@\(.user.login)** [\(if .user.login == $me then "self-review" else "reviewer" end)]: \(.body)"'
