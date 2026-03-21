#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"
REPO=$("$CONFIG" '.sources.gitlab.repo')
MAX_CONCURRENT=$($CONFIG '.skills.worker.max_concurrent')

# Count in-progress tasks
IN_PROGRESS=$(glab issue list --repo "$REPO" --label "status:in-progress" --output json 2>/dev/null | jq 'length')

if [[ "$IN_PROGRESS" -ge "$MAX_CONCURRENT" ]]; then
  exit 0
fi

# Find highest priority Todo task
NEXT_ISSUE=$(glab issue list --repo "$REPO" --label "status:todo" --output json 2>/dev/null | jq -r '
  [.[]
    | . + {
        priority_weight: (
          [.labels[] | select(startswith("priority:"))] | first // "priority:medium"
          | split(":")[1]
          | if . == "urgent" then 0
            elif . == "high" then 1
            elif . == "medium" then 2
            elif . == "low" then 3
            else 9 end
        )
      }
  ]
  | sort_by(.priority_weight, .iid)
  | if length > 0 then first.iid else empty end
')

if [[ -n "${NEXT_ISSUE:-}" ]]; then
  echo "$NEXT_ISSUE"
fi
