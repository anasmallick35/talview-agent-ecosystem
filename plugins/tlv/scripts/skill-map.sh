#!/usr/bin/env bash
# Resolve the phase -> skill map against the workspace actually on disk.
#
#   skill-map.sh check              audit every mapped resource, list what is missing
#   skill-map.sh phase <name>       what to invoke for one phase, resolved
#   skill-map.sh track <name>       ordered phase list for a track
#
# A mapped skill that is absent is reported, never silently dropped. That is the
# whole point: a phase that quietly does nothing is how work goes missing.
#
# Plugin skills are validated too. They are written as the name you actually invoke
# (`talview-learn:learn`), because a reference nobody can call is the same defect as a
# reference that does not exist — and it is harder to notice.

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MAP="${CLAUDE_PLUGIN_ROOT}/config/skill-map.json"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
WS="$ROOT/$(jq -r '.workspaceRoot // ".claude"' "$MAP")"

have_skill() { [ -f "$WS/skills/$1/SKILL.md" ]; }
have_agent() { [ -f "$WS/agents/$1.md" ] || [ "$1" = "Explore" ]; }

# `<plugin>:<skill>` — look beside this plugin first (a local checkout), then in the
# install cache. Either location means the skill is callable.
have_plugin_skill() {
  local ref="$1" plug skill sibling
  case "$ref" in
    *:*) plug="${ref%%:*}"; skill="${ref#*:}" ;;
    *)   return 1 ;;
  esac
  sibling="$(dirname "$CLAUDE_PLUGIN_ROOT")/$plug/skills/$skill/SKILL.md"
  [ -f "$sibling" ] && return 0
  compgen -G "$HOME/.claude/plugins/cache/*/$plug/*/skills/$skill/SKILL.md" >/dev/null 2>&1
}

case "${1:-check}" in
  track)
    jq -r --arg t "${2:?track}" '.tracks[$t][]?' "$MAP"
    ;;

  phase)
    p="${2:?phase}"
    jq -r --arg p "$p" '
      .phases[$p] // empty
      | [ (.workspace[]?       | "workspace-skill\t" + .),
          (.workspaceAgents[]? | "workspace-agent\t" + .),
          (.plugin[]?          | "plugin-skill\t"    + .),
          (.mcp[]?             | "mcp\t"             + .),
          (.tools[]?           | "tool\t"            + .),
          (if .output   then "output\t"   + .output   else empty end),
          (if .fallback then "fallback\t" + .fallback else empty end)
        ] | .[]' "$MAP" \
    | while IFS=$'\t' read -r kind name; do
        case "$kind" in
          workspace-skill) have_skill "$name" && echo "skill      $name" || echo "MISSING    skill $name" ;;
          workspace-agent) have_agent "$name" && echo "agent      $name" || echo "MISSING    agent $name" ;;
          plugin-skill)    have_plugin_skill "$name" && echo "plugin     /$name" || echo "MISSING    plugin skill /$name" ;;
          mcp)             echo "mcp        $name" ;;
          tool)            command -v "$name" >/dev/null 2>&1 && echo "tool       $name (on PATH)" || echo "tool       $name (via pnpm dlx)" ;;
          output)          echo "output     $name" ;;
          fallback)        echo "fallback   $name" ;;
        esac
      done
    ;;

  check)
    missing=0
    echo "workspace: $WS"
    echo
    for p in $(jq -r '.phases|keys_unsorted[]' "$MAP"); do
      out=""
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        have_skill "$s" || { out="${out}    missing skill: $s"$'\n'; missing=$((missing+1)); }
      done < <(jq -r --arg p "$p" '.phases[$p].workspace[]?' "$MAP")
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        have_agent "$a" || { out="${out}    missing agent: $a"$'\n'; missing=$((missing+1)); }
      done < <(jq -r --arg p "$p" '.phases[$p].workspaceAgents[]?' "$MAP")
      while IFS= read -r g; do
        [ -n "$g" ] || continue
        have_plugin_skill "$g" || { out="${out}    missing plugin skill: /$g"$'\n'; missing=$((missing+1)); }
      done < <(jq -r --arg p "$p" '.phases[$p].plugin[]?' "$MAP")
      [ -n "$out" ] && { echo "  $p"; printf '%s' "$out"; }
    done
    if [ "$missing" -eq 0 ]; then
      echo "All mapped skills and agents resolve. ($(jq -r '[.phases[].workspace[]?]|length' "$MAP") workspace skills, $(jq -r '[.phases[].workspaceAgents[]?]|length' "$MAP") agents, $(jq -r '[.phases[].plugin[]?]|length' "$MAP") plugin skills)"
    else
      echo
      echo "$missing unresolved reference(s). Affected phases degrade to their fallback — say so when they do."
    fi
    ;;

  *) echo "usage: skill-map.sh check | phase <name> | track <name>" >&2; exit 64 ;;
esac
