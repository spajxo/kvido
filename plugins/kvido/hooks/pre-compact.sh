#!/usr/bin/env bash
set -euo pipefail

# PreCompact hook — injects session context summary before compaction.

cat > /dev/null

# Skip context injection for non-kvido sessions
if [[ -z "${KVIDO_SESSION:-}" ]]; then
  jq -n '{"continue": true}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

CONTEXT=$(KVIDO_PROJECT="$PROJECT_DIR" bash "$SCRIPT_DIR/build-context.sh" 2>/dev/null || true)

if [[ -n "$CONTEXT" ]]; then
  jq -n --arg msg "$CONTEXT" \
    '{"continue": true, "systemMessage": $msg}'
else
  jq -n '{"continue": true}'
fi
