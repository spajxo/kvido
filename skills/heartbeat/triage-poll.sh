#!/usr/bin/env bash
# triage-poll.sh — Deterministic triage reaction polling
# Reads JSON array of triage items on stdin, polls Slack reactions, executes approve/reject.
# Input:  [{"issue":"7","ts":"1773933088.437"},...]
# Output: [{"issue":"7","result":"approved|rejected|pending"},...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SLACK_SH="$PLUGIN_ROOT/skills/slack/slack.sh"
CANCEL_SH="$PLUGIN_ROOT/skills/worker/work-cancel.sh"
CONFIG_SH="$PLUGIN_ROOT/skills/config.sh"

REPO=$("$CONFIG_SH" '.sources.gitlab.repo')

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
  ISSUE=$(echo "$INPUT" | jq -r ".[$i].issue")
  TS=$(echo "$INPUT" | jq -r ".[$i].ts")

  # Poll reactions
  REACTIONS=$("$SLACK_SH" reactions "$TS" 2>/dev/null || echo '{}')
  APPROVED=$(echo "$REACTIONS" | jq -r '.white_check_mark // .thumbsup // "false"')
  REJECTED=$(echo "$REACTIONS" | jq -r '.x // .thumbsdown // "false"')

  if [[ "$APPROVED" == "true" ]]; then
    # Move issue to todo
    glab issue update "$ISSUE" --repo "$REPO" --unlabel "status:triage" --label "status:todo" >/dev/null 2>&1 || true
    RESULTS=$(echo "$RESULTS" | jq --arg issue "$ISSUE" '. + [{"issue": $issue, "result": "approved"}]')
  elif [[ "$REJECTED" == "true" ]]; then
    # Cancel issue
    "$CANCEL_SH" --issue "$ISSUE" --reason "Rejected via triage reaction" >/dev/null 2>&1 || true
    RESULTS=$(echo "$RESULTS" | jq --arg issue "$ISSUE" '. + [{"issue": $issue, "result": "rejected"}]')
  else
    RESULTS=$(echo "$RESULTS" | jq --arg issue "$ISSUE" '. + [{"issue": $issue, "result": "pending"}]')
  fi
done

echo "$RESULTS"
