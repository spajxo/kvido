#!/usr/bin/env bash
set -euo pipefail

# PreCompact hook — injects dynamic session state summary before compaction.

cat > /dev/null

# Skip context injection for non-kvido sessions
if [[ -z "${KVIDO_SESSION:-}" ]]; then
  jq -n '{"continue": true}'
  exit 0
fi

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

CONTEXT="# Session Context"$'\n\n'

# Project info
if [[ -n "$PROJECT_DIR" ]] && git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
  CONTEXT+="## Project"$'\n'
  CONTEXT+="- Path: $PROJECT_DIR"$'\n'
  CONTEXT+="- Branch: $(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo unknown)"$'\n'
  CONTEXT+="- Dirty files: $(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l)"$'\n\n'
fi

# State summary
CONTEXT+="## State"$'\n'

if [[ -f "$KVIDO_HOME/state/current.md" ]]; then
  FOCUS=$(grep -A1 "## Active Focus" "$KVIDO_HOME/state/current.md" 2>/dev/null | tail -1 || echo "")
  WIP_COUNT=$(sed -n '/## Work in Progress/,/## /p' "$KVIDO_HOME/state/current.md" 2>/dev/null | grep -c "^\- " 2>/dev/null || true)
  CONTEXT+="- Focus: ${FOCUS:-none}"$'\n'
  CONTEXT+="- WIP: ${WIP_COUNT:-0} items"$'\n'
fi

ITER=$(kvido state get heartbeat.iteration_count 2>/dev/null || echo 0)
CONTEXT+="- Heartbeat iteration: $ITER"$'\n'

if [[ -d "$KVIDO_HOME/tasks" ]]; then
  TODO=$(find "$KVIDO_HOME/tasks/todo/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  WIP_T=$(find "$KVIDO_HOME/tasks/in-progress/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  TRIAGE=$(find "$KVIDO_HOME/tasks/triage/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  CONTEXT+="- Tasks: ${TODO} todo, ${WIP_T} in-progress, ${TRIAGE} triage"$'\n'
fi

jq -n --arg msg "$CONTEXT" \
  '{"continue": true, "systemMessage": $msg}'
