#!/usr/bin/env bash
set -euo pipefail

# build-context.sh — generates session context markdown to stdout
# Shared by session-start.sh (SessionStart hook) and pre-compact.sh (PreCompact hook).
# Also called by kvido CLI before launching Claude.

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "# Session Context"
echo ""

# Project info
PROJECT="${KVIDO_PROJECT:-}"
if [[ -n "$PROJECT" ]] && git -C "$PROJECT" rev-parse --git-dir &>/dev/null 2>&1; then
  echo "## Project"
  echo "- Path: $PROJECT"
  echo "- Branch: $(git -C "$PROJECT" branch --show-current 2>/dev/null || echo unknown)"
  echo "- Dirty files: $(git -C "$PROJECT" status --porcelain 2>/dev/null | wc -l)"
  echo ""
fi

# State summary
if [[ -f "$KVIDO_HOME/state/current.md" ]]; then
  FOCUS=$(grep -A1 "## Active Focus" "$KVIDO_HOME/state/current.md" 2>/dev/null | tail -1 || echo "")
  # grep -c outputs "0" and exits 1 when no matches — valid for empty WIP section
  WIP_COUNT=$(sed -n '/## Work in Progress/,/## /p' "$KVIDO_HOME/state/current.md" 2>/dev/null | grep -c "^\- " 2>/dev/null || true)
  echo "## State"
  echo "- Focus: ${FOCUS:-none}"
  echo "- WIP: ${WIP_COUNT:-0} items"
fi

ITER=$(kvido state get heartbeat.iteration_count 2>/dev/null || echo 0)
echo "- Heartbeat iteration: $ITER"

if [[ -d "$KVIDO_HOME/state/tasks" ]]; then
  TODO=$(find "$KVIDO_HOME/state/tasks/todo/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  WIP_T=$(find "$KVIDO_HOME/state/tasks/in-progress/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  TRIAGE=$(find "$KVIDO_HOME/state/tasks/triage/" -name "*.md" 2>/dev/null | wc -l || echo 0)
  echo "- Tasks: ${TODO} todo, ${WIP_T} in-progress, ${TRIAGE} triage"
fi

echo ""

# Plugin session context contributions
bash "$PLUGIN_ROOT/skills/context/context.sh" session 2>/dev/null || echo "ERROR: context.sh session failed (exit $?)" >&2
