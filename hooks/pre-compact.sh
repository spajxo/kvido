#!/usr/bin/env bash
set -euo pipefail

# Read JSON input from stdin
cat > /dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
STATE_DIR="$REPO_DIR/state"

# Build context summary to inject into conversation after compaction
SUMMARY=""

if [[ -f "$STATE_DIR/current.md" ]]; then
  FOCUS=$(grep -A1 "## Active Focus" "$STATE_DIR/current.md" 2>/dev/null | tail -1 || echo "")
  WIP_COUNT=$(sed -n '/## Work in Progress/,/## /p' "$STATE_DIR/current.md" 2>/dev/null | grep -c "^\- " 2>/dev/null || true)
  WIP_COUNT="${WIP_COUNT:-0}"
  SUMMARY="Focus: ${FOCUS:-none}. WIP: ${WIP_COUNT} items."
fi

if [[ -f "$STATE_DIR/heartbeat-state.json" ]]; then
  ITER=$(jq -r '.iteration_count // 0' "$STATE_DIR/heartbeat-state.json" 2>/dev/null || echo "0")
  SUMMARY="$SUMMARY Heartbeat iteration: $ITER."
fi

# Task queue summary
if [[ -d "$STATE_DIR/tasks" ]]; then
  TODO_COUNT=$(find "$STATE_DIR/tasks/todo/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  WIP_TASKS=$(find "$STATE_DIR/tasks/in-progress/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  TRIAGE_COUNT=$(find "$STATE_DIR/tasks/triage/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  SUMMARY="$SUMMARY Tasks: ${TODO_COUNT} todo, ${WIP_TASKS} in-progress, ${TRIAGE_COUNT} triage."
fi

if [[ -n "$SUMMARY" ]]; then
  jq -n --arg msg "State summary before compact: $SUMMARY Reload state files for full context." \
    '{"continue": true, "systemMessage": $msg}'
else
  jq -n '{"continue": true}'
fi
