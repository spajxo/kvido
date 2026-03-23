#!/usr/bin/env bash
# heartbeat-state.sh — CRUD interface for state/heartbeat-state.json
# Usage:
#   heartbeat-state.sh get <key>
#   heartbeat-state.sh set <key> <value>
#   heartbeat-state.sh set-raw <key> <json_value>
#   heartbeat-state.sh increment <key>
#   heartbeat-state.sh get-json
#   heartbeat-state.sh log-activity <agent> <action> [--detail "..."] [--duration_ms N] [--tokens N] [--task_id N]
#
# Concurrency:
#   Write operations (set, set-raw, increment) are protected by flock on
#   STATE_FILE.lock. Read operations (get, get-json) do not need a lock —
#   they read the file after an atomic mv, which is atomic on Linux for
#   a reader on the same FS. Lock timeout is 10s; if the lock cannot be
#   acquired, the script fails with exit 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="${PWD}/state/heartbeat-state.json"
LOCK_FILE="${STATE_FILE}.lock"
LOCK_TIMEOUT=10  # seconds

_ensure_file() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
  fi
}

_atomic_write() {
  local content="$1"
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  echo "$content" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# _locked_write <key> <jq_filter> [jq_args...]
# Locks LOCK_FILE, performs jq transformation and atomically writes the result.
# The lock is released automatically when FD 200 is closed (on function return).
_locked_write() {
  local jq_filter="$1"
  shift
  (
    # Open lock FD and acquire exclusive lock (timeout LOCK_TIMEOUT s)
    exec 200>"$LOCK_FILE"
    if ! flock -w "$LOCK_TIMEOUT" 200; then
      echo "heartbeat-state.sh: timeout acquiring lock ($LOCK_TIMEOUT s)" >&2
      exit 1
    fi
    _ensure_file
    updated=$(jq "$@" "$jq_filter" "$STATE_FILE")
    _atomic_write "$updated"
  )
}

CMD="${1:-}"

case "$CMD" in
  get)
    key="${2:?Usage: heartbeat-state.sh get <key>}"
    _ensure_file
    jq -r --arg k "$key" '.[$k] // empty' "$STATE_FILE"
    ;;

  set)
    key="${2:?Usage: heartbeat-state.sh set <key> <value>}"
    value="${3?Usage: heartbeat-state.sh set <key> <value>}"
    _locked_write '.[$k] = $v' --arg k "$key" --arg v "$value"
    ;;

  set-raw)
    # set-raw <key> <json_value> — value is raw JSON (number, bool, array, object)
    key="${2:?Usage: heartbeat-state.sh set-raw <key> <json_value>}"
    raw="${3?Usage: heartbeat-state.sh set-raw <key> <json_value>}"
    _locked_write '.[$k] = $v' --arg k "$key" --argjson v "$raw"
    ;;

  increment)
    key="${2:?Usage: heartbeat-state.sh increment <key>}"
    _locked_write '.[$k] = ((.[$k] // 0) | tonumber + 1)' --arg k "$key"
    ;;

  get-json)
    _ensure_file
    cat "$STATE_FILE"
    ;;

  log-activity)
    # Backward compat — delegate to kvido log add
    shift  # remove "log-activity"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec bash "$SCRIPT_DIR/../log/log.sh" add "$@"
    ;;

  *)
    echo "Usage: heartbeat-state.sh <get|set|set-raw|increment|get-json|log-activity> [args...]" >&2
    exit 1
    ;;
esac
