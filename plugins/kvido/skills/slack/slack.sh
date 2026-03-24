#!/usr/bin/env bash
set -euo pipefail

# Slack Web API wrapper — Block Kit messaging via curl + jq
# Usage:
#   slack.sh send [channel] <template|-> [--var key=value]...
#   slack.sh reply [channel] <thread_ts> <template|-> [--var key=value]...
#   slack.sh edit [channel] <message_ts> <template|-> [--var key=value]...
#   slack.sh read [channel] [--limit N] [--oldest ts] [--thread ts] [--text]
#   slack.sh react <ts> <emoji> [channel]
#   slack.sh unreact <ts> <emoji> [channel]
#   slack.sh reactions <message_ts> [channel]
#   slack.sh delete [channel] <message_ts>
#   slack.sh download <url_private> [output_dir]
# Channel is optional — defaults to slack.dm_channel_id from settings.json

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

SLACK_API="https://slack.com/api"
TOKEN=$(bash "$SCRIPT_DIR/../config.sh" 'slack.bot_token' '' 2>/dev/null || true)

if [[ -z "$TOKEN" ]]; then
  echo "Error: slack.bot_token not set in settings.json (use \"\$SLACK_BOT_TOKEN\" to reference .env)" >&2
  exit 1
fi

ACTION="${1:-}"
shift || true

# If next arg looks like a Slack channel/DM ID (C.../D.../G...), consume it.
# Otherwise fall back to slack.dm_channel_id from settings.json.
# Sets global CHANNEL_SHIFTED=true if caller should shift, false otherwise.
CHANNEL_SHIFTED=false
RESOLVED_CHANNEL=""
_DEFAULT_CHANNEL=""
resolve_channel() {
  CHANNEL_SHIFTED=false
  if [[ "${1:-}" =~ ^[CDG][A-Z0-9]+ ]]; then
    RESOLVED_CHANNEL="$1"
    CHANNEL_SHIFTED=true
    return 0
  fi
  if [[ -z "$_DEFAULT_CHANNEL" ]]; then
    _DEFAULT_CHANNEL=$(bash "$SCRIPT_DIR/../config.sh" 'slack.dm_channel_id' '' 2>/dev/null || true)
  fi
  if [[ -z "$_DEFAULT_CHANNEL" ]]; then
    echo "Error: channel not provided and slack.dm_channel_id not set in settings.json" >&2
    exit 1
  fi
  RESOLVED_CHANNEL="$_DEFAULT_CHANNEL"
  return 0
}

# Call Slack Web API (POST with JSON body)
slack_post() {
  local method="$1"; shift
  curl -s -X POST "$SLACK_API/$method" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-type: application/json; charset=utf-8" \
    "$@"
}

# Call Slack Web API (GET with query params)
slack_get() {
  local method="$1"; shift
  curl -s -G "$SLACK_API/$method" \
    -H "Authorization: Bearer $TOKEN" \
    "$@"
}

# Send message via API method, handle response
slack_message() {
  local api_method="$1" payload="$2" return_ts="${3:-true}"
  local result
  result=$(slack_post "$api_method" -d "$payload")
  if [[ $(echo "$result" | jq -r '.ok') != "true" ]]; then
    echo "Error: $(echo "$result" | jq -r '.error')" >&2
    exit 1
  fi
  [[ "$return_ts" == "true" ]] && echo "$result" | jq -r '.ts' || true
}

# Parse --var arguments and render template through jq
build_blocks() {
  local template_name="$1"
  shift
  local jq_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --var)
        if [[ -z "${2:-}" || "$2" != *=* ]]; then
          echo "Error: --var requires key=value format" >&2
          exit 1
        fi
        local key="${2%%=*}"
        local value="${2#*=}"
        # Convert escaped \n sequences to actual newlines so Slack renders line breaks
        value=$(printf '%b' "$value")
        jq_args+=(--arg "$key" "$value")
        shift 2
        ;;
      *)
        echo "Warning: build_blocks — unknown argument '$1' (typo in --var?)" >&2
        shift
        ;;
    esac
  done

  if [[ "$template_name" == "-" ]]; then
    cat
  else
    local template_file="$TEMPLATES_DIR/${template_name}.json"
    if [[ ! -f "$template_file" ]]; then
      echo "Error: template '$template_name' not found at $template_file" >&2
      exit 1
    fi
    local rendered
    if [[ ${#jq_args[@]} -eq 0 ]]; then
      rendered=$(cat "$template_file")
    else
      rendered=$(jq "${jq_args[@]}" '
        walk(if type == "string" then
          reduce ($ARGS.named | to_entries[]) as $e (.; gsub("{{" + $e.key + "}}"; $e.value))
        else . end)
      ' "$template_file")
    fi

    # Validate: fail if any {{placeholder}} remains unresolved
    local unresolved
    unresolved=$(echo "$rendered" | jq -r '
      [.. | strings | [capture("\\{\\{(?<var>[^}]+)\\}\\}"; "g")] | .[].var]
      | unique | .[]
    ' 2>/dev/null || true)
    if [[ -n "$unresolved" ]]; then
      echo "Error: template '$template_name' has unresolved variables: $(echo "$unresolved" | tr '\n' ', ' | sed 's/,$//')" >&2
      echo "Hint: pass --var <name>=<value> for each variable" >&2
      exit 1
    fi

    echo "$rendered"
  fi
}

case "$ACTION" in
  send)
    [[ $# -lt 1 ]] && { echo "Usage: slack.sh send [channel] <template> [--var ...]" >&2; exit 1; }
    resolve_channel "$1"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    TEMPLATE="$1"; shift
    BLOCKS=$(build_blocks "$TEMPLATE" "$@")
    PAYLOAD=$(jq -n --arg channel "$CHANNEL" --argjson blocks "$BLOCKS" \
      '{channel: $channel, blocks: $blocks}')
    slack_message "chat.postMessage" "$PAYLOAD"
    ;;
  reply)
    [[ $# -lt 2 ]] && { echo "Usage: slack.sh reply [channel] <thread_ts> <template> [--var ...]" >&2; exit 1; }
    resolve_channel "$1"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    THREAD_TS="$1"; shift
    TEMPLATE="$1"; shift
    BLOCKS=$(build_blocks "$TEMPLATE" "$@")
    PAYLOAD=$(jq -n --arg channel "$CHANNEL" --arg thread_ts "$THREAD_TS" --argjson blocks "$BLOCKS" \
      '{channel: $channel, thread_ts: $thread_ts, blocks: $blocks}')
    slack_message "chat.postMessage" "$PAYLOAD"
    ;;
  edit)
    [[ $# -lt 2 ]] && { echo "Usage: slack.sh edit [channel] <message_ts> <template> [--var ...]" >&2; exit 1; }
    resolve_channel "$1"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    MESSAGE_TS="$1"; shift
    TEMPLATE="$1"; shift
    BLOCKS=$(build_blocks "$TEMPLATE" "$@")
    PAYLOAD=$(jq -n --arg channel "$CHANNEL" --arg ts "$MESSAGE_TS" --argjson blocks "$BLOCKS" \
      '{channel: $channel, ts: $ts, blocks: $blocks}')
    slack_message "chat.update" "$PAYLOAD" "false"
    ;;
  read)
    resolve_channel "${1:-}"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    LIMIT=5
    OLDEST=""
    LAST_CHAT_TS_ARG=""
    THREAD=""
    TEXT_MODE=false
    HEARTBEAT_MODE=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --limit) LIMIT="$2"; shift 2 ;;
        --oldest) OLDEST="$2"; shift 2 ;;
        --last-chat-ts) LAST_CHAT_TS_ARG="$2"; shift 2 ;;
        --thread) THREAD="$2"; shift 2 ;;
        --text) TEXT_MODE=true; shift ;;
        --json) TEXT_MODE=false; HEARTBEAT_MODE=false; shift ;;
        --heartbeat) HEARTBEAT_MODE=true; TEXT_MODE=false; shift ;;
        *) shift ;;
      esac
    done
    CURL_ARGS=(--data-urlencode "channel=$CHANNEL" --data-urlencode "limit=$LIMIT")
    [[ -n "$OLDEST" ]] && CURL_ARGS+=(--data-urlencode "oldest=$OLDEST")
    if [[ -n "$THREAD" ]]; then
      CURL_ARGS+=(--data-urlencode "ts=$THREAD")
      RAW=$(slack_get "conversations.replies" "${CURL_ARGS[@]}")
    else
      RAW=$(slack_get "conversations.history" "${CURL_ARGS[@]}")
    fi
    if [[ "$TEXT_MODE" == "true" ]]; then
      echo "$RAW" | jq -r '
        (.messages // [])
        | reverse
        | .[]
        | "[" + ((.ts | tonumber) | strftime("%H:%M")) + "] "
          + (.real_name // .name // .username // .user // "unknown") + ": "
          + (.text // "")
      '
    elif [[ "$HEARTBEAT_MODE" == "true" ]]; then
      # Compact format for heartbeat: one line per message with fields needed for chat check
      # Fields: ts, user (ID), text (in quotes, escaped), reactions, reply_count, latest_reply
      # Thread replies fetched for qualifying threads (reply_count>0), indented with ┗ prefix
      # Reactions from conversations.history natively — no extra API calls
      LAST_CHAT_TS="${LAST_CHAT_TS_ARG:-}"
      MESSAGES_JSON=$(echo "$RAW" | jq -c '(.messages // []) | reverse | .[]' || true)
      THREAD_COUNT=0
      while IFS= read -r MSG; do
        [[ -z "$MSG" ]] && continue
        TS=$(echo "$MSG" | jq -r '.ts' || true)
        USER=$(echo "$MSG" | jq -r '.user // "unknown"' || true)
        TEXT=$(echo "$MSG" | jq -r '(.text // "") | gsub("\n"; " ") | gsub("\""; "\\\"")' || true)
        REACTIONS=$(echo "$MSG" | jq -r 'if (.reactions // []) | length > 0 then " reactions=" + ([.reactions[].name] | join(",")) else "" end' || true)
        REPLY_COUNT=$(echo "$MSG" | jq -r '.reply_count // 0' || echo 0)
        LATEST_REPLY=$(echo "$MSG" | jq -r '.latest_reply // ""' || true)
        THREAD_TS_VAL=$(echo "$MSG" | jq -r 'if .thread_ts != null and .thread_ts != .ts then .thread_ts else "" end' || true)

        LINE="ts=$TS user=$USER text=\"$TEXT\"$REACTIONS"
        [[ -n "$THREAD_TS_VAL" ]] && LINE="$LINE thread_ts=$THREAD_TS_VAL"
        if [[ "$REPLY_COUNT" -gt 0 ]]; then
          LINE="$LINE reply_count=$REPLY_COUNT"
          [[ -n "$LATEST_REPLY" ]] && LINE="$LINE latest_reply=$LATEST_REPLY"
        fi
        echo "$LINE"

        # Fetch thread replies for qualifying threads (max 3 threads per call, max 5 replies each)
        if [[ "$REPLY_COUNT" -gt 0 && "$THREAD_COUNT" -lt 3 ]]; then
          # Only fetch if latest_reply is newer than oldest (last_chat_ts)
          FETCH_THREAD=true
          if [[ -n "$LAST_CHAT_TS" && -n "$LATEST_REPLY" ]]; then
            # Compare as floats: latest_reply > last_chat_ts
            if ! awk "BEGIN { exit ($LATEST_REPLY > $LAST_CHAT_TS) ? 0 : 1 }" 2>/dev/null; then
              FETCH_THREAD=false
            fi
          fi
          if [[ "$FETCH_THREAD" == "true" ]]; then
            THREAD_COUNT=$((THREAD_COUNT + 1))
            THREAD_RAW=$(slack_get "conversations.replies" \
              --data-urlencode "channel=$CHANNEL" \
              --data-urlencode "ts=$TS" \
              --data-urlencode "limit=100" 2>/dev/null || echo '{"messages":[]}')
            # Skip first message (parent), take LAST 5 replies (newest)
            echo "$THREAD_RAW" | jq -r '
              (.messages // [])
              | .[1:]
              | .[-5:]
              | .[]
              | "  \u250b ts=" + .ts
                + " user=" + (.user // "unknown")
                + " text=\"" + ((.text // "") | gsub("\n"; " ") | gsub("\""; "\\\"")) + "\""
                + (if (.reactions // []) | length > 0 then " reactions=" + ([.reactions[].name] | join(",")) else "" end)
            '
          fi
        fi

        echo ""
      done <<< "$MESSAGES_JSON"
    else
      echo "$RAW" | jq '.messages // []'
    fi
    ;;
  react)
    # Usage: slack.sh react <ts> <emoji> [channel]
    # Adds a reaction to a message. Emoji without colons (e.g. "eyes", "white_check_mark").
    # Channel defaults to slack.dm_channel_id from settings.json.
    [[ $# -lt 2 ]] && { echo "Usage: slack.sh react <ts> <emoji> [channel]" >&2; exit 1; }
    REACT_TS="$1"; shift
    REACT_EMOJI="$1"; shift
    # Strip surrounding colons if provided (e.g. :eyes: → eyes)
    REACT_EMOJI="${REACT_EMOJI#:}"; REACT_EMOJI="${REACT_EMOJI%:}"
    resolve_channel "${1:-}"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    PAYLOAD=$(jq -n --arg channel "$CHANNEL" --arg timestamp "$REACT_TS" --arg name "$REACT_EMOJI" \
      '{channel: $channel, timestamp: $timestamp, name: $name}')
    RESULT=$(slack_post "reactions.add" -d "$PAYLOAD")
    if [[ $(echo "$RESULT" | jq -r '.ok') != "true" ]]; then
      ERR=$(echo "$RESULT" | jq -r '.error')
      # already_reacted is not a real error — idempotent behaviour
      if [[ "$ERR" == "already_reacted" ]]; then
        echo "ok"
      else
        echo "Error: $ERR" >&2
        exit 1
      fi
    else
      echo "ok"
    fi
    ;;
  unreact)
    # Usage: slack.sh unreact <ts> <emoji> [channel]
    # Removes a reaction from a message. Emoji without colons (e.g. "eyes").
    # Idempotent: no_reaction is treated as success.
    [[ $# -lt 2 ]] && { echo "Usage: slack.sh unreact <ts> <emoji> [channel]" >&2; exit 1; }
    REACT_TS="$1"; shift
    REACT_EMOJI="$1"; shift
    REACT_EMOJI="${REACT_EMOJI#:}"; REACT_EMOJI="${REACT_EMOJI%:}"
    resolve_channel "${1:-}"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    PAYLOAD=$(jq -n --arg channel "$CHANNEL" --arg timestamp "$REACT_TS" --arg name "$REACT_EMOJI" \
      '{channel: $channel, timestamp: $timestamp, name: $name}')
    RESULT=$(slack_post "reactions.remove" -d "$PAYLOAD")
    if [[ $(echo "$RESULT" | jq -r '.ok') != "true" ]]; then
      ERR=$(echo "$RESULT" | jq -r '.error')
      if [[ "$ERR" == "no_reaction" ]]; then
        echo "ok"
      else
        echo "Error: $ERR" >&2
        exit 1
      fi
    else
      echo "ok"
    fi
    ;;
  reactions)
    # Usage: slack.sh reactions <message_ts> [channel]
    # Returns JSON: {"white_check_mark": true/false, "x": true/false}
    [[ $# -lt 1 ]] && { echo "Usage: slack.sh reactions <message_ts> [channel]" >&2; exit 1; }
    REACTIONS_TS="$1"; shift
    resolve_channel "${1:-}"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    RAW=$(slack_get "reactions.get" \
      --data-urlencode "channel=$CHANNEL" \
      --data-urlencode "timestamp=$REACTIONS_TS" \
      --data-urlencode "full=true")
    if [[ $(echo "$RAW" | jq -r '.ok') != "true" ]]; then
      echo "Error: $(echo "$RAW" | jq -r '.error')" >&2
      exit 1
    fi
    echo "$RAW" | jq '{
      white_check_mark: ([(.message.reactions // [])[] | select(.name == "white_check_mark")] | length > 0),
      thumbsup: ([(.message.reactions // [])[] | select(.name == "+1" or .name == "thumbsup")] | length > 0),
      x: ([(.message.reactions // [])[] | select(.name == "x")] | length > 0),
      thumbsdown: ([(.message.reactions // [])[] | select(.name == "-1" or .name == "thumbsdown")] | length > 0)
    }'
    ;;
  delete)
    [[ $# -lt 1 ]] && { echo "Usage: slack.sh delete [channel] <message_ts>" >&2; exit 1; }
    resolve_channel "$1"
    CHANNEL="$RESOLVED_CHANNEL"; [[ "$CHANNEL_SHIFTED" == "true" ]] && shift
    MESSAGE_TS="$1"; shift
    PAYLOAD=$(jq -n --arg channel "$CHANNEL" --arg ts "$MESSAGE_TS" \
      '{channel: $channel, ts: $ts}')
    slack_message "chat.delete" "$PAYLOAD" "false"
    ;;
  download)
    [[ $# -lt 1 ]] && { echo "Usage: slack.sh download <url_private> [output_dir]" >&2; exit 1; }
    URL_PRIVATE="$1"; shift
    OUTPUT_DIR="${1:-/tmp}"; shift 2>/dev/null || true
    FILENAME=$(basename "$URL_PRIVATE" | cut -d'?' -f1)
    [[ -z "$FILENAME" ]] && FILENAME="slack-file-$(date +%s)"
    OUTPUT_PATH="$OUTPUT_DIR/$FILENAME"
    HTTP_CODE=$(curl -s -w "%{http_code}" -o "$OUTPUT_PATH" \
      -H "Authorization: Bearer $TOKEN" \
      "$URL_PRIVATE")
    if [[ "$HTTP_CODE" != "200" ]]; then
      rm -f "$OUTPUT_PATH"
      echo "Error: download failed with HTTP $HTTP_CODE for $URL_PRIVATE" >&2
      exit 1
    fi
    echo "$OUTPUT_PATH"
    ;;
  *)
    echo "Usage: slack.sh {send|reply|edit|read|react|unreact|reactions|delete|download} ..." >&2
    exit 1
    ;;
esac
