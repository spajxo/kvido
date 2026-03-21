#!/usr/bin/env bash
set -euo pipefail

# Stay in the current directory (user's workspace), not the plugin cache
# Load .env from the workspace
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

MODEL="${CLAUDE_MODEL:-claude-sonnet-4-6}"
PROMPT="${*:-/loop 5m /heartbeat}"

# shellcheck disable=SC2086
exec claude \
  --permission-mode="${CLAUDE_PERMISSION_MODE:-default}" \
  --model="$MODEL" \
  --name="${ASSISTANT_NAME:-kvido}" \
  ${CLAUDE_ADDITIONAL_OPTIONS:-} \
  "$PROMPT"
