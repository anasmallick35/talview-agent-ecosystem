#!/usr/bin/env bash
# Deterministic tests for the lesson ledger and the rule-injection path.
#
# The claim under test is the one the whole plugin rests on: a lesson recorded on one run
# reaches the next one. That is three links — ledger outside the plugin, `applied` moves
# it into active-rules.md, SessionStart injects that file — and each is asserted here.
# No model calls, safe in CI.
#
#   ./lessons.test.sh
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LEARN="$(dirname "$HERE")"
CORE="$(dirname "$LEARN")/talview-core"

pass=0; fail=0
ok()    { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); }
no()    { printf '  \033[31mFAIL\033[0m %s\n     %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
check() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected '$3', got '$2'"; }
has()   { printf '%s' "$2" | grep -q -- "$3" && ok "$1" || no "$1" "missing '$3'"; }
hasnt() { printf '%s' "$2" | grep -q -- "$3" && no "$1" "unexpectedly found '$3'" || ok "$1"; }

TMP="$(mktemp -d)"
export TLV_LESSONS_DIR="$TMP/lessons"
export TLV_HOME="$TMP/home"
FIX="$TMP/fixture"
trap 'rm -rf "$TMP"' EXIT

L="$LEARN/scripts/lesson.sh"

record() {
  "$L" add "$1" "$2" "https://example.test/pr/1" >/dev/null <<EOF
## What was said
> something

## What changed in response
nothing — pushed back, thread resolved unchanged

## Why it happened
the convention was never written down

## Proposed enforcement
$3
EOF
}

echo
echo "ledger location"
record rule-one skill-rule "Never ||-chain an ID to a secondary identifier."
[ -f "$TLV_LESSONS_DIR/rule-one.md" ] && ok "lesson written to TLV_LESSONS_DIR" || no "lesson written to TLV_LESSONS_DIR"
[ -f "$LEARN/lessons/rule-one.md" ] && no "ledger stays out of the plugin dir" "wrote into the install cache" || ok "ledger stays out of the plugin dir"

echo
echo "open vs applied"
"$L" rules >/dev/null
hasnt "an open lesson is not injected" "$(cat "$TLV_LESSONS_DIR/active-rules.md")" "rule-one"
"$L" applied rule-one "react-code-quality/reference/clean-code.md" >/dev/null
RULES="$(cat "$TLV_LESSONS_DIR/active-rules.md")"
has "applied lesson becomes an active rule" "$RULES" "rule-one"
has "rule text is the enforcement line"    "$RULES" "Never ||-chain an ID"
hasnt "rule text stops at the next heading" "$RULES" "Enforcement landed"

echo
echo "propose-only destinations never auto-apply"
record rule-two eslint-rule "Forbid cross-module imports."
check "eslint-rule is marked propose" "$(grep -m1 '^action:' "$TLV_LESSONS_DIR/rule-two.md" | cut -d' ' -f2)" "propose"
has "propose lessons surface in pending" "$("$L" pending)" "rule-two"

echo
echo "repetition"
"$L" bump rule-one >/dev/null; OUT="$("$L" bump rule-one)"
has "3rd sighting flags promotion" "$OUT" "candidate for promotion"

echo
echo "harvest queue"
"$L" queue add "https://example.test/pr/42" >/dev/null
check "queued PR is owed"      "$("$L" queue count)" "1"
"$L" queue add "https://example.test/pr/42" >/dev/null
check "queueing twice is idempotent" "$("$L" queue count)" "1"
"$L" queue done "https://example.test/pr/42" >/dev/null
check "harvested PR leaves the queue" "$("$L" queue count)" "0"

echo
echo "in-session capture"
"$L" capture argued-x adopted "Export keeps raw enums; a downstream importer parses them." >/dev/null
"$L" capture argued-y rejected "Said memoize the list; the cost was the query, not the render." >/dev/null
check "adopted outcome recorded"  "$(grep -m1 '^outcome:' "$TLV_LESSONS_DIR/argued-x.md" | cut -d' ' -f2)" "adopted"
check "rejected outcome recorded" "$(grep -m1 '^outcome:' "$TLV_LESSONS_DIR/argued-y.md" | cut -d' ' -f2)" "rejected"
check "capture lands as a draft"  "$(grep -m1 '^status:' "$TLV_LESSONS_DIR/argued-y.md" | cut -d' ' -f2)" "draft"
has "drafts are listable" "$("$L" drafts)" "argued-y"
"$L" rules >/dev/null
hasnt "a draft is never injected" "$(cat "$TLV_LESSONS_DIR/active-rules.md")" "argued-x"
"$L" capture argued-x adopted "came up again" >/dev/null
check "re-capture bumps instead of duplicating" "$(grep -m1 '^seen:' "$TLV_LESSONS_DIR/argued-x.md" | cut -d' ' -f2)" "2"
"$L" capture bad-outcome sideways "x" >/dev/null 2>&1
check "invalid outcome refused" "$?" "64"

echo
echo "a captured lesson injects its own text"
sed -i '' 's/^destination: unclassified/destination: skill-rule/; s/^status: draft/status: open/' "$TLV_LESSONS_DIR/argued-x.md" 2>/dev/null \
  || sed -i 's/^destination: unclassified/destination: skill-rule/; s/^status: draft/status: open/' "$TLV_LESSONS_DIR/argued-x.md"
"$L" applied argued-x "reference/i18n.md" >/dev/null
has "capture text becomes the rule" "$(cat "$TLV_LESSONS_DIR/active-rules.md")" "Export keeps raw enums"

echo
echo "applied refuses what it cannot inject"
"$L" capture argued-z open "something not yet classified" >/dev/null
rc=0; "$L" applied argued-z "somewhere" >/dev/null 2>&1 || rc=$?
check "unclassified draft refused"      "$rc" "65"
rc=0; "$L" applied rule-two "somewhere" >/dev/null 2>&1 || rc=$?
check "propose-only destination refused" "$rc" "65"
"$L" rules >/dev/null
hasnt "neither leaked into the rules" "$(cat "$TLV_LESSONS_DIR/active-rules.md")" "argued-z"

echo
echo "SessionStart injection"
mkdir -p "$FIX" && cd "$FIX"
git init -q -b develop . && git config user.email t@t && git config user.name t
echo '{}' > package.json && git add -A && git commit -qm base
git update-ref refs/remotes/origin/develop refs/heads/develop
IN="{\"cwd\":\"$FIX\"}"
CTX() { printf '%s' "$IN" | CLAUDE_PLUGIN_ROOT="$CORE" "$CORE/scripts/session-context.sh" | jq -r '.hookSpecificOutput.additionalContext // ""'; }

OUT="$(CTX)"
has "rules injected with no tracked run" "$OUT" "Rules learned from review"
has "the rule itself is present"         "$OUT" "rule-one"

"$L" queue add "https://example.test/pr/7" >/dev/null
has "unharvested PRs are reported" "$(CTX)" "never had their review harvested"

mkdir -p "$TLV_HOME/.talview/fixture/runs"
echo '{"ticket":"T-1","track":"feature","phase":"implement_ui","armed":false,"waivers":{}}' \
  > "$TLV_HOME/.talview/fixture/runs/develop.json"
OUT="$(CTX)"
has "tracked run still reports run state" "$OUT" "T-1"
has "tracked run also carries the rules"  "$OUT" "Rules learned from review"

OUT="$(TLV_LESSONS_DIR="$TMP/none" CTX)"
hasnt "no ledger -> no rules section" "$OUT" "Rules learned from review"
has   "no ledger -> run state intact" "$OUT" "T-1"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
