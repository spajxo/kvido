#!/usr/bin/env bash
# event.sh — Append-only JSONL event bus
# Storage: $KVIDO_HOME/state/events.jsonl
# Cursors: stored in state/state.json via kvido state (key: <consumer>.cursor_offset)
#
# Usage:
#   event.sh emit <type> [--data '{}'] [--producer <name>] [--dedup-key <key> --dedup-window <dur>]
#   event.sh read [--consumer <name>] [--type <glob>] [--since <ts>] [--limit N]
#   event.sh ack --consumer <name> [--through <event-id>]
#   event.sh gc [--older-than 72h]
#   event.sh count [--consumer <name>] [--type <glob>] [--unread]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
EVENTS_FILE="${KVIDO_HOME}/state/events.jsonl"
LOCK_FILE="${EVENTS_FILE}.lock"
LOCK_TIMEOUT=10
STATE_SH="$(cd "$SCRIPT_DIR/.." && pwd)/state/state.sh"

_ensure_file() {
  mkdir -p "$(dirname "$EVENTS_FILE")"
  touch "$EVENTS_FILE"
}

_gen_id() {
  local epoch
  epoch="$(date +%s)"
  local hex
  hex="$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  echo "evt_${epoch}_${hex}"
}

# _duration_to_seconds <duration> (e.g. "72h", "30m", "1d")
_duration_to_seconds() {
  local dur="$1"
  local num="${dur%[hdms]}"
  local unit="${dur: -1}"
  case "$unit" in
    h) echo $((num * 3600)) ;;
    d) echo $((num * 86400)) ;;
    m) echo $((num * 60)) ;;
    s) echo "$num" ;;
    *) echo "$((num * 3600))" ;; # default hours
  esac
}

CMD="${1:-}"

case "$CMD" in
  emit)
    shift
    type=""
    data='{}'
    producer=""
    dedup_key=""
    dedup_window=""

    # First positional arg is type
    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
      type="$1"
      shift
    fi

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --data) data="${2:?--data requires value}"; shift 2 ;;
        --producer) producer="${2:?--producer requires value}"; shift 2 ;;
        --dedup-key) dedup_key="${2:?--dedup-key requires value}"; shift 2 ;;
        --dedup-window) dedup_window="${2:?--dedup-window requires value}"; shift 2 ;;
        *) echo "event.sh emit: unknown option: $1" >&2; exit 1 ;;
      esac
    done

    [[ -z "$type" ]] && { echo "Usage: event.sh emit <type> [--data '{}'] [--producer <name>]" >&2; exit 1; }

    _ensure_file

    id="$(_gen_id)"
    ts="$(date -Iseconds)"

    # Inject dedup_key into data before lock (so it's stored in the event)
    if [[ -n "$dedup_key" ]]; then
      data=$(jq -c --arg dk "$dedup_key" '. + {dedup_key: $dk}' <<< "$data")
    fi

    # Append with lock (dedup check inside lock to prevent races)
    # Exit code 2 = dedup skip (distinguishes from lock failure = 1)
    (
      mkdir -p "$(dirname "$LOCK_FILE")"
      exec 200>"$LOCK_FILE"
      if ! flock -w "$LOCK_TIMEOUT" 200; then
        echo "event.sh: timeout acquiring lock" >&2
        exit 1
      fi

      # Dedup check (inside lock to prevent race between check and append)
      if [[ -n "$dedup_key" && -n "$dedup_window" ]]; then
        window_secs=$(_duration_to_seconds "$dedup_window")
        cutoff_epoch=$(( $(date +%s) - window_secs ))
        cutoff_ts="$(date -Iseconds -d "@$cutoff_epoch")"
        existing=$(jq -r --arg dk "$dedup_key" --arg ct "$cutoff_ts" \
          'select(.data.dedup_key == $dk and .ts >= $ct) | .id' \
          "$EVENTS_FILE" 2>/dev/null | head -1 || true)
        if [[ -n "$existing" ]]; then
          exit 2
        fi
      fi

      jq -c -n \
        --arg id "$id" \
        --arg ts "$ts" \
        --arg type "$type" \
        --arg producer "$producer" \
        --argjson data "$data" \
        '{id: $id, ts: $ts, type: $type, producer: $producer, data: $data}' \
        >> "$EVENTS_FILE"
    ) && rc=0 || rc=$?
    if [[ $rc -eq 2 ]]; then
      # Dedup: silently skip
      exit 0
    elif [[ $rc -ne 0 ]]; then
      exit $rc
    fi
    echo "$id"
    ;;

  read)
    shift
    consumer=""
    type_glob=""
    since=""
    limit=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --consumer) consumer="${2:?--consumer requires value}"; shift 2 ;;
        --type) type_glob="${2:?--type requires value}"; shift 2 ;;
        --since) since="${2:?--since requires value}"; shift 2 ;;
        --limit) limit="${2:?--limit requires value}"; shift 2 ;;
        *) echo "event.sh read: unknown option: $1" >&2; exit 1 ;;
      esac
    done

    _ensure_file

    # Consumer cursor — filter by line offset
    offset=0
    if [[ -n "$consumer" ]]; then
      offset=$(bash "$STATE_SH" get "${consumer}.cursor_offset" 2>/dev/null || echo "0")
      [[ -z "$offset" ]] && offset=0
    fi

    # Snapshot total line count BEFORE reading — this is where ack will advance to.
    # Events emitted after this point will NOT be acked, ensuring next-tick pickup.
    # When --limit is used, do NOT set pending_cursor — caller must use ack --through
    # for the subset they actually processed (prevents skipping unread events).
    if [[ -n "$consumer" && -z "$limit" ]]; then
      total=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
      bash "$STATE_SH" set "${consumer}.pending_cursor" "$total"
    fi

    # Build jq filter combining type and since
    jq_filter='.'
    jq_args=()
    if [[ -n "$type_glob" ]]; then
      regex="^$(echo "$type_glob" | sed 's/\./\\./g; s/\*/.*/g')$"
      jq_filter="select(.type | test(\$r))"
      jq_args+=(--arg r "$regex")
    fi
    if [[ -n "$since" ]]; then
      if [[ "$jq_filter" == "." ]]; then
        jq_filter="select(.ts >= \$s)"
      else
        jq_filter="$jq_filter | select(.ts >= \$s)"
      fi
      jq_args+=(--arg s "$since")
    fi

    {
      if [[ "$offset" -gt 0 ]]; then
        tail -n "+$((offset + 1))" "$EVENTS_FILE"
      else
        cat "$EVENTS_FILE"
      fi
    } | {
      jq -c ${jq_args[@]+"${jq_args[@]}"} "$jq_filter"
    } | {
      if [[ -n "$limit" ]]; then
        head -n "$limit"
      else
        cat
      fi
    }
    ;;

  ack)
    shift
    consumer=""
    through=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --consumer) consumer="${2:?--consumer requires value}"; shift 2 ;;
        --through) through="${2:?--through requires value}"; shift 2 ;;
        *) echo "event.sh ack: unknown option: $1" >&2; exit 1 ;;
      esac
    done

    [[ -z "$consumer" ]] && { echo "Usage: event.sh ack --consumer <name> [--through <event-id>]" >&2; exit 1; }

    _ensure_file

    if [[ -n "$through" ]]; then
      line_num=$(grep -n "\"$through\"" "$EVENTS_FILE" | head -1 | cut -d: -f1 || true)
      if [[ -n "$line_num" ]]; then
        bash "$STATE_SH" set "${consumer}.cursor_offset" "$line_num"
      fi
    else
      # Use pending_cursor from last read (not current file end) to avoid
      # skipping events emitted between read and ack
      pending=$(bash "$STATE_SH" get "${consumer}.pending_cursor" 2>/dev/null || echo "")
      if [[ -n "$pending" ]]; then
        bash "$STATE_SH" set "${consumer}.cursor_offset" "$pending"
        bash "$STATE_SH" delete "${consumer}.pending_cursor"
      else
        # Fallback: no pending cursor (read was not called), use current end
        total=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
        bash "$STATE_SH" set "${consumer}.cursor_offset" "$total"
      fi
    fi
    ;;

  gc)
    shift
    older_than="72h"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --older-than) older_than="${2:?--older-than requires value}"; shift 2 ;;
        *) echo "event.sh gc: unknown option: $1" >&2; exit 1 ;;
      esac
    done

    _ensure_file

    window_secs=$(_duration_to_seconds "$older_than")
    cutoff_epoch=$(( $(date +%s) - window_secs ))
    cutoff_ts="$(date -Iseconds -d "@$cutoff_epoch")"

    # GC under lock to prevent concurrent emit from losing events
    (
      mkdir -p "$(dirname "$LOCK_FILE")"
      exec 200>"$LOCK_FILE"
      if ! flock -w "$LOCK_TIMEOUT" 200; then
        echo "event.sh: timeout acquiring lock for gc" >&2
        exit 1
      fi

      before_count=$(wc -l < "$EVENTS_FILE" | tr -d ' ')

      tmp="$(mktemp "${EVENTS_FILE}.tmp.XXXXXX")"
      jq -c --arg ct "$cutoff_ts" 'select(.ts >= $ct)' "$EVENTS_FILE" > "$tmp" 2>/dev/null || true
      mv "$tmp" "$EVENTS_FILE"

      after_count=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
      removed=$((before_count - after_count))

      # Adjust all cursor-like keys by subtracting removed lines (floor at 0)
      if [[ "$removed" -gt 0 ]]; then
        for cursor_key in $(bash "$STATE_SH" list 2>/dev/null | grep -E '\.(cursor_offset|pending_cursor)$' || true); do
          old_val=$(bash "$STATE_SH" get "$cursor_key" 2>/dev/null || echo "0")
          [[ -z "$old_val" ]] && old_val=0
          new_val=$((old_val - removed))
          (( new_val < 0 )) && new_val=0
          bash "$STATE_SH" set "$cursor_key" "$new_val"
        done
      fi

      echo "gc: removed $removed events (kept $after_count)"
    )
    ;;

  count)
    shift
    consumer=""
    type_glob=""
    unread="false"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --consumer) consumer="${2:?--consumer requires value}"; shift 2 ;;
        --type) type_glob="${2:?--type requires value}"; shift 2 ;;
        --unread) unread="true"; shift ;;
        *) echo "event.sh count: unknown option: $1" >&2; exit 1 ;;
      esac
    done

    _ensure_file

    args=()
    [[ -n "$consumer" && "$unread" == "true" ]] && args+=(--consumer "$consumer")
    [[ -n "$type_glob" ]] && args+=(--type "$type_glob")

    bash "$SCRIPT_DIR/event.sh" read ${args[@]+"${args[@]}"} 2>/dev/null | wc -l | tr -d ' '
    ;;

  *)
    echo "Usage: event.sh <emit|read|ack|gc|count> [args...]" >&2
    exit 1
    ;;
esac
