#!/usr/bin/env bash
# Pull every review comment off a PR, threaded, with the code it was attached to and
# whether the thread was resolved.
#
#   harvest.sh <pr-number> [--exclude-self] [--repo <owner/name>]
#
# Threads come from GraphQL, not REST. REST returns review comments as a flat list with
# no resolution state, which loses the two things that make a disagreement legible: who
# was answering whom, and who ended up right. A reviewer's point plus your rebuttal plus
# "resolved" is a lesson; the same three comments in a flat list are noise.
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
owner="${repo%%/*}"; name="${repo#*/}"
me="$(gh api user -q .login 2>/dev/null)"

flt() {
  if [ "$exclude_self" -eq 1 ]; then jq --arg me "$me" '[.[] | select(.user.type != "Bot") | select(.user.login != $me)]'
  else jq '[.[] | select(.user.type != "Bot")]'; fi
}

echo "# PR #$pr — $repo"
[ "$exclude_self" -eq 0 ] && echo "_Self-authored comments included and marked \`self-review\` — the review tooling posts as the human._"
echo

echo "## Review threads"
echo
echo "_A thread marked RESOLVED after a disagreement is the outcome, not just the exchange._"
echo

gh api graphql -f owner="$owner" -f name="$name" -F pr="$pr" -f query='
  query($owner:String!, $name:String!, $pr:Int!) {
    repository(owner:$owner, name:$name) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            id
            isResolved
            isOutdated
            path
            line
            comments(first:50) {
              nodes { author { login } body diffHunk createdAt }
            }
          }
        }
      }
    }
  }' 2>/dev/null \
| jq -r --arg me "$me" --argjson xs "$exclude_self" '
    .data.repository.pullRequest.reviewThreads.nodes[]?
    | . as $t
    | ($t.comments.nodes | map(select(.author.login != null))) as $cs
    | ($cs | map(select(.author.login | test("\\[bot\\]$") | not))) as $cs
    | (if $xs == 1 then ($cs | map(select(.author.login != $me))) else $cs end) as $cs
    | select($cs | length > 0)
    | "### \($t.path):\($t.line // "?")  — \(if $t.isResolved then "RESOLVED" else "UNRESOLVED" end)\(if $t.isOutdated then ", outdated" else "" end), \($cs|length) comment(s)\n`thread: \($t.id)`\n"
      + "\n```diff\n\($cs[0].diffHunk // "")\n```\n"
      + ([ $cs[] | "**@\(.author.login)** [\(if .author.login == $me then "self" else "reviewer" end)]:\n\(.body)\n" ] | join("\n"))
      + (if ($cs|length) > 1 then "\n_This thread has replies. Pair the opening comment with the last one and with what the diff does now — agreement, pushback and silence are three different lessons._\n" else "" end)
  '

echo
echo "## Review summaries"
gh api "repos/$repo/pulls/$pr/reviews" --paginate 2>/dev/null | flt | jq -r --arg me "$me" '
  .[] | select(.body != "")
  | "- **@\(.user.login)** [\(if .user.login == $me then "self-review" else "reviewer" end)] (\(.state)): \(.body)"'
echo

echo "## Issue-level comments"
gh api "repos/$repo/issues/$pr/comments" --paginate 2>/dev/null | flt | jq -r --arg me "$me" '
  .[] | "- **@\(.user.login)** [\(if .user.login == $me then "self-review" else "reviewer" end)]: \(.body)"'

echo
echo "## What changed in response"
echo
echo '```'
gh pr diff "$pr" --repo "$repo" --name-only 2>/dev/null | head -40
echo '```'
echo
echo "_Pair each thread with the file it names above. A thread with no corresponding change"
echo "is either an unactioned comment or a disagreement you won — both are lessons, and they"
echo "are different ones._"
