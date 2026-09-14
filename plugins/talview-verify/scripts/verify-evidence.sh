#!/usr/bin/env bash
# Evidence artifacts for a browser verification run. Lives outside the target repo.
#   verify-evidence.sh init          create the run's evidence dir, print its path
#   verify-evidence.sh note          append stdin as a timestamped note
#   verify-evidence.sh path          print the dir
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
name="$(basename "$root" | tr -cd '[:alnum:]._-')"
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
slug="$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]._-')"
dir="${TLV_HOME:-$HOME}/.talview/${name:-workspace}/runs/${slug}.verify"

case "${1:-path}" in
  init) mkdir -p "$dir"; echo "$dir" ;;
  note) mkdir -p "$dir"; { echo; echo "## $(date -u '+%Y-%m-%dT%H:%M:%SZ')"; cat; } >> "$dir/findings.md"; echo "appended to $dir/findings.md" ;;
  path) echo "$dir" ;;
  *) echo "usage: verify-evidence.sh init|note|path" >&2; exit 64 ;;
esac
