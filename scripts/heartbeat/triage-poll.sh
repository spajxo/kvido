#!/usr/bin/env bash
# triage-poll.sh — Deterministic triage reaction polling
# Reads JSON array of triage items on stdin, polls Slack reactions, executes approve/reject.
# Input:  [{"slug":"fix-auth-bug","ts":"1773933088.437"},...]
# Output: [{"slug":"fix-auth-bug","result":"approved|rejected|pending"},...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SLACK_SH="$PLUGIN_ROOT/scripts/slack/slack.sh"
TASK_SH="$PLUGIN_ROOT/scripts/worker/task.sh"

# Read input from stdin
INPUT=$(cat)
COUNT=$(echo "$INPUT" | jq -r 'length')

if [[ "$COUNT" -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Max 5 items per iteration
if (( COUNT > 5 )); then
  COUNT=5
fi

RESULTS="[]"

for i in $(seq 0 $((COUNT - 1))); do
  SLUG=$(echo "$INPUT" | jq -r ".[$i].slug")
  TS=$(echo "$INPUT" | jq -r ".[$i].ts")

  # Poll reactions
  REACTIONS=$("$SLACK_SH" reactions "$TS" 2>/dev/null || echo '{}')
  APPROVED=$(echo "$REACTIONS" | jq -r '.white_check_mark // .thumbsup // "false"')
  REJECTED=$(echo "$REACTIONS" | jq -r '.x // .thumbsdown // "false"')

  if [[ "$APPROVED" == "true" ]]; then
    "$TASK_SH" move "$SLUG" todo >/dev/null 2>&1 || echo "ERROR: task move $SLUG to todo failed (exit $?)" >&2
    RESULTS=$(echo "$RESULTS" | jq --arg slug "$SLUG" '. + [{"slug": $slug, "result": "approved"}]')
  elif [[ "$REJECTED" == "true" ]]; then
    "$TASK_SH" note "$SLUG" "## Cancelled\n\nRejected via triage reaction" >/dev/null 2>&1 || echo "ERROR: task note $SLUG failed (exit $?)" >&2
    "$TASK_SH" move "$SLUG" cancelled >/dev/null 2>&1 || echo "ERROR: task move $SLUG to cancelled failed (exit $?)" >&2
    RESULTS=$(echo "$RESULTS" | jq --arg slug "$SLUG" '. + [{"slug": $slug, "result": "rejected"}]')
  else
    RESULTS=$(echo "$RESULTS" | jq --arg slug "$SLUG" '. + [{"slug": $slug, "result": "pending"}]')
  fi
done

echo "$RESULTS"
