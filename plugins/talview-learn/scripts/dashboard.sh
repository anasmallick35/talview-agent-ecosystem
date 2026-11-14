#!/usr/bin/env bash
# Build and serve the personal learning dashboard. Local only — nothing is deployed.
#
#   dashboard.sh serve [port]     default 4455
#   dashboard.sh status           what the library holds right now
#
# Node, no dependencies. The devcontainer runs as `node`, so this behaves identically on
# a laptop and inside a devpod; the port is auto-forwarded by VS Code / DevPod on access.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/tlv-state.sh"

command -v node >/dev/null 2>&1 || { echo "node is required for the dashboard (not found on PATH)" >&2; exit 1; }

case "${1:-serve}" in
  serve)
    port="${2:-${TLV_DASHBOARD_PORT:-4455}}"
    # Already up? Say so instead of failing on EADDRINUSE — the page rebuilds per request,
    # so a server started an hour ago is already showing current data.
    if command -v curl >/dev/null 2>&1 && curl -sf -m 1 "http://localhost:$port" -o /dev/null; then
      echo "dashboard already serving: http://localhost:$port"
      exit 0
    fi
    exec node "$HERE/dashboard.mjs" --port "$port"
    ;;
  status)
    echo "state root : $(tlv_state_root)"
    echo "entries    : $(ls "$(tlv_journal_dir)"/*.json 2>/dev/null | wc -l | tr -d ' ')"
    echo "concepts   : $(ls "$(tlv_concepts_dir)"/*.md 2>/dev/null | wc -l | tr -d ' ')"
    echo "due today  : $("$HERE/concept.sh" count-due 2>/dev/null || echo '?')"
    ;;
  *) echo "usage: dashboard.sh serve [port] | status" >&2; exit 64 ;;
esac
