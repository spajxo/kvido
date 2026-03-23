#!/usr/bin/env bash
set -euo pipefail

# kvido log — unified logging for kvido
# Usage: kvido log <add|list|purge> [args...]

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
ACTIVITY_LOG="${KVIDO_HOME}/state/log.jsonl"

# One-time migration: rename old activity-log.jsonl → log.jsonl
OLD_LOG="${KVIDO_HOME}/state/activity-log.jsonl"
if [[ -f "$OLD_LOG" && ! -f "$ACTIVITY_LOG" ]]; then
  mv "$OLD_LOG" "$ACTIVITY_LOG"
elif [[ -f "$OLD_LOG" && -f "$ACTIVITY_LOG" ]]; then
  # Both exist (edge case) — append old into new, remove old
  cat "$OLD_LOG" >> "$ACTIVITY_LOG"
  rm "$OLD_LOG"
fi

ACTION="${1:?Usage: kvido log <add|list|purge> [args...]}"
shift

case "$ACTION" in

  # ---------------------------------------------------------------------------
  # kvido log add <agent> <action> [--message "..."] [--tokens N] [--duration_ms N] [--detail "..."] [--task_id "..."]
  # ---------------------------------------------------------------------------
  add)
    agent="${1:?Usage: kvido log add <agent> <action> [options...]}"
    action="${2:?Usage: kvido log add <agent> <action> [options...]}"
    shift 2

    ts="$(date -Iseconds)"
    message="" detail="" duration_ms="" tokens="" task_id=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --message)     message="$2"; shift 2 ;;
        --detail)      detail="$2"; shift 2 ;;
        --duration_ms) duration_ms="$2"; shift 2 ;;
        --tokens)      tokens="$2"; shift 2 ;;
        --task_id)     task_id="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    # Build JSON with jq — only include non-empty optional fields
    jq_args=(--arg ts "$ts" --arg agent "$agent" --arg action "$action")
    jq_filter='{ts: $ts, agent: $agent, action: $action}'

    if [[ -n "$message" ]]; then
      jq_args+=(--arg message "$message")
      jq_filter="$jq_filter + {message: \$message}"
    fi
    if [[ -n "$detail" ]]; then
      jq_args+=(--arg detail "$detail")
      jq_filter="$jq_filter + {detail: \$detail}"
    fi
    if [[ -n "$duration_ms" ]]; then
      jq_args+=(--argjson duration_ms "$duration_ms")
      jq_filter="$jq_filter + {duration_ms: \$duration_ms}"
    fi
    if [[ -n "$tokens" ]]; then
      jq_args+=(--argjson tokens "$tokens")
      jq_filter="$jq_filter + {tokens: \$tokens}"
    fi
    if [[ -n "$task_id" ]]; then
      jq_args+=(--arg task_id "$task_id")
      jq_filter="$jq_filter + {task_id: \$task_id}"
    fi

    mkdir -p "$(dirname "$ACTIVITY_LOG")"
    jq -c -n "${jq_args[@]}" "$jq_filter" >> "$ACTIVITY_LOG"
    ;;

  # ---------------------------------------------------------------------------
  # kvido log list [--today] [--agent <name>] [--since <ts>] [--format human|json|jsonl] [--limit N] [--summary]
  # ---------------------------------------------------------------------------
  list)
    FORMAT="human"
    FILTER_TODAY=false
    FILTER_AGENT=""
    FILTER_SINCE=""
    LIMIT=""
    SUMMARY=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --today)   FILTER_TODAY=true; shift ;;
        --agent)   FILTER_AGENT="$2"; shift 2 ;;
        --since)   FILTER_SINCE="$2"; shift 2 ;;
        --format)  FORMAT="$2"; shift 2 ;;
        --limit)   LIMIT="$2"; shift 2 ;;
        --summary) SUMMARY=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    if [[ ! -f "$ACTIVITY_LOG" ]]; then
      case "$FORMAT" in
        json)  echo "[]" ;;
        jsonl) ;;
        human) ;;
      esac
      exit 0
    fi

    # Build jq filter pipeline
    JQ_ARGS=(-s)
    JQ_FILTER='[.[]'

    if [[ "$FILTER_TODAY" == "true" ]]; then
      TODAY=$(date +%Y-%m-%d)
      JQ_ARGS+=(--arg since "${TODAY}T00:00:00")
      JQ_FILTER="$JQ_FILTER | select(.ts >= \$since)"
    elif [[ -n "$FILTER_SINCE" ]]; then
      JQ_ARGS+=(--arg since "$FILTER_SINCE")
      JQ_FILTER="$JQ_FILTER | select(.ts >= \$since)"
    fi

    if [[ -n "$FILTER_AGENT" ]]; then
      JQ_ARGS+=(--arg agent "$FILTER_AGENT")
      JQ_FILTER="$JQ_FILTER | select(.agent == \$agent)"
    fi

    JQ_FILTER="$JQ_FILTER] | sort_by(.ts)"

    if [[ -n "$LIMIT" ]]; then
      JQ_FILTER="$JQ_FILTER | .[-${LIMIT}:]"
    fi

    if [[ "$SUMMARY" == "true" ]]; then
      JQ_FILTER="$JQ_FILTER | group_by(.agent) | map({
        agent: .[0].agent,
        tokens: (map(.tokens // 0) | add),
        runs: length,
        duration_ms: (map(.duration_ms // 0) | add)
      }) | sort_by(-.tokens)"

      case "$FORMAT" in
        json)  jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$ACTIVITY_LOG" ;;
        jsonl) jq "${JQ_ARGS[@]}" "$JQ_FILTER | .[]" "$ACTIVITY_LOG" | jq -c '.' ;;
        human)
          jq -r "${JQ_ARGS[@]}" "$JQ_FILTER | .[] | \"\\(.agent): \\(.runs) runs, \\(.tokens) tokens, \\(.duration_ms)ms\"" "$ACTIVITY_LOG"
          ;;
      esac
    else
      # Reverse for display (newest first)
      JQ_FILTER="$JQ_FILTER | reverse"

      case "$FORMAT" in
        json)  jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$ACTIVITY_LOG" ;;
        jsonl) jq "${JQ_ARGS[@]}" "$JQ_FILTER | .[]" "$ACTIVITY_LOG" | jq -c '.' ;;
        human)
          jq -r "${JQ_ARGS[@]}" "$JQ_FILTER | .[] | \"- **\\(.ts | split(\"T\")[1] | split(\"+\")[0] | split(\"-\")[0] | .[0:5])** [\\(.agent)] \\(.message // .action)\"" "$ACTIVITY_LOG"
          ;;
      esac
    fi
    ;;

  # ---------------------------------------------------------------------------
  # kvido log purge [--before <date|today>] [--archive] [--dry-run]
  # ---------------------------------------------------------------------------
  purge)
    BEFORE=""
    ARCHIVE=false
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --before)  BEFORE="$2"; shift 2 ;;
        --archive) ARCHIVE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    [[ -z "$BEFORE" ]] && { echo "Usage: kvido log purge --before <date|today> [--archive] [--dry-run]" >&2; exit 1; }

    if [[ "$BEFORE" == "today" ]]; then
      BEFORE=$(date +%Y-%m-%d)
    fi

    CUTOFF="${BEFORE}T00:00:00"

    if [[ ! -f "$ACTIVITY_LOG" ]]; then
      echo "No log file found." >&2
      exit 0
    fi

    # Count entries to purge
    OLD_COUNT=$(jq -s --arg cutoff "$CUTOFF" '[.[] | select(.ts < $cutoff)] | length' "$ACTIVITY_LOG")
    KEEP_COUNT=$(jq -s --arg cutoff "$CUTOFF" '[.[] | select(.ts >= $cutoff)] | length' "$ACTIVITY_LOG")

    if [[ "$OLD_COUNT" -eq 0 ]]; then
      echo "Nothing to purge (0 entries before $BEFORE)."
      exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "Would purge $OLD_COUNT entries before $BEFORE ($KEEP_COUNT kept)."
      if [[ "$ARCHIVE" == "true" ]]; then
        ARCHIVE_DATE=$(date -d "${BEFORE} - 1 day" +%Y-%m-%d 2>/dev/null || date -v-1d -j -f "%Y-%m-%d" "$BEFORE" +%Y-%m-%d)
        echo "Would archive to state/archive/log-${ARCHIVE_DATE}.jsonl"
      fi
      exit 0
    fi

    if [[ "$ARCHIVE" == "true" ]]; then
      mkdir -p "${KVIDO_HOME}/state/archive"
      # Name archive after the day before the cutoff (the last day of archived data)
      ARCHIVE_DATE=$(date -d "${BEFORE} - 1 day" +%Y-%m-%d 2>/dev/null || date -v-1d -j -f "%Y-%m-%d" "$BEFORE" +%Y-%m-%d)
      jq -c -s --arg cutoff "$CUTOFF" '.[] | select(.ts < $cutoff)' "$ACTIVITY_LOG" >> "${KVIDO_HOME}/state/archive/log-${ARCHIVE_DATE}.jsonl"
      echo "Archived $OLD_COUNT entries to state/archive/log-${ARCHIVE_DATE}.jsonl"
    fi

    # Keep only entries >= cutoff
    TMPFILE=$(mktemp)
    jq -c -s --arg cutoff "$CUTOFF" '.[] | select(.ts >= $cutoff)' "$ACTIVITY_LOG" > "$TMPFILE"
    mv "$TMPFILE" "$ACTIVITY_LOG"
    echo "Purged $OLD_COUNT entries before $BEFORE ($KEEP_COUNT kept)."

    # Clean old archives (older than 7 days)
    if [[ "$ARCHIVE" == "true" ]]; then
      find "${KVIDO_HOME}/state/archive" -name "log-*.jsonl" -mtime +7 -delete 2>/dev/null || true
    fi
    ;;

  *)
    echo "Usage: kvido log <add|list|purge> [args...]" >&2
    exit 1
    ;;
esac
