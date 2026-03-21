#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"
REPO=$("$CONFIG" '.sources.gitlab.repo')

ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ISSUE" ]]; then
  echo "Error: --issue required" >&2
  exit 1
fi

# WIP limit check
MAX_CONCURRENT=$($CONFIG '.skills.worker.max_concurrent')

IN_PROGRESS=$(glab issue list --repo "$REPO" --label "status:in-progress" --output json 2>/dev/null | jq 'length')

if [[ "$IN_PROGRESS" -ge "$MAX_CONCURRENT" ]]; then
  echo "LOCKED"
  exit 1
fi

# Swap status label
glab issue update "$ISSUE" --repo "$REPO" --unlabel "status:todo" --label "status:in-progress" >/dev/null

# Pipeline: if has pipeline label but no phase label, set default
LABELS=$(glab issue view "$ISSUE" --repo "$REPO" --output json | jq -r '.labels[]')

if echo "$LABELS" | grep -qx 'pipeline'; then
  if ! echo "$LABELS" | grep -q '^phase:'; then
    SIZE_LABEL=$(echo "$LABELS" | grep -oP '^size:.+$' | head -1 || true)
    SIZE="${SIZE_LABEL#size:}"
    if [[ "$SIZE" == "l" || "$SIZE" == "xl" ]]; then
      glab issue update "$ISSUE" --repo "$REPO" --label "phase:brainstorm" >/dev/null
    else
      glab issue update "$ISSUE" --repo "$REPO" --label "phase:implement" >/dev/null
    fi
  fi
fi

echo "OK"
