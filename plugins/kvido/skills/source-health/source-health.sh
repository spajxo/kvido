#!/usr/bin/env bash
# source-health.sh — read/write state/source-health.json
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/source-health.json"
LOCK_FILE="${STATE_FILE}.lock"
LOCK_TIMEOUT=10

_ensure_file() {
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
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

case "${1:-}" in
  get)
    _ensure_file
    source="${2:-}"
    if [[ -z "$source" ]]; then
      cat "$STATE_FILE"
    else
      jq -r --arg k "$source" '.[$k].status // empty' "$STATE_FILE"
    fi
    ;;
  set)
    source="${2:?Usage: source-health.sh set <source> <status>}"
    status="${3:?Usage: source-health.sh set <source> <status>}"
    now=$(date -Iseconds)
    _ensure_file
    mkdir -p "$(dirname "$LOCK_FILE")"
    (
      exec 200>"$LOCK_FILE"
      if ! flock -w "$LOCK_TIMEOUT" 200; then
        echo "source-health.sh: timeout acquiring lock" >&2
        exit 1
      fi
      _ensure_file
      updated=$(jq --arg k "$source" --arg s "$status" --arg t "$now" \
        '.[$k] = {status: $s, timestamp: $t}' "$STATE_FILE")
      _atomic_write "$updated"
    )
    ;;
  *)
    echo "Usage: source-health.sh <get|set> [args...]" >&2
    exit 1
    ;;
esac
