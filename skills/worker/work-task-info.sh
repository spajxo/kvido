#!/usr/bin/env bash
# work-task-info.sh — Get task info from GitLab Issue labels + body
#
# Usage:
#   work-task-info.sh <ISSUE_NUMBER>
#
# Output (key=value):
#   TASK_ID, SIZE, PRIORITY, SOURCE, ASSIGNEE, STATUS, PIPELINE, PHASE, GOAL,
#   INSTRUCTION, SOURCE_REF, WAITING_ON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"
REPO=$("$CONFIG" '.sources.gitlab.repo')

ISSUE_NUMBER="${1:-}"
[[ -z "$ISSUE_NUMBER" ]] && { echo "Usage: work-task-info.sh <ISSUE_NUMBER>" >&2; exit 1; }

# Get issue details in one call
ISSUE_JSON=$(glab issue view "$ISSUE_NUMBER" --repo "$REPO" --output json)

TASK_ID=$(echo "$ISSUE_JSON" | jq -r '.iid')
LABELS=$(echo "$ISSUE_JSON" | jq -r '.labels[]')
BODY=$(echo "$ISSUE_JSON" | jq -r '.description // ""')

# Extract from labels
PRIORITY=$(echo "$LABELS" | sed -n 's/^priority://p' | head -1)
SIZE=$(echo "$LABELS" | sed -n 's/^size://p' | head -1)
SOURCE=$(echo "$LABELS" | sed -n 's/^source://p' | head -1)
ASSIGNEE=$(echo "$LABELS" | sed -n 's/^assignee://p' | head -1)
STATUS=$(echo "$LABELS" | sed -n 's/^status://p' | head -1)
PHASE=$(echo "$LABELS" | sed -n 's/^phase://p' | head -1)
GOAL=$(echo "$LABELS" | sed -n 's/^goal://p' | head -1)

if echo "$LABELS" | grep -qx 'pipeline'; then
  PIPELINE="enabled"
else
  PIPELINE="disabled"
fi

if echo "$LABELS" | grep -qx 'worktree'; then
  WORKTREE="true"
else
  WORKTREE="false"
fi

# Extract from body
INSTRUCTION=""
SOURCE_REF=""
WAITING_ON=""

if [[ -n "$BODY" ]]; then
  # ## Task section: first non-empty line after header
  INSTRUCTION=$(echo "$BODY" | awk '/^## Task/{found=1; next} found && /^## /{exit} found && NF{print; exit}')
  [[ -z "$INSTRUCTION" ]] && INSTRUCTION=$(echo "$BODY" | awk 'NF{print; exit}')

  SOURCE_REF=$(echo "$BODY" | grep -oP '(?<=- Source Ref: ).+' | head -1 || true)
  WAITING_ON=$(echo "$BODY" | grep -oP '(?<=- Waiting On: ).+' | head -1 || true)
fi

echo "TASK_ID=$TASK_ID"
echo "SIZE=${SIZE:-}"
echo "PRIORITY=${PRIORITY:-}"
echo "SOURCE=${SOURCE:-}"
echo "ASSIGNEE=${ASSIGNEE:-}"
echo "STATUS=${STATUS:-}"
echo "PIPELINE=$PIPELINE"
echo "PHASE=${PHASE:-}"
echo "INSTRUCTION=${INSTRUCTION:-}"
echo "SOURCE_REF=${SOURCE_REF:-}"
echo "WAITING_ON=${WAITING_ON:-}"
echo "WORKTREE=$WORKTREE"
echo "GOAL=${GOAL:-}"
