#!/usr/bin/env bash
# Where durable, cross-container state lives. Sourced by journal.sh, concept.sh and the
# dashboard so they cannot drift apart on the one thing they must agree about.
#
#   1. TLV_STATE_ROOT                 explicit override
#   2. $CLAUDE_CONFIG_DIR/talview     a devcontainer points this at a mounted volume, so
#                                     every devpod shares one library and a rebuild keeps it
#   3. $HOME/.talview                 a plain workstation
#
# Lessons keep honouring TLV_LESSONS_DIR for back-compat; everything else hangs off the root.

tlv_state_root() {
  if [ -n "${TLV_STATE_ROOT:-}" ]; then printf '%s' "$TLV_STATE_ROOT"; return; fi
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then printf '%s/talview' "$CLAUDE_CONFIG_DIR"; return; fi
  printf '%s/.talview' "${TLV_HOME:-$HOME}"
}
tlv_journal_dir()  { printf '%s/journal'  "$(tlv_state_root)"; }
tlv_concepts_dir() { printf '%s/concepts' "$(tlv_state_root)"; }
tlv_lessons_dir2() {
  if [ -n "${TLV_LESSONS_DIR:-}" ]; then printf '%s' "$TLV_LESSONS_DIR"; return; fi
  printf '%s/lessons' "$(tlv_state_root)"
}
tlv_today() { date +%Y-%m-%d; }
