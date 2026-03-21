#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"
REPO=$("$CONFIG" '.sources.gitlab.repo')

# Defaults
INSTRUCTION=""
PRIORITY="medium"
SIZE="m"
SOURCE="manual"
SOURCE_REF=""
RECURRING=""
STATUS=""
TITLE=""
WORKTREE=false
GOAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instruction) INSTRUCTION="$2"; shift 2 ;;
    --priority)    PRIORITY="$2"; shift 2 ;;
    --size)        SIZE="$2"; shift 2 ;;
    --source)      SOURCE="$2"; shift 2 ;;
    --source-ref)  SOURCE_REF="$2"; shift 2 ;;
    --recurring)   RECURRING="$2"; shift 2 ;;
    --status)      STATUS="$2"; shift 2 ;;
    --title)       TITLE="$2"; shift 2 ;;
    --worktree)    WORKTREE=true; shift ;;
    --goal)        GOAL="$2"; shift 2 ;;
    # legacy --assignee flag: silently ignored
    --assignee)    shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$INSTRUCTION" ]]; then
  echo "Error: --instruction required" >&2
  exit 1
fi

# Title: explicit override or first ~80 chars of instruction
if [[ -z "$TITLE" ]]; then
  TITLE="${INSTRUCTION:0:80}"
fi

# Determine status based on source if not explicitly set
# source:slack (direct user request) → status:todo (skip triage)
# everything else → status:triage (needs approval)
if [[ -z "$STATUS" ]]; then
  if [[ "$SOURCE" == "slack" ]]; then
    STATUS="todo"
  else
    STATUS="triage"
  fi
fi

# Build labels (no assignee:agent — all status:todo issues are picked up by workers)
LABELS="status:${STATUS},priority:${PRIORITY},size:${SIZE},source:${SOURCE}"

if [[ "$SIZE" == "l" || "$SIZE" == "xl" ]]; then
  LABELS="${LABELS},pipeline,phase:brainstorm"
fi

if [[ "$WORKTREE" == true ]]; then
  LABELS="${LABELS},worktree"
fi

if [[ -n "$GOAL" ]]; then
  LABELS="${LABELS},goal:${GOAL}"
fi

# Build issue body
GOAL_SECTION=""
if [[ -n "$GOAL" ]]; then
  GOAL_SECTION="
## Goal
${GOAL}
"
fi

BODY="## Task

${INSTRUCTION}
${GOAL_SECTION}
## Metadata
- Source Ref: ${SOURCE_REF}
- Waiting On:
- Recurring: ${RECURRING}

## Worker Notes
"

# Create issue
ISSUE_URL=$(glab issue create \
  --repo "$REPO" \
  --title "$TITLE" \
  --description "$BODY" \
  --label "$LABELS" \
  --yes)

ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
echo "$ISSUE_NUMBER"
