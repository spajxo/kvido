#!/usr/bin/env bash
# task.sh — Central helper for managing local tasks
#
# Usage: task.sh <command> [args...]
#
# Commands:
#   create   --title "..." --instruction "..." [--priority medium] [--size m] ...
#   read     <slug>           # key=value output
#   read-raw <slug>           # full file contents
#   update   <slug> <key> <value>  # update frontmatter field
#   move     <slug> <status>  # move between folders
#   list     <status> [--sort priority]  # list slugs
#   find     <slug>           # returns current status
#   note     <slug> <message> # append to ## Worker Notes
#   count    <status>         # number of tasks in folder

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
TASKS_DIR="${TASKS_DIR:-${KVIDO_HOME}/state/tasks}"
STATUSES="triage todo in-progress done failed cancelled"

# --- Helpers ---

_slugify() {
  local title="$1"
  echo "$title" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9čďěňřšťůžáéíóúý -]//g' \
    | sed 's/č/c/g; s/ď/d/g; s/[ěéë]/e/g; s/[ňñ]/n/g; s/[řŕ]/r/g; s/[šś]/s/g; s/[ťτ]/t/g; s/[ůúü]/u/g; s/[žź]/z/g; s/[áàâ]/a/g; s/[íìî]/i/g; s/[óòô]/o/g' \
    | sed 's/ \+/-/g; s/-\+/-/g; s/^-//; s/-$//' \
    | cut -c1-60
}

_unique_slug() {
  local base="$1"
  local slug="$base"
  local suffix=2

  # Check across all status folders for global uniqueness
  while _find_task "$slug" >/dev/null 2>&1; do
    slug="${base}-${suffix}"
    suffix=$((suffix + 1))
  done
  echo "$slug"
}

_find_task() {
  local slug="$1"
  for status_dir in $STATUSES; do
    if [[ -f "$TASKS_DIR/$status_dir/$slug.md" ]]; then
      echo "$status_dir"
      return 0
    fi
  done
  return 1
}

_task_file() {
  local slug="$1"
  local status
  status=$(_find_task "$slug") || { echo "Error: task '$slug' not found" >&2; exit 1; }
  echo "$TASKS_DIR/$status/$slug.md"
}

_read_frontmatter() {
  local file="$1" key="$2"
  awk '/^---$/{c++; next} c==1' "$file" \
    | awk -v k="$key" '{
        if (index($0, k ": ") == 1) { print substr($0, length(k) + 3); found=1; exit }
      } END { if (!found) print "" }'
}

_update_frontmatter() {
  local file="$1" key="$2" value="$3"
  local tmp="${file}.tmp"
  awk -v k="$key" -v v="$value" '
    /^---$/ { c++; if (c == 2 && !found) print k ": " v; print; next }
    c == 1 && index($0, k ": ") == 1 { print k ": " v; found = 1; next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

_yaml_val() {
  local v="$1"
  case "$v" in
    *[:\#\[\]\{\},\|]*|true|false|null|"") printf '"%s"' "$v" ;;
    *) printf '%s' "$v" ;;
  esac
}

_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

_priority_weight() {
  case "${1:-medium}" in
    urgent) echo 0 ;;
    high)   echo 1 ;;
    medium) echo 2 ;;
    low)    echo 3 ;;
    *)      echo 9 ;;
  esac
}

# --- Commands ---

cmd_create() {
  local INSTRUCTION="" PRIORITY="medium" SIZE="m" SOURCE="manual"
  local SOURCE_REF="" RECURRING="" STATUS="" TITLE="" GOAL=""
  local WORKTREE=false

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
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$INSTRUCTION" ]]; then
    echo "Error: --instruction required" >&2
    exit 1
  fi

  # Title: explicit or first ~80 chars of instruction
  [[ -z "$TITLE" ]] && TITLE="${INSTRUCTION:0:80}"

  # Status: slack → todo (skip triage), else → triage
  if [[ -z "$STATUS" ]]; then
    if [[ "$SOURCE" == "slack" ]]; then
      STATUS="todo"
    else
      STATUS="triage"
    fi
  fi

  # Pipeline auto-enable for large tasks
  local PIPELINE=false PHASE="null"
  if [[ "$SIZE" == "l" || "$SIZE" == "xl" ]]; then
    PIPELINE=true
    PHASE="brainstorm"
  fi

  # Generate slug
  local base_slug slug
  base_slug=$(_slugify "$TITLE")
  [[ -z "$base_slug" ]] && base_slug="task"
  slug=$(_unique_slug "$base_slug")

  local NOW
  NOW=$(_now)

  # Ensure directory exists
  mkdir -p "$TASKS_DIR/$STATUS"

  local file="$TASKS_DIR/$STATUS/$slug.md"

  # Generate frontmatter with safe quoting
  local phase_val="${PHASE}"
  [[ "$phase_val" == "null" ]] && phase_val=""
  local goal_val="${GOAL:-}"
  [[ "$goal_val" == "null" ]] && goal_val=""
  local recurring_val="${RECURRING:-}"
  [[ "$recurring_val" == "null" ]] && recurring_val=""

  cat > "$file" << EOF
---
title: $(_yaml_val "$TITLE")
priority: $PRIORITY
size: $SIZE
source: $SOURCE
source_ref: $(_yaml_val "$SOURCE_REF")
pipeline: $PIPELINE
phase: $phase_val
worktree: $WORKTREE
goal: $goal_val
recurring: $recurring_val
waiting_on: ""
created_at: $NOW
updated_at: $NOW
triage_slack_ts: ""
---

## Instruction

$INSTRUCTION

## Worker Notes

EOF

  echo "$slug"
}

cmd_read() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "Usage: task.sh read <slug>" >&2; exit 1; }

  local file
  file=$(_task_file "$slug")
  local status
  status=$(_find_task "$slug")

  echo "SLUG=$slug"
  echo "STATUS=$status"
  echo "TITLE=$(_read_frontmatter "$file" 'title')"
  echo "PRIORITY=$(_read_frontmatter "$file" 'priority')"
  echo "SIZE=$(_read_frontmatter "$file" 'size')"
  echo "SOURCE=$(_read_frontmatter "$file" 'source')"
  echo "SOURCE_REF=$(_read_frontmatter "$file" 'source_ref')"
  echo "PIPELINE=$(_read_frontmatter "$file" 'pipeline')"
  echo "PHASE=$(_read_frontmatter "$file" 'phase')"
  echo "WORKTREE=$(_read_frontmatter "$file" 'worktree')"
  echo "GOAL=$(_read_frontmatter "$file" 'goal')"
  echo "RECURRING=$(_read_frontmatter "$file" 'recurring')"
  echo "WAITING_ON=$(_read_frontmatter "$file" 'waiting_on')"
  echo "CREATED_AT=$(_read_frontmatter "$file" 'created_at')"
  echo "UPDATED_AT=$(_read_frontmatter "$file" 'updated_at')"
  echo "TRIAGE_SLACK_TS=$(_read_frontmatter "$file" 'triage_slack_ts')"

  # Extract instruction from body
  local instruction
  instruction=$(sed -n '/^## Instruction/,/^## /{/^## /!p}' "$file" | sed '/^$/d' | head -5)
  echo "INSTRUCTION=$instruction"
}

cmd_read_raw() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "Usage: task.sh read-raw <slug>" >&2; exit 1; }

  local file
  file=$(_task_file "$slug")
  cat "$file"
}

cmd_update() {
  local slug="${1:-}" key="${2:-}" value="${3:-}"
  [[ -z "$slug" || -z "$key" ]] && { echo "Usage: task.sh update <slug> <key> <value>" >&2; exit 1; }

  local file
  file=$(_task_file "$slug")
  _update_frontmatter "$file" "$key" "$value"
  _update_frontmatter "$file" "updated_at" "$(_now)"
}

cmd_move() {
  local slug="${1:-}" target="${2:-}"
  [[ -z "$slug" || -z "$target" ]] && { echo "Usage: task.sh move <slug> <status>" >&2; exit 1; }

  local current
  current=$(_find_task "$slug") || { echo "Error: task '$slug' not found" >&2; exit 1; }

  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  mkdir -p "$TASKS_DIR/$target"

  local src="$TASKS_DIR/$current/$slug.md"
  local dst="$TASKS_DIR/$target/$slug.md"

  mv "$src" "$dst"
  _update_frontmatter "$dst" "updated_at" "$(_now)"
}

cmd_list() {
  local status="${1:-}" sort_mode=""
  shift || true

  [[ -z "$status" ]] && { echo "Usage: task.sh list <status> [--sort priority]" >&2; exit 1; }

  local dir="$TASKS_DIR/$status"
  [[ ! -d "$dir" ]] && exit 0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sort) sort_mode="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ "$sort_mode" == "priority" ]]; then
    # Read all tasks, sort by priority weight then created_at
    local entries="" slug priority created_at weight
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      slug=$(basename "$f" .md)
      priority=$(_read_frontmatter "$f" "priority")
      [[ -z "$priority" ]] && priority="medium"
      created_at=$(_read_frontmatter "$f" "created_at")
      weight=$(_priority_weight "$priority")
      entries="${entries}${weight} ${created_at} ${slug}\n"
    done
    if [[ -n "$entries" ]]; then
      printf '%b' "$entries" | sort -t' ' -k1,1n -k2,2 | awk '{print $3}'
    fi
  else
    # Simple listing by filename
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      basename "$f" .md
    done
  fi
}

cmd_find() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "Usage: task.sh find <slug>" >&2; exit 1; }

  _find_task "$slug" || { echo "Error: task '$slug' not found" >&2; exit 1; }
}

cmd_note() {
  local slug="${1:-}" message="${2:-}"
  [[ -z "$slug" || -z "$message" ]] && { echo "Usage: task.sh note <slug> <message>" >&2; exit 1; }

  local file
  file=$(_task_file "$slug")

  # Append to end of file (after ## Worker Notes)
  printf '\n%s\n' "$message" >> "$file"
  _update_frontmatter "$file" "updated_at" "$(_now)"
}

cmd_count() {
  local status="${1:-}"
  [[ -z "$status" ]] && { echo "Usage: task.sh count <status>" >&2; exit 1; }

  local dir="$TASKS_DIR/$status"
  if [[ ! -d "$dir" ]]; then
    echo 0
    return
  fi

  local count=0
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] && count=$((count + 1))
  done
  echo "$count"
}

# --- Main ---

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  create)   cmd_create "$@" ;;
  read)     cmd_read "$@" ;;
  read-raw) cmd_read_raw "$@" ;;
  update)   cmd_update "$@" ;;
  move)     cmd_move "$@" ;;
  list)     cmd_list "$@" ;;
  find)     cmd_find "$@" ;;
  note)     cmd_note "$@" ;;
  count)    cmd_count "$@" ;;
  *)
    echo "Usage: task.sh <create|read|read-raw|update|move|list|find|note|count> [args...]" >&2
    exit 1
    ;;
esac
