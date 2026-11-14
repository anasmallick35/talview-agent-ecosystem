#!/usr/bin/env bash
# Deterministic tests for the talview-core gates.
#
# These are shell tests, not `claude plugin eval` cases, and deliberately so: eval runs
# start in an empty working directory with no git repo, no pnpm and no eslint, where
# every one of these hooks correctly does nothing. Model-call evals cannot observe
# behaviour that only exists inside a real repository. They cost nothing to run and are
# safe in CI.
#
#   ./gates.test.sh            run against a synthetic fixture repo
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_PLUGIN_ROOT="$(dirname "$HERE")"

pass=0; fail=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m %s\n     %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
check(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "expected '$3', got '$2'"; }

FIX="$(mktemp -d)/fixture"
export TLV_HOME="$(mktemp -d)"
trap 'rm -rf "$FIX" "$TLV_HOME"' EXIT

setup_repo() {
  mkdir -p "$FIX"; cd "$FIX"
  git init -q -b develop .
  git config user.email t@t; git config user.name t
  mkdir -p modules/demo/features/Thing v8/src
  echo '{}' > package.json
  printf 'export const A = 1;\n' > modules/demo/features/Thing/index.ts
  git add -A && git commit -qm base
  # mimic `origin/develop` so merge-base resolves without a real remote
  git update-ref refs/remotes/origin/develop refs/heads/develop
  git checkout -qb feat/demo
}

# A clean pass emits nothing at all, so an empty body is "no decision", not a parse error.
decision() { [ -z "$HOOK_OUT" ] && { echo none; return; }; printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "none"'; }

hook() { # hook <script> <json>   -> prints stdout, sets HOOK_RC
  local s="$1" j="$2"
  set +e; HOOK_OUT="$(printf '%s' "$j" | bash "$CLAUDE_PLUGIN_ROOT/scripts/$s" 2>/dev/null)"; HOOK_RC=$?; set -e
  printf '%s' "$HOOK_OUT"
}

echo "talview-core gates"
setup_repo

# ---------------------------------------------------------------- no run state
echo
echo "untracked branch (no run state)"
hook dod-gate.sh "{\"cwd\":\"$FIX\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}" >/dev/null
check "Stop gate is silent"            "$HOOK_RC" "0"
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push\"}}" >/dev/null
check "push is not denied"             "$(decision)" "none"

# ---------------------------------------------------------------- protected branch
echo
echo "protected branches"
git -C "$FIX" checkout -q develop
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin develop\"}}" >/dev/null
check "push to develop denied"         "$(decision)" "deny"

# A gate with a known way around it is decoration. Global options sit between the
# binary and the subcommand, and `git -C <dir> push` used to slip past the matcher.
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C $FIX push origin develop\"}}" >/dev/null
check "git -C ... push still caught"   "$(decision)" "deny"
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git --no-pager push origin develop\"}}" >/dev/null
check "git --opt push still caught"    "$(decision)" "deny"
git -C "$FIX" checkout -q feat/demo

# ------------------------------------------------------------------- cross-repo push
# Pushing repo B from a session rooted in repo A is ordinary. The gate must judge the
# branch it is actually about to push, not the session's — denying a push it was never
# asked about is how people learn to ignore a gate.
echo
echo "cross-repo push"
OTHER="$(mktemp -d)/other"; mkdir -p "$OTHER"
git init -q -b develop "$OTHER"
git -C "$OTHER" config user.email t@t; git -C "$OTHER" config user.name t
echo x > "$OTHER/f.txt"; git -C "$OTHER" add -A; git -C "$OTHER" commit -qm base
git -C "$OTHER" checkout -qb feat/elsewhere
git -C "$FIX" checkout -q develop
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $OTHER && git push -u origin feat/elsewhere\"}}" >/dev/null
check "judges the cd'd repo, not the session" "$(decision)" "none"
git -C "$OTHER" checkout -q develop
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $OTHER && git push origin develop\"}}" >/dev/null
check "protected branch in the cd'd repo denied" "$(decision)" "deny"

# Half a fix is worse than none: if the branch check follows the cd'd repo but the
# evidence ledger does not, the gate reads another workspace's proof. The ledger for
# the target repo lives under its own name in the state dir.
git -C "$OTHER" checkout -q feat/elsewhere
mkdir -p "$TLV_HOME/.talview/other/runs"
echo '{"ticket":"X-1","track":"feature","phase":"ship","armed":true,"waivers":{},"gateBlocks":0}' \
  > "$TLV_HOME/.talview/other/runs/feat-elsewhere.json"
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $OTHER && git push -u origin feat/elsewhere\"}}" >/dev/null
check "tracked target repo is denied on no evidence" "$(decision)" "deny"
printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'Never run on this branch' \
  && ok "reads the TARGET repo's ledger" || no "reads the TARGET repo's ledger"
git -C "$FIX" checkout -q feat/demo
rm -rf "$OTHER"

# ---------------------------------------------------------------- non-push bash
echo
echo "unrelated commands"
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"pnpm run test\"}}" >/dev/null
check "non-push command ignored"       "${HOOK_OUT:-empty}" "empty"
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh stack submit --auto\"}}" >/dev/null
check "gh stack passes through"        "${HOOK_OUT:-empty}" "empty"

# ---------------------------------------------------------------- armed gate
echo
echo "tracked run, gates armed"
RUNS="$TLV_HOME/.talview/fixture/runs"; mkdir -p "$RUNS"
echo '{"ticket":"T-1","track":"feature","phase":"test_unit","armed":true,"waivers":{},"gateBlocks":0}' > "$RUNS/feat-demo.json"
mkdir -p "$FIX/modules/demo/features/Widget"
printf 'export const W = (): null => null;\n' > "$FIX/modules/demo/features/Widget/index.tsx"

hook dod-gate.sh "{\"cwd\":\"$FIX\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}" >/dev/null
check "missing test blocks Stop"       "$HOOK_RC" "2"

jq '.waivers.tests = "fixture"' "$RUNS/feat-demo.json" > "$RUNS/t" && mv "$RUNS/t" "$RUNS/feat-demo.json"
hook dod-gate.sh "{\"cwd\":\"$FIX\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}" >/dev/null
check "waiver clears the block"        "$HOOK_RC" "0"

jq '.waivers = {} | .armed = false' "$RUNS/feat-demo.json" > "$RUNS/t" && mv "$RUNS/t" "$RUNS/feat-demo.json"
hook dod-gate.sh "{\"cwd\":\"$FIX\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}" >/dev/null
check "disarmed run does not block"    "$HOOK_RC" "0"

jq '.armed = true' "$RUNS/feat-demo.json" > "$RUNS/t" && mv "$RUNS/t" "$RUNS/feat-demo.json"
hook dod-gate.sh "{\"cwd\":\"$FIX\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":true}" >/dev/null
check "stop_hook_active short-circuits" "$HOOK_RC" "0"

# ---------------------------------------------------------------- loop breaker
echo
echo "loop breaker"
jq '.gateBlocks = 3' "$RUNS/feat-demo.json" > "$RUNS/t" && mv "$RUNS/t" "$RUNS/feat-demo.json"
hook dod-gate.sh "{\"cwd\":\"$FIX\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}" >/dev/null
check "releases at maxGateBlocks"      "$HOOK_RC" "0"
check "counter recorded"               "$(jq -r .gateBlocks "$RUNS/feat-demo.json")" "4"

# ---------------------------------------------------------------- evidence staleness
echo
echo "evidence staleness"
jq '.gateBlocks = 0 | .waivers.tests = "fixture"' "$RUNS/feat-demo.json" > "$RUNS/t" && mv "$RUNS/t" "$RUNS/feat-demo.json"
cd "$FIX"
for c in lint typecheck test; do bash "$CLAUDE_PLUGIN_ROOT/scripts/evidence.sh" record "$c" pass "fixture" >/dev/null; done
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push\"}}" >/dev/null
check "fresh evidence allows push"     "$(decision)" "none"

sleep 1; printf 'export const W2 = 2;\n' >> "$FIX/modules/demo/features/Widget/index.tsx"
hook pre-push-gate.sh "{\"cwd\":\"$FIX\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push\"}}" >/dev/null
check "edit after pass -> stale -> deny" "$(decision)" "deny"
printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q "source changed since" \
  && ok "reason names staleness" || no "reason names staleness" "got: $(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' | tr '\n' ' ')"

# ---------------------------------------------------------------- fail-open
echo
echo "fail-open outside a git repo"
NOGIT="$(mktemp -d)"
hook dod-gate.sh "{\"cwd\":\"$NOGIT\",\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}" >/dev/null
check "no repo -> silent"              "$HOOK_RC" "0"
hook post-edit-lint.sh "{\"cwd\":\"$NOGIT\",\"tool_input\":{\"file_path\":\"$NOGIT/x.tsx\"},\"hook_event_name\":\"PostToolUse\"}" >/dev/null
check "no eslint -> silent"            "${HOOK_OUT:-empty}" "empty"
rm -rf "$NOGIT"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
