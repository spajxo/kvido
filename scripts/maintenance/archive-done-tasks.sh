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

# Resolve the task.sh helper (prefer KVIDO_ROOT / script-relative path)
_resolve_task_sh() {
  # Try KVIDO_ROOT (set when running inside Claude Code plugin context)
  if [[ -n "${KVIDO_ROOT:-}" && -f "$KVIDO_ROOT/scripts/worker/task.sh" ]]; then
    echo "$KVIDO_ROOT/scripts/worker/task.sh"
    return
  fi
  # Try relative to this script's location
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local candidate="$script_dir/../worker/task.sh"
  if [[ -f "$candidate" ]]; then
    echo "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
    return
  fi
  echo "task.sh not found" >&2
  exit 1
}

TASK_SH="$(_resolve_task_sh)"

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
    (( skipped++ )) || true
    continue
  fi

  if (( file_epoch < cutoff_epoch )); then
    # Extract slug from filename (strip leading NNN- task ID prefix)
    slug=$(basename "$f" .md | sed 's/^[0-9]*-//')
    task_id=$(basename "$f" .md | grep -o '^[0-9]*' || echo "")

    identifier="${task_id:-$slug}"

    if "$TASK_SH" move "$identifier" archive >/dev/null 2>&1; then
      echo "archived: $(basename "$f")"
      (( archived++ )) || true
    else
      echo "WARN: failed to archive $(basename "$f")" >&2
      (( skipped++ )) || true
    fi
  fi
done

echo "ARCHIVE_DONE_TASKS: archived=$archived skipped=$skipped days=$DAYS"
