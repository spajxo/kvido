#!/usr/bin/env bash
# source-calendar/fetch.sh — fetch calendar events via gws CLI
# Usage: ./fetch.sh [YYYY-MM-DD]
# Output: formatted summary with categorized events + meeting/free time

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$(cd "$SKILL_DIR/.." && pwd)/config.sh"

# Target date (default: today)
TARGET_DATE="${1:-$(date +%Y-%m-%d)}"
TIME_MIN="${TARGET_DATE}T00:00:00Z"
TIME_MAX="${TARGET_DATE}T23:59:59Z"

# Fetch events
EVENTS=$(gws calendar events list primary \
  --timeMin "$TIME_MIN" \
  --timeMax "$TIME_MAX" \
  --singleEvents \
  --orderBy startTime \
  --format json 2>/dev/null) || {
  echo "ERROR: gws calendar fetch failed" >&2
  exit 1
}

EVENT_COUNT=$(echo "$EVENTS" | jq -r '.items | length')

if [[ "$EVENT_COUNT" -eq 0 ]]; then
  echo "Calendar $TARGET_DATE: no events"
  exit 0
fi

echo "Calendar $TARGET_DATE:"
echo ""

TOTAL_MINUTES=0

echo "$EVENTS" | jq -r '.items[] | @base64' | while read -r ITEM_B64; do
  ITEM=$(echo "$ITEM_B64" | base64 -d)

  SUMMARY=$(echo "$ITEM" | jq -r '.summary // "(no title)"')
  START=$(echo "$ITEM" | jq -r '.start.dateTime // .start.date // ""')
  END=$(echo "$ITEM" | jq -r '.end.dateTime // .end.date // ""')
  ALL_DAY=$(echo "$ITEM" | jq -r 'if .start.date then "true" else "false" end')

  # Determine category from config
  LOWER_SUMMARY=$(echo "$SUMMARY" | tr '[:upper:]' '[:lower:]')
  CATEGORY="meeting"
  while IFS=$'\t' read -r CAT KEYWORDS; do
    for KW in $(echo "$KEYWORDS" | tr ',' ' '); do
      [[ -z "$KW" ]] && continue
      if echo "$LOWER_SUMMARY" | grep -qi "$KW"; then
        CATEGORY="$CAT"
        break 2
      fi
    done
  done < <(for cat_key in $($CONFIG --keys 'sources.calendar.categories'); do
    printf '%s\t%s\n' "$cat_key" "$($CONFIG "sources.calendar.categories.${cat_key}")"
  done)

  # Format time
  if [[ "$ALL_DAY" == "true" ]]; then
    TIME_STR="all day"
  else
    START_TIME=$(echo "$START" | grep -oE '[0-9]{2}:[0-9]{2}' || echo "$START")
    END_TIME=$(echo "$END" | grep -oE '[0-9]{2}:[0-9]{2}' || echo "$END")
    TIME_STR="${START_TIME}–${END_TIME}"

    # Calculate duration in minutes (GNU date, no python3 dependency)
    if [[ -n "$START" && -n "$END" ]]; then
      S_EPOCH=$(date -d "$START" +%s 2>/dev/null || echo 0)
      E_EPOCH=$(date -d "$END" +%s 2>/dev/null || echo 0)
      DURATION=$(( (E_EPOCH - S_EPOCH) / 60 ))
    fi
  fi

  echo "- $TIME_STR — $SUMMARY [$CATEGORY]"
done

# Summary line
echo ""
echo "Total: $EVENT_COUNT events"
