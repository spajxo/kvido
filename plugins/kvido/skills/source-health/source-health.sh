#!/usr/bin/env bash
# source-health.sh — thin wrapper over kvido state for source health tracking
# Data lives in state/state.json under source-health.* keys
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_SH="$(cd "$SCRIPT_DIR/.." && pwd)/state/state.sh"

case "${1:-}" in
  get)
    source="${2:-}"
    if [[ -z "$source" ]]; then
      # List all source health entries
      for key in $(bash "$STATE_SH" list "source-health." 2>/dev/null); do
        # Strip prefix, extract source name (source-health.<name>.status → <name>)
        name="${key#source-health.}"
        name="${name%.status}"
        [[ "$key" == *".status" ]] || continue
        status=$(bash "$STATE_SH" get "$key" 2>/dev/null || echo "unknown")
        ts=$(bash "$STATE_SH" get "source-health.${name}.timestamp" 2>/dev/null || echo "")
        echo "${name}: ${status} (${ts})"
      done
    else
      bash "$STATE_SH" get "source-health.${source}.status" 2>/dev/null
    fi
    ;;
  set)
    source="${2:?Usage: source-health.sh set <source> <status>}"
    status="${3:?Usage: source-health.sh set <source> <status>}"
    now=$(date -Iseconds)
    bash "$STATE_SH" set "source-health.${source}.status" "$status"
    bash "$STATE_SH" set "source-health.${source}.timestamp" "$now"
    ;;
  *)
    echo "Usage: source-health.sh <get|set> [args...]" >&2
    exit 1
    ;;
esac
