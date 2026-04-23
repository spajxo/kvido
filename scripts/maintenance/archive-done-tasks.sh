#!/usr/bin/env bash
# archive-done-tasks.sh — Move done tasks older than N days to tasks/archive/
#
# Usage: archive-done-tasks.sh [days]
#   days  — age threshold in days (default: 7)
#
# Reads UPDATED_AT from task frontmatter. Falls back to file modification
# time when the field is missing or unparseable.
#
# Called by the librarian agent as part of its Cleanup step.

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
TASKS_DIR="$KVIDO_HOME/tasks"
DONE_DIR="$TASKS_DIR/done"
ARCHIVE_DIR="$TASKS_DIR/archive"
DAYS="${1:-7}"

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "Error: DAYS must be a positive integer" >&2
  exit 1
fi

TASK_SH="${KVIDO_ROOT:+$KVIDO_ROOT/bin/kvido-task}"
if [[ -z "${TASK_SH:-}" || ! -x "$TASK_SH" ]]; then
  echo "kvido-task not found (KVIDO_ROOT=${KVIDO_ROOT:-unset})" >&2
  exit 1
fi

[[ ! -d "$DONE_DIR" ]] && exit 0

mkdir -p "$ARCHIVE_DIR"

now_epoch=$(date +%s)
cutoff_epoch=$(( now_epoch - DAYS * 86400 ))

archived=0
skipped=0

for f in "$DONE_DIR"/*.md; do
  [[ -e "$f" ]] || continue  # glob with no matches

  # Read UPDATED_AT from frontmatter
  updated_at=$(grep -m1 '^updated_at:' "$f" 2>/dev/null | sed 's/updated_at:[[:space:]]*//' | tr -d '"' | tr -d "'" || true)

  file_epoch=""
  if [[ -n "$updated_at" ]]; then
    # Parse ISO 8601 date — try date -d (GNU) then date -j (BSD/macOS)
    file_epoch=$(date -d "$updated_at" +%s 2>/dev/null \
      || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null \
      || true)
  fi

  # Fallback to file modification time
  if [[ -z "$file_epoch" ]]; then
    file_epoch=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || true)
  fi

  if [[ -z "$file_epoch" ]]; then
    echo "WARN: could not determine age of $(basename "$f"), skipping" >&2
    (( ++skipped ))
    continue
  fi

  if (( file_epoch < cutoff_epoch )); then
    # Extract slug from filename (strip leading NNN- task ID prefix)
    slug=$(basename "$f" .md | sed 's/^[0-9]*-//')
    task_id=$(basename "$f" .md | grep -o '^[0-9]*' || echo "")

    identifier="${task_id:-$slug}"

    if "$TASK_SH" move "$identifier" archive >/dev/null 2>&1; then
      echo "archived: $(basename "$f")"
      (( ++archived ))
    else
      echo "WARN: failed to archive $(basename "$f")" >&2
      (( ++skipped ))
    fi
  fi
done

echo "ARCHIVE_DONE_TASKS: archived=$archived skipped=$skipped days=$DAYS"
