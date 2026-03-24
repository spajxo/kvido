#!/usr/bin/env bash
# planner-state.sh — CRUD interface for state/planner-state.json
# Usage:
#   planner-state.sh reset
#   planner-state.sh event check|report|list|cleanup [args...]
#   planner-state.sh timestamp get|set <key> [value]
#   planner-state.sh reminder get|set <slug>
#   planner-state.sh interests get|set|list [topic]
#   planner-state.sh schedule get|set
#   planner-state.sh last-run get|set
#
# Concurrency:
#   Write operations are protected by flock on STATE_FILE.lock.
#   Read operations do not need a lock — they read after an atomic mv.
#   Lock timeout is 10s; if the lock cannot be acquired the script fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/planner-state.json"
LOCK_FILE="${STATE_FILE}.lock"
LOCK_TIMEOUT=10  # seconds

_ensure_file() {
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    echo '{"last_run":{},"timestamps":{},"events":{},"reminders":{},"interests":{},"schedule":""}' > "$STATE_FILE"
  fi
}

_atomic_write() {
  local content="$1"
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  echo "$content" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# _locked_write <jq_filter> [jq_args...]
# Locks LOCK_FILE, performs jq transformation and atomically writes the result.
# The lock is released automatically when FD 200 is closed (on function return).
_locked_write() {
  local jq_filter="$1"
  shift
  (
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 200>"$LOCK_FILE"
    if ! flock -w "$LOCK_TIMEOUT" 200; then
      echo "planner-state.sh: timeout acquiring lock ($LOCK_TIMEOUT s)" >&2
      exit 1
    fi
    _ensure_file
    updated=$(jq "$@" "$jq_filter" "$STATE_FILE")
    _atomic_write "$updated"
  )
}

CMD="${1:-}"

case "$CMD" in
  reset)
    mkdir -p "$(dirname "$STATE_FILE")"
    _atomic_write '{"last_run":{},"timestamps":{},"events":{},"reminders":{},"interests":{},"schedule":""}'
    ;;

  event)
    subcmd="${2:?Usage: planner-state.sh event <check|report|list|cleanup> [args...]}"
    case "$subcmd" in
      check)
        key="${3:?Usage: planner-state.sh event check <key>}"
        _ensure_file
        jq -e --arg k "$key" '.events | has($k)' "$STATE_FILE" > /dev/null
        ;;

      report)
        key="${3:?Usage: planner-state.sh event report <key>}"
        now="$(date -Iseconds)"
        _locked_write '
          if .events[$k] then
            .events[$k].last_reported = $now
          else
            .events[$k] = {"first_seen": $now, "last_reported": $now}
          end
        ' --arg k "$key" --arg now "$now"
        ;;

      list)
        _ensure_file
        jq '.events' "$STATE_FILE"
        ;;

      cleanup)
        max_age="72h"
        shift 2  # remove "event cleanup"
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --max-age)
              max_age="${2:?--max-age requires a value}"
              shift 2
              ;;
            *)
              echo "planner-state.sh: unknown option: $1" >&2
              exit 1
              ;;
          esac
        done
        hours="${max_age%h}"
        cutoff="$(date -Iseconds -d "-${hours} hours")"
        _locked_write '
          .events |= ([to_entries[] | select(.value.last_reported >= $cutoff)] | from_entries)
        ' --arg cutoff "$cutoff"
        ;;

      *)
        echo "Usage: planner-state.sh event <check|report|list|cleanup> [args...]" >&2
        exit 1
        ;;
    esac
    ;;

  timestamp)
    subcmd="${2:?Usage: planner-state.sh timestamp <get|set> <key> [value]}"
    case "$subcmd" in
      get)
        key="${3:?Usage: planner-state.sh timestamp get <key>}"
        _ensure_file
        val="$(jq -r --arg k "$key" '.timestamps[$k] // empty' "$STATE_FILE")"
        if [[ -z "$val" ]]; then
          exit 1
        fi
        echo "$val"
        ;;

      set)
        key="${3:?Usage: planner-state.sh timestamp set <key> <value>}"
        value="${4:?Usage: planner-state.sh timestamp set <key> <value>}"
        _locked_write '.timestamps[$k] = $v' --arg k "$key" --arg v "$value"
        ;;

      *)
        echo "Usage: planner-state.sh timestamp <get|set> [args...]" >&2
        exit 1
        ;;
    esac
    ;;

  reminder)
    subcmd="${2:?Usage: planner-state.sh reminder <get|set> <slug>}"
    case "$subcmd" in
      get)
        slug="${3:?Usage: planner-state.sh reminder get <slug>}"
        _ensure_file
        val="$(jq -r --arg s "$slug" '.reminders[$s].last_reminded // empty' "$STATE_FILE")"
        if [[ -z "$val" ]]; then
          exit 1
        fi
        echo "$val"
        ;;

      set)
        slug="${3:?Usage: planner-state.sh reminder set <slug>}"
        today="$(date +%Y-%m-%d)"
        _locked_write '.reminders[$s].last_reminded = $today' --arg s "$slug" --arg today "$today"
        ;;

      *)
        echo "Usage: planner-state.sh reminder <get|set> [args...]" >&2
        exit 1
        ;;
    esac
    ;;

  interests)
    subcmd="${2:?Usage: planner-state.sh interests <get|set|list> [topic]}"
    case "$subcmd" in
      get)
        topic="${3:?Usage: planner-state.sh interests get <topic>}"
        _ensure_file
        val="$(jq -r --arg t "$topic" '.interests[$t].last_checked // empty' "$STATE_FILE")"
        if [[ -z "$val" ]]; then
          exit 1
        fi
        echo "$val"
        ;;

      set)
        topic="${3:?Usage: planner-state.sh interests set <topic>}"
        now="$(date -Iseconds)"
        _locked_write '.interests[$t].last_checked = $now' --arg t "$topic" --arg now "$now"
        ;;

      list)
        _ensure_file
        jq '.interests' "$STATE_FILE"
        ;;

      *)
        echo "Usage: planner-state.sh interests <get|set|list> [args...]" >&2
        exit 1
        ;;
    esac
    ;;

  schedule)
    subcmd="${2:?Usage: planner-state.sh schedule <get|set>}"
    case "$subcmd" in
      get)
        _ensure_file
        jq -r '.schedule' "$STATE_FILE"
        ;;

      set)
        content="$(cat)"
        _locked_write '.schedule = $content' --arg content "$content"
        ;;

      *)
        echo "Usage: planner-state.sh schedule <get|set>" >&2
        exit 1
        ;;
    esac
    ;;

  last-run)
    subcmd="${2:?Usage: planner-state.sh last-run <get|set>}"
    case "$subcmd" in
      get)
        _ensure_file
        jq '.last_run' "$STATE_FILE"
        ;;

      set)
        content="$(cat)"
        _locked_write '.last_run = $content' --argjson content "$content"
        ;;

      *)
        echo "Usage: planner-state.sh last-run <get|set>" >&2
        exit 1
        ;;
    esac
    ;;

  *)
    echo "Usage: planner-state.sh <reset|event|timestamp|reminder|interests|schedule|last-run> [args...]" >&2
    exit 1
    ;;
esac
