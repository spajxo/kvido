#!/usr/bin/env bash
# fetch-messages.sh — Extract user messages and error patterns from Claude Code sessions
#
# Usage: fetch-messages.sh [YYYY-MM-DD]
# Default: today
#
# Output: Plain text with session markers, max ~2000 lines (newest first, truncate oldest)
# Dependencies: jq, date

set -euo pipefail

TARGET_DATE="${1:-$(date '+%Y-%m-%d')}"

if ! date -d "$TARGET_DATE" &>/dev/null 2>&1; then
  echo "ERROR: invalid date: $TARGET_DATE" >&2
  exit 1
fi

SESSIONS_DIR="${HOME}/.claude/projects"

if [[ ! -d "$SESSIONS_DIR" ]]; then
  echo "No session data available"
  exit 0
fi

MAX_LINES=2000
output=""

# Collect all JSONL files, sorted by modification time (newest first)
while IFS= read -r jsonl_file; do
  # Resolve project name from path
  rel="${jsonl_file#"$SESSIONS_DIR/"}"
  dir_name="${rel%%/*}"

  # Strip home prefix to get display name
  display="${dir_name#-}"
  display="${display#home-}"
  display="${display#*-Projects-}"
  display="${display#git-digital-cz-}"
  display="${display#github-com-}"
  if [[ "$display" == *-* ]]; then
    org="${display%%-*}"
    repo="${display#*-}"
    display="${org}/${repo}"
  fi

  # Extract user messages and assistant error/retry patterns for target date
  messages=$(jq -r --arg date "$TARGET_DATE" '
    select(.timestamp != null) |
    select(.timestamp[:10] == $date) |
    if .type == "user" then
      "USER: " + (
        if (.message.content | type) == "string" then .message.content
        elif (.message.content | type) == "array" then
          [.message.content[] | select(.type == "text") | .text] | join(" ")
        else ""
        end
      )
    elif .type == "assistant" then
      .message.content as $content |
      if ($content | type) == "string" then
        if ($content | test("(?i)(sorry|opravuji|pardon|mistake|let me fix|znovu|retry)")) then
          "RETRY: " + ($content[:200])
        else empty
        end
      elif ($content | type) == "array" then
        [$content[] | select(.type == "text") | .text] | join(" ") |
        if test("(?i)(sorry|opravuji|pardon|mistake|let me fix|znovu|retry)") then
          "RETRY: " + .[:200]
        else empty
        end
      else empty
      end
    else empty
    end
  ' "$jsonl_file" 2>/dev/null || true)

  if [[ -n "$messages" ]]; then
    session_id=$(basename "$jsonl_file" .jsonl)
    block="=== ${display} (${session_id}) ===
${messages}

"
    output="${block}${output}"
  fi

done < <(
  find "$SESSIONS_DIR" -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn \
  | awk '{print $2}'
)

if [[ -z "$output" ]]; then
  echo "No session messages for $TARGET_DATE"
  exit 0
fi

# Truncate to MAX_LINES (keeps newest — output is already newest-first)
echo "$output" | head -n "$MAX_LINES"
