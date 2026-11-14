#!/usr/bin/env bash
# Tests for the work journal, the concept library and the dashboard server.
# No model calls; the server is started on an ephemeral port and torn down.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$(dirname "$HERE")/scripts"

pass=0; fail=0
ok()    { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); }
no()    { printf '  \033[31mFAIL\033[0m %s\n     %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
check() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected '$3', got '$2'"; }
has()   { printf '%s' "$2" | grep -q -- "$3" && ok "$1" || no "$1" "missing '$3'"; }

TMP="$(mktemp -d)"; export TLV_STATE_ROOT="$TMP/state"; SRV=""; PORT=""
trap '[ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT
J="$S/journal.sh"; C="$S/concept.sh"

echo
echo "journal"
ID="$("$J" open WFT-1 feature demo-repo demo-branch)"
has "entry id is date-scoped" "$ID" "WFT-1"
check "re-opening the same ticket today is the same entry" "$("$J" open WFT-1 feature demo-repo demo-branch)" "$ID"
"$J" set "$ID" title "A thing" >/dev/null
"$J" add "$ID" prs "https://x/pull/1" >/dev/null
"$J" add "$ID" prs "https://x/pull/1" >/dev/null
check "lists de-duplicate" "$("$J" show "$ID" | jq '.prs|length')" "1"
has "entry with no concepts is flagged" "$("$J" open-entries)" "WFT-1"

echo
echo "concepts"
printf '## How it actually works\nmechanism\n\n## Revise with\nQ: why?\n' \
  | "$C" add demo-concept --tags "shell,ci" --entry "$ID" --title "Demo" >/dev/null
has "concept is linked back to the entry" "$("$J" show "$ID" | jq -r '.concepts[]')" "demo-concept"
rc=0; printf 'x\n' | "$C" add demo-concept >/dev/null 2>&1 || rc=$?
check "duplicate add refused (bump instead)" "$rc" "1"
"$C" bump demo-concept >/dev/null
check "bump increments seen" "$(grep -m1 '^seen:' "$TLV_STATE_ROOT/concepts/demo-concept.md" | cut -d' ' -f2)" "2"
has "entry no longer flagged as empty" "$("$J" open-entries)" "every entry has at least one"

echo
echo "revision ladder"
check "a new concept is due at once" "$("$C" count-due)" "1"
"$C" reviewed demo-concept known >/dev/null
check "reviewed concept is not due"  "$("$C" count-due)" "0"
check "stage advanced"               "$(grep -m1 '^stage:' "$TLV_STATE_ROOT/concepts/demo-concept.md" | cut -d' ' -f2)" "1"
has "lastReview persisted (not the empty-value bug)" \
    "$(grep -m1 '^lastReview:' "$TLV_STATE_ROOT/concepts/demo-concept.md")" "$(date +%Y-%m-%d)"
"$C" reviewed demo-concept shaky >/dev/null
check "shaky resets to the bottom rung" "$(grep -m1 '^stage:' "$TLV_STATE_ROOT/concepts/demo-concept.md" | cut -d' ' -f2)" "0"
check "shaky is counted"                "$(grep -m1 '^shaky:' "$TLV_STATE_ROOT/concepts/demo-concept.md" | cut -d' ' -f2)" "1"

echo
echo "dashboard server"
if command -v node >/dev/null 2>&1; then
  PORT=$(( 14400 + RANDOM % 400 ))
  # disown so the shell does not print a "Terminated" job notice when the trap kills it
  node "$S/dashboard.mjs" --port "$PORT" >/dev/null 2>&1 &
  SRV=$!; disown "$SRV" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 0.3; curl -sf -m 1 "http://localhost:$PORT" -o "$TMP/p.html" && break; done
  if [ -s "$TMP/p.html" ]; then
    ok "serves a page"
    has "renders the concept"  "$(cat "$TMP/p.html")" "demo-concept"
    has "renders the entry"    "$(cat "$TMP/p.html")" "WFT-1"
    R="$(curl -sf -X POST "http://localhost:$PORT/api/review" -H 'content-type: application/json' -d '{"slug":"demo-concept","result":"known"}')"
    has "review endpoint responds" "$R" '"ok":true'
    has "review WRITES BACK to the ledger — not browser state" \
        "$(grep -m1 '^stage:' "$TLV_STATE_ROOT/concepts/demo-concept.md")" "stage: 1"
    # The shell stamps a local date; a UTC stamp in node would disagree by a day east of GMT.
    has "server date agrees with the shell" \
        "$(grep -m1 '^lastReview:' "$TLV_STATE_ROOT/concepts/demo-concept.md")" "$(date +%Y-%m-%d)"
    R="$(curl -s -X POST "http://localhost:$PORT/api/review" -H 'content-type: application/json' -d '{"slug":"nope","result":"known"}')"
    has "unknown concept rejected" "$R" '"ok":false'
  else
    no "serves a page" "no response on :$PORT"
  fi
else
  ok "dashboard server (node absent; skipped)"
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
