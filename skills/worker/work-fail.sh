#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"
REPO=$(git remote get-url origin 2>/dev/null | sed 's|.*[:/]\([^/]*/[^/]*\)\.git$|\1|; s|.*[:/]\([^/]*/[^/]*\)$|\1|')

ISSUE=""
REASON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)  ISSUE="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ISSUE" ]]; then
  echo "Error: --issue required" >&2
  exit 1
fi

if [[ -n "$REASON" ]]; then
  glab issue note "$ISSUE" --repo "$REPO" --message "## Failed

$REASON"
fi

# Remove status/phase labels, add result
LABELS=$(glab issue view "$ISSUE" --repo "$REPO" --output json | jq -r '.labels[]')
REMOVE_LABELS=""
for label in $LABELS; do
  case "$label" in
    status:*|phase:*) REMOVE_LABELS="${REMOVE_LABELS:+$REMOVE_LABELS,}$label" ;;
  esac
done
if [[ -n "$REMOVE_LABELS" ]]; then
  glab issue update "$ISSUE" --repo "$REPO" --unlabel "$REMOVE_LABELS" --label "result:failed" >/dev/null
else
  glab issue update "$ISSUE" --repo "$REPO" --label "result:failed" >/dev/null
fi

glab issue close "$ISSUE" --repo "$REPO" >/dev/null

echo "FAILED: #$ISSUE"
