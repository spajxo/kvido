#!/usr/bin/env bash
# current.sh — read/write state/current.md (atomic writes)
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/current.md"

case "${1:-}" in
  get)
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE"
    ;;
  set)
    mkdir -p "$(dirname "$STATE_FILE")"
    tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
    cat > "$tmp"
    mv "$tmp" "$STATE_FILE"
    ;;
  *)
    echo "Usage: current.sh <get|set>" >&2
    exit 1
    ;;
esac
