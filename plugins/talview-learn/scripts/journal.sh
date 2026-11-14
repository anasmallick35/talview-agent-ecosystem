#!/usr/bin/env bash
# The work journal: one entry per run, per day. Seeded automatically by `run.sh start`
# so the record exists before anyone has to remember to make it.
#
#   journal.sh open <ticket> <track> [repo] [branch]   create/return today's entry id
#   journal.sh set  <id> <field> <value>               title | summary
#   journal.sh add  <id> <list> <value>                areas | prs | concepts | lessons
#   journal.sh show <id>
#   journal.sh list [--since YYYY-MM-DD]
#   journal.sh open-entries                            entries with no concepts recorded

set -uo pipefail
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$(dirname "${BASH_SOURCE[0]}")/tlv-state.sh"

DIR="$(tlv_journal_dir)"; mkdir -p "$DIR"
file_for() { printf '%s/%s.json' "$DIR" "$1"; }

case "${1:-list}" in
  open)
    ticket="${2:?ticket}"; track="${3:?track}"; repo="${4:-}"; branch="${5:-}"
    [ -n "$repo" ] || repo="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo workspace)")"
    [ -n "$branch" ] || branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    id="$(tlv_today)-$(printf '%s' "$ticket" | tr -cd '[:alnum:]._-')"
    f="$(file_for "$id")"
    # Re-opening the same ticket on the same day is the same entry, not a second one:
    # a run that spans a lunch break is still one piece of work.
    [ -f "$f" ] || jq -n --arg i "$id" --arg d "$(tlv_today)" --arg t "$ticket" \
      --arg k "$track" --arg r "$repo" --arg b "$branch" \
      '{id:$i, date:$d, ticket:$t, track:$k, repo:$r, branch:$b,
        title:"", summary:"", areas:[], prs:[], concepts:[], lessons:[]}' > "$f"
    printf '%s\n' "$id"
    ;;
  set)
    id="${2:?id}"; k="${3:?field}"; v="${4:?value}"; f="$(file_for "$id")"
    [ -f "$f" ] || { echo "no entry '$id'" >&2; exit 1; }
    case "$k" in title|summary) ;; *) echo "set takes title|summary" >&2; exit 64 ;; esac
    jq --arg k "$k" --arg v "$v" '.[$k] = $v' "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
    echo "$id.$k set"
    ;;
  add)
    id="${2:?id}"; k="${3:?list}"; v="${4:?value}"; f="$(file_for "$id")"
    [ -f "$f" ] || { echo "no entry '$id'" >&2; exit 1; }
    case "$k" in areas|prs|concepts|lessons) ;; *) echo "add takes areas|prs|concepts|lessons" >&2; exit 64 ;; esac
    jq --arg k "$k" --arg v "$v" '.[$k] = ((.[$k] // []) + [$v] | unique)' "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
    echo "$id.$k += $v"
    ;;
  show) f="$(file_for "${2:?id}")"; [ -f "$f" ] && jq . "$f" || { echo "no such entry" >&2; exit 1; } ;;
  list)
    since="${3:-0000-00-00}"
    for f in "$DIR"/*.json; do [ -f "$f" ] || continue; jq -c --arg s "$since" 'select(.date >= $s)' "$f"; done \
      | jq -s -r 'sort_by(.date, .ticket) | .[] | "\(.date)  \(.track|.[0:4])  \(.ticket)  \(.title // "")  [\(.concepts|length) concepts]"'
    ;;
  open-entries)
    n=0
    for f in "$DIR"/*.json; do
      [ -f "$f" ] || continue
      jq -e '(.concepts|length) == 0' "$f" >/dev/null 2>&1 || continue
      n=$((n+1)); jq -r '"\(.date)  \(.ticket)  \(.title // "(untitled)")"' "$f"
    done
    [ "$n" -eq 0 ] && echo "_every entry has at least one concept recorded_"
    exit 0
    ;;
  path) echo "$DIR" ;;
  *) echo "usage: journal.sh open|set|add|show|list|open-entries|path" >&2; exit 64 ;;
esac
