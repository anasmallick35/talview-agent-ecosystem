#!/usr/bin/env bash
# The concept library: what the work taught, written while the code is still in front of
# you. One file per concept, accumulating across runs — a concept met five times over
# three months IS the curriculum, and the `seen` counter finds it without anyone guessing.
#
#   concept.sh add <slug> [--tags a,b] [--entry <journal-id>] [--title "..."]   body on stdin
#   concept.sh bump <slug> [--entry <journal-id>]
#   concept.sh list [--tag x]
#   concept.sh due                      what revision is owed today
#   concept.sh reviewed <slug> <known|shaky>
#   concept.sh show <slug>
#
# Revision ladder, in days. `known` moves up one rung, `shaky` drops to the bottom —
# forgetting is information, so it resets the interval rather than nudging it.
LADDER=(1 3 7 21 60)

set -uo pipefail
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$(dirname "${BASH_SOURCE[0]}")/tlv-state.sh"

DIR="$(tlv_concepts_dir)"; mkdir -p "$DIR"
f_for() { printf '%s/%s.md' "$DIR" "$1"; }
# `cut -d' ' -f2-` returns the whole line when the field has no value, so an empty
# `lastReview:` read back as the literal key. Strip the key instead.
fm()    { sed -n "s/^$2:[[:space:]]*//p" "$1" 2>/dev/null | head -1 ; }
set_fm() {
  local f="$1" k="$2" v="$3"
  if grep -q "^$k:" "$f"; then
    # `^k: .*` needs a space after the colon, so a valueless key silently never matched
    # and every write was a no-op — which made the whole ladder look permanently due.
    sed -i '' "s|^$k:.*|$k: $v|" "$f" 2>/dev/null || sed -i "s|^$k:.*|$k: $v|" "$f"
  else
    sed -i '' "1a\\
$k: $v
" "$f" 2>/dev/null || sed -i "1a $k: $v" "$f"
  fi
}
days_between() {  # days_between <from YYYY-MM-DD> -> whole days until today
  local a b
  a=$(date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo 0)
  b=$(date +%s)
  [ "$a" -gt 0 ] 2>/dev/null && echo $(( (b - a) / 86400 )) || echo 9999
}
interval_for() { local s="${1:-0}"; [ "$s" -ge "${#LADDER[@]}" ] && s=$(( ${#LADDER[@]} - 1 )); echo "${LADDER[$s]}"; }
is_due() {
  local f="$1" last stage
  last="$(fm "$f" lastReview)"; stage="$(fm "$f" stage)"; stage="${stage:-0}"
  [ -n "$last" ] && [ "$last" != "never" ] || return 0      # never reviewed -> due
  [ "$(days_between "$last")" -ge "$(interval_for "$stage")" ]
}

args=(); tags=""; entry=""; title=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tags)  tags="${2:-}"; shift 2 ;;
    --entry) entry="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- "${args[@]:-}"

case "${1:-list}" in
  add)
    slug="${2:?slug}"; f="$(f_for "$slug")"
    if [ -f "$f" ]; then
      echo "'$slug' exists — bump it instead so the counter means something:" >&2
      echo "  concept.sh bump $slug --entry ${entry:-<id>}" >&2
      exit 1
    fi
    body="$(cat)"
    [ -n "$body" ] || { echo "a concept needs a body on stdin" >&2; exit 64; }
    { echo "---"
      echo "name: $slug"
      echo "title: ${title:-$slug}"
      echo "tags: ${tags:-untagged}"
      echo "seen: 1"
      echo "first: $(tlv_today)"
      echo "last: $(tlv_today)"
      echo "stage: 0"
      echo "lastReview: never"
      echo "reviews: 0"
      echo "shaky: 0"
      echo "entries: ${entry}"
      echo "---"
      echo
      printf '%s\n' "$body"
    } > "$f"
    echo "concept '$slug' recorded [$DIR]"
    [ -n "$entry" ] && "$(dirname "${BASH_SOURCE[0]}")/journal.sh" add "$entry" concepts "$slug" >/dev/null 2>&1
    exit 0
    ;;
  bump)
    slug="${2:?slug}"; f="$(f_for "$slug")"; [ -f "$f" ] || { echo "no concept '$slug'" >&2; exit 1; }
    n=$(( $(fm "$f" seen) + 1 )); set_fm "$f" seen "$n"; set_fm "$f" last "$(tlv_today)"
    if [ -n "$entry" ]; then
      cur="$(fm "$f" entries)"
      case ",$cur," in *",$entry,"*) ;; *) set_fm "$f" entries "${cur:+$cur,}$entry" ;; esac
      "$(dirname "${BASH_SOURCE[0]}")/journal.sh" add "$entry" concepts "$slug" >/dev/null 2>&1
    fi
    echo "'$slug' seen $n time(s)"
    exit 0
    ;;
  reviewed)
    slug="${2:?slug}"; res="${3:?known|shaky}"; f="$(f_for "$slug")"
    [ -f "$f" ] || { echo "no concept '$slug'" >&2; exit 1; }
    stage="$(fm "$f" stage)"; stage="${stage:-0}"
    case "$res" in
      known) stage=$((stage + 1)); [ "$stage" -ge "${#LADDER[@]}" ] && stage=$(( ${#LADDER[@]} - 1 )) ;;
      shaky) stage=0; set_fm "$f" shaky "$(( $(fm "$f" shaky) + 1 ))" ;;
      *) echo "result must be known or shaky" >&2; exit 64 ;;
    esac
    set_fm "$f" stage "$stage"
    set_fm "$f" lastReview "$(tlv_today)"
    set_fm "$f" reviews "$(( $(fm "$f" reviews) + 1 ))"
    echo "'$slug' -> $res, next in $(interval_for "$stage") day(s)"
    exit 0
    ;;
  due)
    n=0
    for f in "$DIR"/*.md; do
      [ -f "$f" ] || continue
      is_due "$f" || continue
      n=$((n+1))
      printf '%-34s seen:%-3s stage:%-2s %s\n' "$(basename "$f" .md)" "$(fm "$f" seen)" "$(fm "$f" stage)" "$(fm "$f" title)"
    done
    [ "$n" -eq 0 ] && echo "_nothing due — the ladder is clear_"
    exit 0
    ;;
  count-due)
    n=0; for f in "$DIR"/*.md; do [ -f "$f" ] || continue; is_due "$f" && n=$((n+1)); done; echo "$n"
    ;;
  list)
    printf '%-34s %-5s %-6s %-22s %s\n' SLUG SEEN STAGE TAGS TITLE
    for f in "$DIR"/*.md; do
      [ -f "$f" ] || continue
      [ -n "$tags" ] && { case ",$(fm "$f" tags)," in *",$tags,"*) ;; *) continue ;; esac; }
      printf '%-34s %-5s %-6s %-22s %s\n' "$(basename "$f" .md)" "$(fm "$f" seen)" "$(fm "$f" stage)" "$(fm "$f" tags)" "$(fm "$f" title)"
    done
    ;;
  show) f="$(f_for "${2:?slug}")"; [ -f "$f" ] && cat "$f" || { echo "no such concept" >&2; exit 1; } ;;
  path) echo "$DIR" ;;
  *) echo "usage: concept.sh add|bump|reviewed|due|count-due|list|show|path" >&2; exit 64 ;;
esac
