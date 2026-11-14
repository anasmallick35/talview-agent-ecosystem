#!/usr/bin/env bash
# Answer and close review threads, addressed by id rather than by matching body text.
#
#   thread.sh reply   <thread-id> <<<"what changed, or why it did not"
#   thread.sh resolve <thread-id>
#   thread.sh close   <thread-id> <<<"..."        reply, then resolve
#   thread.sh list    <pr-number> [--repo o/n]    open threads and their ids
#
# Resolving is a claim that the thread is finished. Resolve a thread you answered and
# acted on, or answered and declined with a reason. Never resolve one you are quietly
# dropping: a resolved thread reads to the reviewer as "handled", and silently closing
# one spends trust that is hard to get back.

set -uo pipefail
cmd="${1:?reply|resolve|close|list}"; shift || true

repo=""
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?}"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
owner="${repo%%/*}"; name="${repo#*/}"

do_reply() {
  local tid="$1" body="$2"
  gh api graphql -f threadId="$tid" -f body="$body" -f query='
    mutation($threadId:ID!, $body:String!) {
      addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}) {
        comment { url }
      }
    }' -q '.data.addPullRequestReviewThreadReply.comment.url'
}

do_resolve() {
  gh api graphql -f threadId="$1" -f query='
    mutation($threadId:ID!) {
      resolveReviewThread(input:{threadId:$threadId}) { thread { isResolved } }
    }' -q '.data.resolveReviewThread.thread.isResolved'
}

case "$cmd" in
  reply)
    tid="${args[0]:?thread id}"; body="$(cat)"
    [ -n "$body" ] || { echo "a reply needs a body — read it from stdin" >&2; exit 64; }
    echo "replied: $(do_reply "$tid" "$body")"
    ;;
  resolve)
    tid="${args[0]:?thread id}"
    echo "resolved: $(do_resolve "$tid")"
    ;;
  close)
    tid="${args[0]:?thread id}"; body="$(cat)"
    [ -n "$body" ] || { echo "say what you did before closing the thread" >&2; exit 64; }
    echo "replied: $(do_reply "$tid" "$body")"
    echo "resolved: $(do_resolve "$tid")"
    ;;
  list)
    pr="${args[0]:?pr number}"
    # The repo defaults to whatever directory you are standing in, which is rarely the
    # one the PR lives in. Say so plainly instead of letting jq crash on a null.
    out="$(gh api graphql -f owner="$owner" -f name="$name" -F pr="$pr" -f query='
      query($owner:String!, $name:String!, $pr:Int!) {
        repository(owner:$owner, name:$name) {
          pullRequest(number:$pr) {
            reviewThreads(first:100) {
              nodes { id isResolved path line comments(first:1){nodes{author{login} body}} }
            }
          }
        }
      }' 2>/dev/null)"
    if [ -z "$out" ] || [ "$(printf '%s' "$out" | jq -r '.data.repository.pullRequest // "null"')" = "null" ]; then
      echo "No PR #$pr in $repo — pass --repo <owner/name> if the PR lives elsewhere." >&2
      exit 1
    fi
    printf '%s' "$out" \
    | jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
             | select(.isResolved | not)
             | "\(.id)  \(.path):\(.line // "?")  @\(.comments.nodes[0].author.login // "?")  \(.comments.nodes[0].body[0:80] | gsub("\n";" "))"'
    ;;
  *) echo "usage: thread.sh reply|resolve|close|list" >&2; exit 64 ;;
esac
