#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"
REPO=$("$CONFIG" '.sources.gitlab.repo')

ISSUE=""
SUMMARY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)   ISSUE="$2"; shift 2 ;;
    --summary) SUMMARY="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ISSUE" ]]; then
  echo "Error: --issue required" >&2
  exit 1
fi

# Add summary comment
if [[ -n "$SUMMARY" ]]; then
  glab issue note "$ISSUE" --repo "$REPO" --message "## Result

$SUMMARY"
fi

# Fetch issue data once (used for label cleanup + recurring check)
ISSUE_JSON=$(glab issue view "$ISSUE" --repo "$REPO" --output json)
LABELS=$(echo "$ISSUE_JSON" | jq -r '.labels[]')

# Check pipeline phase transition: implement → review instead of closing
HAS_PIPELINE=$(echo "$LABELS" | grep -c '^pipeline$' || true)
CURRENT_PHASE=$(echo "$LABELS" | grep -oP '^phase:\K.*' || true)

if [[ "$HAS_PIPELINE" -gt 0 && "$CURRENT_PHASE" == "implement" ]]; then
  # Move to review phase instead of closing
  glab issue update "$ISSUE" --repo "$REPO" --unlabel "status:in-progress,phase:implement" --label "status:todo,phase:review" >/dev/null
  echo "REVIEW: #$ISSUE (implement → review)"
  exit 0
fi

# Remove status/phase labels, add result
REMOVE_LABELS=""
for label in $LABELS; do
  case "$label" in
    status:*|phase:*) REMOVE_LABELS="${REMOVE_LABELS:+$REMOVE_LABELS,}$label" ;;
  esac
done
if [[ -n "$REMOVE_LABELS" ]]; then
  glab issue update "$ISSUE" --repo "$REPO" --unlabel "$REMOVE_LABELS" --label "result:done" >/dev/null
else
  glab issue update "$ISSUE" --repo "$REPO" --label "result:done" >/dev/null
fi

glab issue close "$ISSUE" --repo "$REPO" >/dev/null

# Handle recurring
HAS_RECURRING=$(echo "$LABELS" | grep -c '^source:recurring$' || true)

if [[ "$HAS_RECURRING" -gt 0 ]]; then
  TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
  BODY=$(echo "$ISSUE_JSON" | jq -r '.description // ""')

  # Parse Recurring from body metadata
  RECURRING_VALUE=$(echo "$BODY" | grep -oP '(?<=- Recurring: ).+' | head -1 || true)

  if [[ -n "$RECURRING_VALUE" ]]; then
    PRIORITY=$(echo "$ISSUE_JSON" | jq -r '[.labels[] | select(startswith("priority:"))] | first // "priority:medium"' | sed 's/^priority://')
    SIZE=$(echo "$ISSUE_JSON" | jq -r '[.labels[] | select(startswith("size:"))] | first // "size:m"' | sed 's/^size://')

    NEW_ISSUE=$("$SCRIPT_DIR/work-add.sh" \
      --instruction "$TITLE" \
      --priority "$PRIORITY" \
      --size "$SIZE" \
      --source recurring \
      --recurring "$RECURRING_VALUE")

    echo "RECURRING: #$NEW_ISSUE"
  fi
  echo "DONE+RECURRING: #$ISSUE"
  exit 0
fi

echo "DONE: #$ISSUE"
