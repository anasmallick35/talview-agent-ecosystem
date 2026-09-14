#!/usr/bin/env bash
# Check every prerequisite the ecosystem depends on, and say what to do about each gap.
#
#   doctor.sh            check everything
#   doctor.sh --quiet    only print problems
#
# Nothing here installs or changes anything. It reports.

set -uo pipefail
quiet=0; [ "${1:-}" = "--quiet" ] && quiet=1
req_fail=0; opt_fail=0

g(){ printf '  \033[32m✓\033[0m  %-30s %s\n' "$1" "${2:-}"; }
r(){ printf '  \033[31m✗\033[0m  %-30s %s\n' "$1" "$2"; printf '     \033[2m→ %s\033[0m\n' "$3"; req_fail=$((req_fail+1)); }
y(){ printf '  \033[33m!\033[0m  %-30s %s\n' "$1" "$2"; printf '     \033[2m→ %s\033[0m\n' "$3"; opt_fail=$((opt_fail+1)); }
head(){ [ "$quiet" -eq 1 ] || { echo; printf '\033[1m%s\033[0m\n' "$1"; }; }
okay(){ [ "$quiet" -eq 1 ] || g "$@"; }

echo "Talview ecosystem — environment check"

# ─────────────────────────────────────────────────────────── toolchain
head "Toolchain"
if command -v node >/dev/null; then
  v="$(node -v | tr -d v)"; maj="${v%%.*}"
  if [ "$maj" -ge 22 ]; then okay "node" "v$v"
  else
    # A compatible version is often installed but not the shell default.
    cand="$(ls "$HOME/.nvm/versions/node" 2>/dev/null | sed 's/^v//' \
            | awk -F. '$1>=22' | sort -t. -k1,1n -k2,2n | tail -1)"
    if [ -n "$cand" ]; then
      y "node" "v$v active, v$cand installed" "nvm use $cand — engines require ^22.13.0 || >=24, and the repo has no .nvmrc to switch for you"
    else
      r "node" "v$v" "engines require ^22.13.0 || >=24 — install it (nvm install 24)"
    fi
  fi
else r "node" "not found" "install Node 22.13+ or 24+"; fi

command -v pnpm >/dev/null && okay "pnpm" "$(pnpm -v)" \
  || r "pnpm" "not found" "corepack enable && corepack prepare pnpm@12.3.4 --activate"
command -v jq   >/dev/null && okay "jq" "$(jq --version)" \
  || r "jq" "not found" "brew install jq — every gate script needs it and fails open without it"
command -v git  >/dev/null && okay "git" "$(git --version | awk '{print $3}')" \
  || r "git" "not found" "install git"
command -v claude >/dev/null && okay "claude code" "$(claude --version 2>/dev/null | awk '{print $1}')" \
  || r "claude code" "not found" "npm install -g @anthropic-ai/claude-code"

# ─────────────────────────────────────────────────────────── github
head "GitHub"
if command -v gh >/dev/null; then
  if gh auth status >/dev/null 2>&1; then
    okay "gh auth" "$(gh api user -q .login 2>/dev/null)"
  else r "gh auth" "not logged in" "gh auth login"; fi
else r "gh cli" "not found" "brew install gh — ADR PRs and comment harvesting need it"; fi

# ─────────────────────────────────────────────────────────── workspace
head "Workspace"
root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$root" ]; then
  okay "repo" "$(basename "$root")"
  [ -d "$root/.claude/skills" ] \
    && okay "workspace skills" "$(ls "$root/.claude/skills" | wc -l | tr -d ' ') found" \
    || r "workspace skills" ".claude/skills missing" "the tracks dispatch to these — run from the product repo checkout"
  [ -d "$root/node_modules" ] \
    && okay "dependencies" "installed" \
    || r "dependencies" "node_modules missing" "pnpm install"
  if [ -f "$root/eslint.config.mjs" ] || [ -f "$root/.eslintrc.json" ]; then
    okay "eslint config" "present"
  else y "eslint config" "none found" "the edit-time lint hook will stay silent here"; fi
else
  r "repo" "not inside a git repo" "cd into the product repo checkout first"
fi

# ─────────────────────────────────────────────────────────── plugins
head "Plugins"
if command -v claude >/dev/null; then
  inst="$(claude plugin list 2>/dev/null)"
  for p in talview-core tlv talview-verify talview-review talview-learn; do
    if printf '%s' "$inst" | grep -q "$p@talview"; then
      ver="$(printf '%s' "$inst" | grep -A3 "$p@talview" | grep -m1 'Version:' | awk '{print $2}')"
      okay "$p" "${ver:-installed}"
    else
      r "$p" "not installed" "claude plugin install $p@talview"
    fi
  done
fi

# ─────────────────────────────────────────────────────────── credentials
head "Workspace MCP servers"
# .claude/settings.local.json is gitignored, so a fresh clone has no MCP servers enabled
# and playwright/storybook/sentry silently never load.
if [ -n "$root" ] && [ -f "$root/.mcp.json" ]; then
  declared="$(jq -r '.mcpServers | keys[]' "$root/.mcp.json" 2>/dev/null | tr '\n' ' ')"
  local_settings="$root/.claude/settings.local.json"
  if [ -f "$local_settings" ]; then
    enabled="$(jq -r '.enabledMcpjsonServers[]?' "$local_settings" 2>/dev/null | tr '\n' ' ')"
    missing=""
    for d in $declared; do
      printf '%s' " $enabled " | grep -q " $d " || missing="$missing $d"
    done
    [ -z "$missing" ] && okay "enabled servers" "$enabled" \
      || y "enabled servers" "not enabled:$missing" "add them to .claude/settings.local.json under enabledMcpjsonServers"
  else
    y "settings.local.json" "absent — none of [$declared] are enabled" \
      "this file is gitignored, so a fresh clone has none. Create it: printf '{\"enabledMcpjsonServers\":[\"playwright\",\"storybook\",\"sentry\"]}' > .claude/settings.local.json"
  fi
fi

head "Credentials — browser verification (verify_browser phase)"
have_auth=0
for v in TEST_AUTH_USERNAME TEST_AUTH_PASSWORD TEST_AUTH_TENANT_ID; do
  val=""
  [ -n "$root" ] && [ -f "$root/.env" ] && val="$(grep -m1 "^${v}=" "$root/.env" 2>/dev/null | cut -d= -f2-)"
  [ -z "$val" ] && val="$(printenv "$v" 2>/dev/null)"
  [ -n "$val" ] && have_auth=$((have_auth+1))
done
if [ "$have_auth" -eq 3 ]; then
  okay "TEST_AUTH_*" "all three present"
elif [ -f "$HOME/.aws/credentials" ] || [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
  okay "TEST_AUTH_* fallback" "AWS Secrets Manager reachable ($have_auth/3 local)"
else
  y "TEST_AUTH_*" "$have_auth/3 present, no AWS fallback" \
    "add TEST_AUTH_USERNAME/PASSWORD/TENANT_ID to .env, or configure AWS creds. Without these, verify_browser cannot log in."
fi

head "Credentials — Sentry (sentry track)"
tok=""
[ -n "$root" ] && [ -f "$root/.env" ] && tok="$(grep -mE1 '^SENTRY_(ACCESS|AUTH)_TOKEN=' "$root/.env" 2>/dev/null | cut -d= -f2-)"
[ -z "$tok" ] && tok="${SENTRY_ACCESS_TOKEN:-${SENTRY_AUTH_TOKEN:-}}"
[ -n "$tok" ] && okay "SENTRY token" "present" \
  || y "SENTRY token" "absent" "add SENTRY_ACCESS_TOKEN to .env — the Sentry MCP server will not start without it"

head "Services — Storybook MCP (implement_ui, test_stories)"
if curl -s -o /dev/null -m 2 -w '%{http_code}' http://localhost:4450/mcp 2>/dev/null | grep -qE '^[234]'; then
  okay "storybook" "responding on :4450"
else
  y "storybook" "not running on :4450" "pnpm --filter @dx/storybook run serve — needed to verify Teserra props rather than guess them"
fi

head "Account-level connectors"
printf '  \033[2m%s\033[0m\n' "Linear and Figma are claude.ai connectors: OAuth, per-account, not per-repo."
printf '  \033[2m%s\033[0m\n' "Authorise once in Claude settings; they follow the account to any machine."
printf '  \033[2m%s\033[0m\n' "chrome-devtools and Context7 need no credentials."

# ─────────────────────────────────────────────────────────── summary
echo
if [ "$req_fail" -eq 0 ] && [ "$opt_fail" -eq 0 ]; then
  printf '\033[32mReady.\033[0m All tracks can run.\n'
elif [ "$req_fail" -eq 0 ]; then
  printf '\033[33m%s optional gap(s).\033[0m Core tracks run; the phases named above will degrade.\n' "$opt_fail"
else
  printf '\033[31m%s blocking gap(s)\033[0m and %s optional. Fix the blocking ones first.\n' "$req_fail" "$opt_fail"
fi
[ "$req_fail" -eq 0 ]
