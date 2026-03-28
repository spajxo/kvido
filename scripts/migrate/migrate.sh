#!/usr/bin/env bash
# migrate.sh — One-time lazy migrations from old formats to new
# Called from heartbeat.sh on startup. Idempotent.
#
# Migrates:
#   settings.json keys: sources.* → *, skills.* → * (v0.28.0)
#   state/heartbeat-state.json → state/state.json (heartbeat.* keys)
#   state/planner-state.json → state/state.json (planner.* keys)
#   state/source-health.json → state/state.json (source-health.* keys)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_SH="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts/state/state.sh"
CONFIG_KEYS_SH="$SCRIPT_DIR/config-keys.sh"

OLD_HEARTBEAT="${KVIDO_HOME}/state/heartbeat-state.json"
OLD_PLANNER="${KVIDO_HOME}/state/planner-state.json"

migrated=0

# Migrate settings.json config keys (v0.28.0)
if [[ -f "$CONFIG_KEYS_SH" ]]; then
  bash "$CONFIG_KEYS_SH"
  migrated=1
fi

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

  # Migrate schedule (string)
  schedule="$(jq -r '.schedule // empty' "$OLD_PLANNER" 2>/dev/null || echo "ERROR: failed to read schedule from planner.json (exit $?)" >&2)"
  if [[ -n "$schedule" ]]; then
    bash "$STATE_SH" set "planner.schedule" "$schedule"
  fi

  # Migrate last_run (JSON object → store as ISO timestamp if available)
  last_run_ts="$(jq -r '.last_run.ts // .last_run.timestamp // empty' "$OLD_PLANNER" 2>/dev/null || echo "ERROR: failed to read last_run from planner.json (exit $?)" >&2)"
  if [[ -n "$last_run_ts" ]]; then
    bash "$STATE_SH" set "planner.last_run" "$last_run_ts"
  fi

  # Discard old events and reminders (no longer used)

  rm "$OLD_PLANNER"
  rm -f "${OLD_PLANNER}.lock"
  migrated=1
fi

# Migrate source-health.json
OLD_SOURCE_HEALTH="${KVIDO_HOME}/state/source-health.json"
if [[ -f "$OLD_SOURCE_HEALTH" ]]; then
  for source in $(jq -r 'keys[]' "$OLD_SOURCE_HEALTH" 2>/dev/null); do
    if [[ "$(jq -r --arg k "$source" '.[$k] | type' "$OLD_SOURCE_HEALTH")" == "string" ]]; then
      # flat format: value is the status string directly
      status="$(jq -r --arg k "$source" '.[$k]' "$OLD_SOURCE_HEALTH")"
      ts=""
    else
      # nested format: value is object with .status and .timestamp
      status="$(jq -r --arg k "$source" '.[$k].status // empty' "$OLD_SOURCE_HEALTH")"
      ts="$(jq -r --arg k "$source" '.[$k].timestamp // empty' "$OLD_SOURCE_HEALTH")"
    fi
    [[ -n "$status" ]] && bash "$STATE_SH" set "source-health.${source}.status" "$status"
    [[ -n "$ts" ]] && bash "$STATE_SH" set "source-health.${source}.timestamp" "$ts"
  done
  rm "$OLD_SOURCE_HEALTH"
  rm -f "${OLD_SOURCE_HEALTH}.lock"
  migrated=1
fi

if [[ "$migrated" -eq 1 ]]; then
  echo "migrate: state migration complete" >&2
fi
