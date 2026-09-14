#!/usr/bin/env bash
# The lesson ledger. One file per lesson, classified by where it can be enforced.
#
#   lesson.sh add <slug> <destination> <pr-url>    create from stdin (the lesson body)
#   lesson.sh list [status]
#   lesson.sh pending                              lessons needing a webclients PR
#
# Destinations:
#   eslint-rule   mechanically detectable  -> dx/eslint-plugin       [webclients: PROPOSE]
#   hook          detectable at edit time  -> talview-core/hooks     [here: APPLY]
#   skill-rule    needs judgment           -> a skill's references/  [here: APPLY]
#   claude-md     seen 3+ times            -> CLAUDE.md              [webclients: PROPOSE]

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DIR="${CLAUDE_PLUGIN_ROOT}/lessons"
mkdir -p "$DIR"

case "${1:-list}" in
  add)
    slug="${2:?slug}"; dest="${3:?destination}"; pr="${4:-}"
    case "$dest" in
      eslint-rule|claude-md) applies="propose" ;;
      hook|skill-rule)       applies="apply" ;;
      *) echo "unknown destination '$dest'" >&2; exit 64 ;;
    esac
    f="$DIR/$slug.md"
    [ -f "$f" ] && { echo "lesson '$slug' exists — bump its count instead:"; grep -m1 '^seen:' "$f"; exit 1; }
    { echo "---"
      echo "slug: $slug"
      echo "destination: $dest"
      echo "action: $applies"
      echo "status: open"
      echo "seen: 1"
      echo "source: ${pr}"
      echo "---"
      echo
      cat
    } > "$f"
    echo "recorded $slug -> $dest ($applies)"
    ;;
  bump)
    f="$DIR/${2:?slug}.md"; [ -f "$f" ] || { echo "no such lesson" >&2; exit 1; }
    n=$(( $(grep -m1 '^seen:' "$f" | awk '{print $2}') + 1 ))
    sed -i '' "s/^seen: .*/seen: $n/" "$f" 2>/dev/null || sed -i "s/^seen: .*/seen: $n/" "$f"
    echo "$2 seen $n time(s)"
    [ "$n" -ge 3 ] && echo "  -> seen 3+ times: candidate for promotion to a CLAUDE.md hard rule."
    ;;
  list)
    printf "%-34s %-14s %-9s %-6s %s\n" SLUG DESTINATION ACTION SEEN STATUS
    for f in "$DIR"/*.md; do
      [ -f "$f" ] || continue
      printf "%-34s %-14s %-9s %-6s %s\n" \
        "$(basename "$f" .md)" \
        "$(grep -m1 '^destination:' "$f" | cut -d' ' -f2-)" \
        "$(grep -m1 '^action:' "$f" | cut -d' ' -f2-)" \
        "$(grep -m1 '^seen:' "$f" | cut -d' ' -f2-)" \
        "$(grep -m1 '^status:' "$f" | cut -d' ' -f2-)"
    done
    ;;
  pending)
    echo "Lessons that need a change in the PRODUCT repo — these are proposals, not applied:"
    for f in "$DIR"/*.md; do
      [ -f "$f" ] || continue
      grep -q '^action: propose' "$f" && grep -q '^status: open' "$f" || continue
      echo; echo "--- $(basename "$f" .md) ---"; sed -n '/^---$/,/^---$/!p' "$f" | head -20
    done
    ;;
  *) echo "usage: lesson.sh add|bump|list|pending" >&2; exit 64 ;;
esac
