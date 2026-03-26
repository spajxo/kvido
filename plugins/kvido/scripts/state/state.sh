#!/usr/bin/env bash
# state.sh — Unified key-value state store
# Storage: $KVIDO_HOME/state/state.json (flat JSON, dot-notation keys)
# Concurrency: flock for writes, atomic mv
#
# Usage:
#   state.sh get <key>           → print value (string), exit 1 if missing
#   state.sh get-json <key>      → print JSON value
#   state.sh set <key> <value>   → set string value
#   state.sh set-json <key> <json> → set JSON value
#   state.sh increment <key>     → atomic increment (counter)
#   state.sh delete <key>        → delete key
#   state.sh list [<prefix>]     → list keys, optionally filtered

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/state.json"
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

_locked_write() {
  local jq_filter="$1"
  shift
  (
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 200>"$LOCK_FILE"
    if ! flock -w "$LOCK_TIMEOUT" 200; then
      echo "state.sh: timeout acquiring lock ($LOCK_TIMEOUT s)" >&2
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
    key="${2:?Usage: state.sh get <key>}"
    _ensure_file
    val="$(jq -r --arg k "$key" '.[$k] // empty' "$STATE_FILE")"
    if [[ -z "$val" ]]; then
      exit 1
    fi
    echo "$val"
    ;;

  get-json)
    key="${2:?Usage: state.sh get-json <key>}"
    _ensure_file
    if ! jq -e "has(\$k)" --arg k "$key" "$STATE_FILE" > /dev/null 2>&1; then
      exit 1
    fi
    jq --arg k "$key" '.[$k]' "$STATE_FILE"
    ;;

  set)
    key="${2:?Usage: state.sh set <key> <value>}"
    value="${3?Usage: state.sh set <key> <value>}"
    _locked_write '.[$k] = $v' --arg k "$key" --arg v "$value"
    ;;

  set-json)
    key="${2:?Usage: state.sh set-json <key> <json>}"
    raw="${3?Usage: state.sh set-json <key> <json>}"
    _locked_write '.[$k] = $v' --arg k "$key" --argjson v "$raw"
    ;;

  increment)
    key="${2:?Usage: state.sh increment <key>}"
    _locked_write '.[$k] = ((.[$k] // 0) | tonumber + 1)' --arg k "$key"
    ;;

  delete)
    key="${2:?Usage: state.sh delete <key>}"
    _locked_write 'del(.[$k])' --arg k "$key"
    ;;

  list)
    prefix="${2:-}"
    _ensure_file
    if [[ -z "$prefix" ]]; then
      jq -r 'keys[]' "$STATE_FILE"
    else
      jq -r --arg p "$prefix" '[keys[] | select(startswith($p))] | .[]' "$STATE_FILE"
    fi
    ;;

  *)
    echo "Usage: state.sh <get|get-json|set|set-json|increment|delete|list> [args...]" >&2
    exit 1
    ;;
esac
