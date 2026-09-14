#!/usr/bin/env bash
# Install the Talview delivery ecosystem on this machine.
#
#   ./bootstrap.sh                          # plugins only
#   ./bootstrap.sh --workspace ~/src/webclients   # plugins + that workspace's local config
#
# Idempotent: safe to re-run. Never overwrites an existing file; where config already
# exists it merges or reports and moves on.

set -uo pipefail
PLUGINS="talview-core tlv talview-verify talview-review talview-learn"
MARKET="anasmallick35/talview-agent-ecosystem"
MCP_SERVERS='["playwright","storybook","sentry"]'

ws=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) ws="${2:?path}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

say()  { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

say "Talview ecosystem — bootstrap"

# ── prerequisites ────────────────────────────────────────────────────────────
command -v claude >/dev/null || die "claude not found — npm install -g @anthropic-ai/claude-code"
command -v jq     >/dev/null || die "jq not found — every gate script needs it (brew install jq)"
command -v git    >/dev/null || die "git not found"
ok "claude $(claude --version 2>/dev/null | awk '{print $1}'), jq, git"

# ── marketplace ──────────────────────────────────────────────────────────────
say "Marketplace"
if claude plugin marketplace list 2>/dev/null | grep -q "talview"; then
  claude plugin marketplace update talview >/dev/null 2>&1
  ok "talview already registered — refreshed"
else
  claude plugin marketplace add "$MARKET" >/dev/null 2>&1 \
    && ok "added $MARKET" \
    || die "could not add marketplace $MARKET"
fi

# ── plugins ──────────────────────────────────────────────────────────────────
say "Plugins"
installed="$(claude plugin list 2>/dev/null)"
for p in $PLUGINS; do
  if printf '%s' "$installed" | grep -q "${p}@talview"; then
    claude plugin update "${p}@talview" >/dev/null 2>&1
    ok "$p (updated)"
  else
    claude plugin install "${p}@talview" >/dev/null 2>&1 \
      && ok "$p (installed)" \
      || warn "$p failed — run: claude plugin install ${p}@talview"
  fi
done

# ── workspace-local config ───────────────────────────────────────────────────
if [ -n "$ws" ]; then
  say "Workspace: $ws"
  [ -d "$ws" ] || die "no such directory: $ws"

  if [ -f "$ws/.mcp.json" ]; then
    local_settings="$ws/.claude/settings.local.json"
    mkdir -p "$ws/.claude"
    if [ -f "$local_settings" ]; then
      # Merge rather than replace — this file often carries other local preferences.
      merged="$(jq --argjson add "$MCP_SERVERS" \
        '.enabledMcpjsonServers = ((.enabledMcpjsonServers // []) + $add | unique)' \
        "$local_settings" 2>/dev/null)"
      if [ -n "$merged" ]; then
        printf '%s\n' "$merged" > "$local_settings"
        ok "merged MCP servers into existing settings.local.json"
      else
        warn "settings.local.json exists but is not valid JSON — left untouched"
      fi
    else
      printf '{\n  "enabledMcpjsonServers": %s\n}\n' "$MCP_SERVERS" > "$local_settings"
      ok "created settings.local.json (gitignored, so a clone never has one)"
    fi
  fi

  if [ ! -f "$ws/.env" ] && [ -f "$ws/.env.example" ]; then
    cp "$ws/.env.example" "$ws/.env"
    warn "created .env from .env.example — fill in TEST_AUTH_* and SENTRY_ACCESS_TOKEN"
  elif [ ! -f "$ws/.env" ]; then
    warn "no .env — verify_browser and the Sentry track need one"
  else
    ok ".env present"
  fi
fi

# ── report ───────────────────────────────────────────────────────────────────
doctor="$(ls -d "$HOME"/.claude/plugins/cache/talview/talview-core/*/scripts/doctor.sh 2>/dev/null | sort -V | tail -1)"
say "Environment"
if [ -n "$doctor" ] && [ -x "$doctor" ]; then
  if [ -n "$ws" ]; then (cd "$ws" && CLAUDE_PLUGIN_ROOT="$(dirname "$(dirname "$doctor")")" "$doctor")
  else CLAUDE_PLUGIN_ROOT="$(dirname "$(dirname "$doctor")")" "$doctor"; fi
else
  warn "doctor.sh not found — re-run after the plugins finish installing"
fi

say "Next"
echo "  Open Claude Code in the product repo and run:  /tlv:start <TICKET>"
echo "  Daily commands and the full flow: README.md in this repository."
