#!/usr/bin/env bash
# source-inbox/fetch.sh — list unprocessed files in inbox
# Usage: ./fetch.sh
# Output: list of files waiting for ingest

set -euo pipefail

INBOX_PATH=$(kvido config 'inbox.path' "$KVIDO_HOME/inbox")

if [[ ! -d "$INBOX_PATH" ]]; then
  echo "Inbox: no directory"
  exit 0
fi

# List files, exclude processed/ subdirectory
FILES=$(find "$INBOX_PATH" -maxdepth 1 -type f 2>/dev/null | sort)

if [[ -z "$FILES" ]]; then
  echo "Inbox: empty"
  exit 0
fi

COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
echo "Inbox: $COUNT file(s) waiting"
echo ""

echo "$FILES" | while read -r FILE; do
  BASENAME=$(basename "$FILE")
  SIZE=$(stat --format='%s' "$FILE" 2>/dev/null || stat -f '%z' "$FILE" 2>/dev/null || echo "?")
  MTIME=$(stat --format='%Y' "$FILE" 2>/dev/null || stat -f '%m' "$FILE" 2>/dev/null || echo "?")
  echo "- $BASENAME (${SIZE}B, mtime:${MTIME})"
done
