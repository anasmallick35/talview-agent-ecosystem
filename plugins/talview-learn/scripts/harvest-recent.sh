#!/usr/bin/env bash
# Sweep recently merged PRs for review feedback, so harvesting does not depend on
# remembering to run it per PR.
#
#   harvest-recent.sh [days] [--author <login>] [--repo <owner/name>]
#
# This is the reason the ecosystem does not need a GitHub Actions workflow in the product
# repo: the same signal is reachable from a local `gh` session, and a scheduled Claude
# Code run can call this. No change to a repository shared by the whole team.

set -uo pipefail
days="${1:-7}"; [ "${days#-}" = "$days" ] || days=7
shift 2>/dev/null || true
author=""; repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --author) author="${2:?}"; shift 2 ;;
    --repo)   repo="${2:?}";   shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$repo" ]   || repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
[ -n "$author" ] || author="$(gh api user -q .login 2>/dev/null)"

since="$(date -u -v-"${days}"d '+%Y-%m-%d' 2>/dev/null || date -u -d "${days} days ago" '+%Y-%m-%d')"
echo "# Review feedback sweep — $repo, merged since $since, author @$author"
echo

prs="$(gh pr list --repo "$repo" --author "$author" --state merged --limit 50 \
        --json number,title,mergedAt,url \
        -q ".[] | select(.mergedAt >= \"${since}\") | \"\(.number)\t\(.title)\"" 2>/dev/null)"

[ -n "$prs" ] || { echo "_No PRs merged in this window._"; exit 0; }

n=0
while IFS=$'\t' read -r num title; do
  [ -n "$num" ] || continue
  inline=$(gh api "repos/$repo/pulls/$num/comments" --paginate 2>/dev/null | jq '[.[]|select(.user.type!="Bot")]|length')
  [ "${inline:-0}" -gt 0 ] || continue
  n=$((n+1))
  echo "---"
  echo
  "$(dirname "$0")/harvest.sh" "$num" --repo "$repo"
  echo
done <<< "$prs"

echo "---"
echo
echo "_$n PR(s) with review comments. Classify each with \`lesson.sh add\`; queue anything"
echo "destined for the product repo with \`lesson.sh pending\` rather than applying it._"
