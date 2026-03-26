#!/usr/bin/env bash
# migrate.sh — One-time lazy migration from old state files to unified state
# Called from heartbeat.sh on startup. Idempotent.
#
# Migrates:
#   state/heartbeat-state.json → state/state.json (heartbeat.* keys)
#   state/planner-state.json → state/state.json (planner.* keys) + discards events

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_SH="$(cd "$SCRIPT_DIR/.." && pwd)/state/state.sh"

OLD_HEARTBEAT="${KVIDO_HOME}/state/heartbeat-state.json"
OLD_PLANNER="${KVIDO_HOME}/state/planner-state.json"

migrated=0

# Migrate heartbeat-state.json
if [[ -f "$OLD_HEARTBEAT" ]]; then
  for key in $(jq -r 'keys[]' "$OLD_HEARTBEAT" 2>/dev/null); do
    val="$(jq -r --arg k "$key" '.[$k] // empty' "$OLD_HEARTBEAT")"
    if [[ -n "$val" && "$val" != "null" ]]; then
      bash "$STATE_SH" set "heartbeat.${key}" "$val"
    fi
  done
  rm "$OLD_HEARTBEAT"
  rm -f "${OLD_HEARTBEAT}.lock"
  migrated=1
fi

# Migrate planner-state.json
if [[ -f "$OLD_PLANNER" ]]; then
  for key in $(jq -r '.timestamps | keys[]' "$OLD_PLANNER" 2>/dev/null); do
    val="$(jq -r --arg k "$key" '.timestamps[$k] // empty' "$OLD_PLANNER")"
    if [[ -n "$val" && "$val" != "null" ]]; then
      bash "$STATE_SH" set "planner.${key}" "$val"
    fi
  done

  for topic in $(jq -r '.interests | keys[]' "$OLD_PLANNER" 2>/dev/null); do
    val="$(jq -r --arg t "$topic" '.interests[$t].last_checked // empty' "$OLD_PLANNER")"
    if [[ -n "$val" && "$val" != "null" ]]; then
      bash "$STATE_SH" set "planner.interests.${topic}" "$val"
    fi
  done

  rm "$OLD_PLANNER"
  rm -f "${OLD_PLANNER}.lock"
  migrated=1
fi

if [[ "$migrated" -eq 1 ]]; then
  echo "migrate: state migration complete" >&2
fi
