#!/usr/bin/env bash
# Shared helpers for Talview Core hooks.
# Every function here fails OPEN: a broken hook must never block a session.

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

TLV_INPUT="${TLV_INPUT:-}"

tlv_have() { command -v "$1" >/dev/null 2>&1; }

# Read hook JSON from stdin once, cache it in TLV_INPUT.
tlv_read_input() {
  if [ -z "$TLV_INPUT" ]; then
    TLV_INPUT="$(cat)"
  fi
  printf '%s' "$TLV_INPUT"
}

tlv_field() {
  tlv_have jq || { printf ''; return; }
  tlv_read_input | jq -r "${1} // empty" 2>/dev/null || printf ''
}

# TLV_ROOT_OVERRIDE lets a hook that has worked out the real target repository tell
# every other helper about it. Without it the protected-branch check and the evidence
# ledger can disagree about which repo is being judged — the worst kind of gate, one
# that is half right.
tlv_repo_root() {
  local cwd
  if [ -n "${TLV_ROOT_OVERRIDE:-}" ] && [ -d "${TLV_ROOT_OVERRIDE}" ]; then
    printf '%s' "$TLV_ROOT_OVERRIDE"; return
  fi
  cwd="$(tlv_field '.cwd')"
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
  git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd"
}

tlv_branch() {
  git -C "$(tlv_repo_root)" rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''
}

# <state-dir>/config.json overrides plugin defaults, per workspace.
tlv_config() {
  local root defaults override
  root="$(tlv_repo_root)"
  defaults="${CLAUDE_PLUGIN_ROOT}/config/defaults.json"
  override="$(tlv_state_dir)/config.json"
  if tlv_have jq && [ -f "$override" ]; then
    jq -s '.[0] * .[1]' "$defaults" "$override" 2>/dev/null || cat "$defaults"
  else
    cat "$defaults" 2>/dev/null || printf '{}'
  fi
}

tlv_cfg() { tlv_config | jq -r "${1} // empty" 2>/dev/null || printf ''; }

tlv_base_branch() {
  local b; b="$(tlv_cfg '.baseBranch')"; printf '%s' "${b:-develop}"
}

# Agent state lives OUTSIDE the target repo. The product repo is a deliverable,
# not a scratchpad: nothing here ever needs a .gitignore entry in someone else's
# monorepo. Keyed by repo name so several checkouts can run side by side.
tlv_state_dir() {
  local root name
  root="$(tlv_repo_root)"
  name="$(basename "$root" | tr -cd '[:alnum:]._-')"
  printf '%s/.talview/%s' "${TLV_HOME:-$HOME}" "${name:-workspace}"
}

# Run-state file for the current branch. Absent == untracked ad-hoc work.
tlv_run_file() {
  local branch slug
  branch="$(tlv_branch)"
  [ -n "$branch" ] || return 1
  slug="$(printf '%s' "$branch" | tr '/' '-' | tr -cd '[:alnum:]._-')"
  printf '%s/runs/%s.json' "$(tlv_state_dir)" "$slug"
}

tlv_run_phase() {
  local f; f="$(tlv_run_file)" || { printf ''; return; }
  [ -f "$f" ] || { printf ''; return; }
  jq -r '.phase // empty' "$f" 2>/dev/null || printf ''
}

# The merge-base with the base branch. Diffing against origin/<base> directly is
# wrong: it also reports everything merged into the base since this branch forked.
tlv_merge_base() {
  local root base
  root="$(tlv_repo_root)"; base="$(tlv_base_branch)"
  git -C "$root" merge-base "origin/$base" HEAD 2>/dev/null \
    || git -C "$root" merge-base "$base" HEAD 2>/dev/null \
    || printf 'origin/%s' "$base"
}

# Files this branch owns: committed since divergence, plus uncommitted, plus untracked.
tlv_changed_files() {
  local root mb
  root="$(tlv_repo_root)"; mb="$(tlv_merge_base)"
  {
    git -C "$root" diff --name-only --diff-filter=ACMR "$mb" 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | grep -v '^$' \
    | grep -vE '(^|/)(generated|__mocks__|__fixtures__|node_modules|dist|coverage)/' \
    | grep -vE '(^|/)\.storybook/|(^|/)storybook/' || true
}

# JSON-escape stdin into a bare string body (no surrounding quotes).
tlv_escape() { jq -Rs . 2>/dev/null | sed 's/^"//; s/"$//'; }

tlv_emit_context() {
  local event="$1" text="$2"
  tlv_have jq || return 0
  jq -n --arg e "$event" --arg c "$text" \
    '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
}

tlv_emit_deny() {
  local event="$1" reason="$2"
  tlv_have jq || return 0
  jq -n --arg e "$event" --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:$e, permissionDecision:"deny", permissionDecisionReason:$r}}'
}
