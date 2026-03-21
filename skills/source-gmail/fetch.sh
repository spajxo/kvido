#!/usr/bin/env bash
# source-gmail/fetch.sh — fetch unread emails via gws CLI
# Usage: ./fetch.sh [--watch]
# Output: formatted summary of unread emails

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$(cd "$SKILL_DIR/.." && pwd)/config.sh"

# Parse config
WATCH_QUERY=$($CONFIG 'sources.gmail.watch_query')
MAX_RESULTS=$($CONFIG 'sources.gmail.max_results')

WATCH_MODE=false
if [[ "${1:-}" == "--watch" ]]; then
  WATCH_MODE=true
fi

# Fetch messages list
MESSAGES=$(gws gmail users messages list --params "$(jq -n \
  --arg q "$WATCH_QUERY" \
  --argjson max "$MAX_RESULTS" \
  '{userId: "me", q: $q, maxResults: $max}')" 2>/dev/null) || {
  echo "ERROR: gws gmail fetch failed" >&2
  exit 1
}

MSG_COUNT=$(echo "$MESSAGES" | jq -r '.messages | length')
HAS_MORE=$(echo "$MESSAGES" | jq -r '.nextPageToken != null')

if [[ "$MSG_COUNT" -eq 0 ]]; then
  echo "Inbox: prázdno"
  exit 0
fi

if [[ "$HAS_MORE" == "true" ]]; then
  echo "Inbox: ${MSG_COUNT}+ nepřečtených (zobrazeno ${MSG_COUNT} z více)"
else
  echo "Inbox: $MSG_COUNT nepřečtených"
fi
echo ""

# Fetch metadata for each message
echo "$MESSAGES" | jq -r '.messages[]?.id // empty' | head -n "$MAX_RESULTS" | while read -r MSG_ID; do
  META=$(gws gmail users messages get --params "$(jq -n \
    --arg id "$MSG_ID" \
    '{userId: "me", id: $id, format: "metadata", metadataHeaders: ["From", "Subject", "Date"]}')" 2>/dev/null) || continue

  FROM=$(echo "$META" | jq -r '.payload.headers[] | select(.name == "From") | .value' 2>/dev/null || echo "unknown")
  SUBJECT=$(echo "$META" | jq -r '.payload.headers[] | select(.name == "Subject") | .value' 2>/dev/null || echo "(bez předmětu)")
  DATE=$(echo "$META" | jq -r '.payload.headers[] | select(.name == "Date") | .value' 2>/dev/null || echo "")
  SNIPPET=$(echo "$META" | jq -r '.snippet // ""' 2>/dev/null | cut -c1-100)

  echo "- Od: $FROM"
  echo "  Předmět: $SUBJECT"
  [[ -n "$DATE" ]] && echo "  Datum: $DATE"
  [[ -n "$SNIPPET" ]] && echo "  Náhled: $SNIPPET"
  echo ""
done
