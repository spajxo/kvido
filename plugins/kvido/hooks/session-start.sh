#!/usr/bin/env bash
set -euo pipefail

# Read JSON input from stdin. We don't need the payload yet, but consuming it
# keeps the hook behavior aligned with Claude Code's hook contract.
cat > /dev/null

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
OUTPUT="$KVIDO_HOME/state/session-context.md"

mkdir -p "$KVIDO_HOME/state"

# Reuse the existing session assembler so SessionStart, /clear, and /compact all
# rebuild the same context file before injecting it back into Claude.
KVIDO_PROJECT="$PROJECT_DIR" bash "$PLUGIN_ROOT/hooks/pre-session.sh" 2>/dev/null || true

if [[ ! -s "$OUTPUT" ]]; then
  jq -n '{"continue": true}'
  exit 0
fi

SESSION_CONTEXT="$(cat "$OUTPUT")"

jq -n \
  --arg msg "$SESSION_CONTEXT" \
  '{
    "continue": true,
    "suppressOutput": true,
    "systemMessage": $msg
  }'
