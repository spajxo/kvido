#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook — injects session context into Claude conversation.
# Only activates when launched via kvido wrapper (KVIDO_SESSION=1).

cat > /dev/null

# Skip context injection for non-kvido sessions
if [[ -z "${KVIDO_SESSION:-}" ]]; then
  jq -n '{"continue": true}'
  exit 0
fi

# Show owl banner
cat >&2 << 'OWL'

        ^...^
       / o,o \
       |):::(|
     ====w=w====
       kvido

OWL

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
OUTPUT="$KVIDO_HOME/state/session-context.md"

mkdir -p "$KVIDO_HOME/state"

KVIDO_PROJECT="$PROJECT_DIR" bash "$SCRIPT_DIR/build-context.sh" > "$OUTPUT" 2>/dev/null || true

if [[ ! -s "$OUTPUT" ]]; then
  jq -n '{"continue": true}'
  exit 0
fi

SESSION_CONTEXT="$(cat "$OUTPUT")"

jq -n \
  --arg ctx "$SESSION_CONTEXT" \
  '{
    "continue": true,
    "suppressOutput": true,
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": $ctx
    }
  }'
