#!/usr/bin/env bash
# Artifact-coverage checks for the current branch. Prints a human-readable report
# on stdout. Exit 0 = clean, 1 = gaps found. Shared by the Stop gate and the
# pre-push gate so both enforce exactly the same definition of done.
#
# Requires TLV_INPUT to be exported (hook JSON) or falls back to $PWD.

set -uo pipefail
. "${CLAUDE_PLUGIN_ROOT}/scripts/tlv-lib.sh"
tlv_have jq || exit 0

root="$(tlv_repo_root)"; cd "$root" || exit 0
run_file="$(tlv_run_file)" || run_file=""
waived() { [ -n "$run_file" ] && [ -f "$run_file" ] && jq -e --arg k "$1" '.waivers[$k] // empty' "$run_file" >/dev/null 2>&1; }

changed="$(tlv_changed_files)"
[ -n "$changed" ] || exit 0

missing_tests=(); missing_stories=(); missing_e2e=(); i18n_gaps=()

has_test() {
  local d="$1" b="$2"
  [ -f "$d/$b.test.tsx" ] || [ -f "$d/$b.test.ts" ] || [ -f "$d/$b.spec.tsx" ] \
    || [ -f "$d/tests/$b.test.tsx" ] || [ -f "$d/tests/index.test.tsx" ] \
    || [ -f "$d/__tests__/$b.test.tsx" ]
}
has_story() {
  local d="$1" b="$2"; local p; p="$(basename "$d")"
  [ -f "$d/$b.stories.tsx" ] || [ -f "$d/$p.stories.tsx" ]
}

while IFS= read -r f; do
  case "$f" in
    *.test.tsx|*.test.ts|*.spec.tsx|*.spec.ts|*.stories.tsx|*.cy.ts|*.d.ts) continue ;;
    */cypress/*) continue ;;
    *.tsx) ;; *) continue ;;
  esac
  case "${f%%/*}" in v8|modules) ;; *) continue ;; esac
  [ -f "$f" ] || continue
  d="$(dirname "$f")"; b="$(basename "$f" .tsx)"

  [ "$(tlv_cfg '.dod.requireUnitTest')" != "false" ] && ! waived tests \
    && { has_test "$d" "$b" || missing_tests+=("$f"); }

  case "$f" in */components/*|*/atoms/*|*/molecules/*|*/organisms/*)
    [ "$(tlv_cfg '.dod.requireStories')" != "false" ] && ! waived stories \
      && { has_story "$d" "$b" || missing_stories+=("$f"); } ;;
  esac
done <<< "$changed"

if [ "$(tlv_cfg '.dod.requireE2E')" != "false" ] && ! waived e2e; then
  new_pages="$(git diff --name-only --diff-filter=A "$(tlv_merge_base)" 2>/dev/null \
    | grep -E '(^|/)pages/.*/index\.tsx$' || true)"
  if [ -n "$new_pages" ] && ! printf '%s\n' "$changed" | grep -qE '\.cy\.ts$'; then
    while IFS= read -r p; do [ -n "$p" ] && missing_e2e+=("$p"); done <<< "$new_pages"
  fi
fi

# Parity is enforced for the keys THIS BRANCH adds to en.json, not for pre-existing
# drift — otherwise every branch inherits the backlog and the gate becomes noise.
if [ "$(tlv_cfg '.dod.requireI18nParity')" != "false" ] && ! waived i18n; then
  mb="$(tlv_merge_base)"
  lds="$(printf '%s\n' "$changed" | grep -E '/locale/en\.json$' \
    | xargs -n1 dirname 2>/dev/null | sort -u || true)"
  while IFS= read -r ld; do
    [ -n "$ld" ] && [ -f "$ld/en.json" ] || continue
    added="$(git show "$mb:$ld/en.json" 2>/dev/null \
      | jq -r --slurpfile now "$ld/en.json" '($now[0]|keys_unsorted) - keys_unsorted | .[]' 2>/dev/null)"
    if [ -z "$added" ]; then
      added="$(jq -r 'keys_unsorted | .[]' "$ld/en.json" 2>/dev/null)"   # new locale dir
    fi
    [ -n "$added" ] || continue
    for other in "$ld"/*.json; do
      [ "$other" = "$ld/en.json" ] && continue; [ -f "$other" ] || continue
      miss="$(printf '%s\n' "$added" | jq -R -s -r --slurpfile o "$other" \
        'split("\n") | map(select(length>0)) | map(select(. as $k | ($o[0]|has($k)) | not)) | .[]' 2>/dev/null)"
      cnt="$(printf '%s\n' "$miss" | grep -c . || true)"
      [ "${cnt:-0}" -gt 0 ] && i18n_gaps+=("$(basename "$other"): missing $cnt of this branch's new key(s) — e.g. $(printf '%s' "$miss" | head -3 | tr '\n' ' ')")
    done
  done <<< "$lds"
fi

total=$(( ${#missing_tests[@]} + ${#missing_stories[@]} + ${#missing_e2e[@]} + ${#i18n_gaps[@]} ))
[ "$total" -eq 0 ] && exit 0

[ ${#missing_tests[@]}   -gt 0 ] && { echo "Missing unit tests (${#missing_tests[@]}):";      printf '  - %s\n' "${missing_tests[@]}";   echo; }
[ ${#missing_stories[@]} -gt 0 ] && { echo "Missing stories (${#missing_stories[@]}):";       printf '  - %s\n' "${missing_stories[@]}"; echo; }
[ ${#missing_e2e[@]}     -gt 0 ] && { echo "New page(s) with no Cypress spec touched:";       printf '  - %s\n' "${missing_e2e[@]}";     echo; }
[ ${#i18n_gaps[@]}       -gt 0 ] && { echo "Locale parity gaps (CLAUDE.md: every id in every locale):"; printf '  - %s\n' "${i18n_gaps[@]}"; echo; }
exit 1
