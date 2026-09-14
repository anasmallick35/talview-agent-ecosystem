#!/usr/bin/env bash
# Resolve the phase -> skill map against the workspace actually on disk.
#
#   skill-map.sh check              audit every mapped resource, list what is missing
#   skill-map.sh phase <name>       what to invoke for one phase, resolved
#   skill-map.sh track <name>       ordered phase list for a track
#
# A mapped skill that is absent is reported, never silently dropped. That is the
# whole point: a phase that quietly does nothing is how work goes missing.

set -uo pipefail

# Claude Code sets CLAUDE_PLUGIN_ROOT when a hook runs. Resolve it ourselves when a
# person runs the script straight from a shell, so both paths work identically.
: "${CLAUDE_PLUGIN_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MAP="${CLAUDE_PLUGIN_ROOT}/config/skill-map.json"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
WS="$ROOT/$(jq -r '.workspaceRoot // ".claude"' "$MAP")"

have_skill() { [ -f "$WS/skills/$1/SKILL.md" ]; }
have_agent() { [ -f "$WS/agents/$1.md" ] || [ "$1" = "Explore" ]; }

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
          plugin-skill)    echo "plugin     $name" ;;
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
      [ -n "$out" ] && { echo "  $p"; printf '%s' "$out"; }
    done
    if [ "$missing" -eq 0 ]; then
      echo "All mapped workspace skills and agents resolve. ($(jq -r '[.phases[].workspace[]?]|length' "$MAP") skill refs, $(jq -r '[.phases[].workspaceAgents[]?]|length' "$MAP") agent refs)"
    else
      echo
      echo "$missing unresolved reference(s). Affected phases degrade to their fallback — say so when they do."
    fi
    ;;

  *) echo "usage: skill-map.sh check | phase <name> | track <name>" >&2; exit 64 ;;
esac
