#!/usr/bin/env bash
# task.sh — Central helper for managing local tasks
#
# Usage: task.sh <command> [args...]
#
# Task files are named <id>-<slug>.md (e.g. 42-fix-auth-bug.md).
# All commands accept either numeric ID or slug as identifier.
#
# Commands:
#   create      --title "..." --instruction "..." [--priority medium] [--size m] ...
#   read        <id|slug>           # key=value output
#   read-raw    <id|slug>           # full file contents
#   update      <id|slug> <key> <value>  # update frontmatter field
#   move        <id|slug> <status>  # move between folders
#   list        <status> [--sort priority] [--source SRC] [--format human|raw|slug-title]  # list tasks
#   find        <id|slug>           # returns current status
#   note        <id|slug> <message> # append to ## Worker Notes
#   count       <status>            # number of tasks in folder
#   migrate-ids                     # assign IDs to legacy tasks

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
TASKS_DIR="${TASKS_DIR:-${KVIDO_HOME}/state/tasks}"
STATUSES="triage todo in-progress done failed cancelled"

# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

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
    local dir="$TASKS_DIR/$status_dir"
    [[ -d "$dir" ]] || continue
    # New format: <id>-<slug>.md — validate extracted slug matches exactly
    for f in "$dir"/[0-9]*-"$slug".md; do
      [[ -f "$f" ]] || continue
      local base
      base=$(basename "$f" .md)
      [[ "${base#*-}" == "$slug" ]] && { echo "$status_dir"; return 0; }
    done
    # Legacy format: <slug>.md (pre-migration)
    if [[ -f "$dir/$slug.md" ]]; then
      echo "$status_dir"
      return 0
    fi
  done
  return 1
}

_task_file() {
  local slug="$1"
  for status_dir in $STATUSES; do
    local dir="$TASKS_DIR/$status_dir"
    [[ -d "$dir" ]] || continue
    for f in "$dir"/[0-9]*-"$slug".md; do
      [[ -f "$f" ]] || continue
      local base
      base=$(basename "$f" .md)
      [[ "${base#*-}" == "$slug" ]] && { echo "$f"; return 0; }
    done
    # Legacy format
    if [[ -f "$dir/$slug.md" ]]; then
      echo "$dir/$slug.md"
      return 0
    fi
  done
  echo "Error: task '$slug' not found" >&2
  exit 1
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
  local tmp
  tmp="$(_make_tmp "$file")"
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

_next_id() {
  local counter_file="$KVIDO_HOME/state/task_counter"
  local id=0
  [[ -f "$counter_file" ]] && id=$(cat "$counter_file")
  id=$((id + 1))
  mkdir -p "$(dirname "$counter_file")"
  local tmp
  tmp="$(_make_tmp "$counter_file")"
  echo "$id" > "$tmp" && mv "$tmp" "$counter_file"
  echo "$id"
}

_resolve_identifier() {
  local identifier="$1"
  # Slug match has priority
  if _find_task "$identifier" >/dev/null 2>&1; then
    echo "$identifier"
    return 0
  fi
  # If purely numeric, find by ID prefix in filename
  if [[ "$identifier" =~ ^[0-9]+$ ]]; then
    local status_dir dir f
    for status_dir in $STATUSES; do
      dir="$TASKS_DIR/$status_dir"
      [[ -d "$dir" ]] || continue
      for f in "$dir"/"$identifier"-*.md; do
        if [[ -f "$f" ]]; then
          local base
          base=$(basename "$f" .md)
          echo "${base#*-}"
          return 0
        fi
      done
    done
  fi
  echo "Error: task '$identifier' not found" >&2
  return 1
}

_slug_from_filename() {
  local base="$1"
  # New format: <id>-<slug> → strip numeric prefix
  if [[ "$base" =~ ^[0-9]+-(.+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    # Legacy format: bare slug
    echo "$base"
  fi
}

_id_from_filename() {
  local base="$1"
  # New format: <id>-<slug> → extract numeric prefix
  if [[ "$base" =~ ^([0-9]+)- ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "-"
  fi
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
      --goal)        GOAL="$2"; shift 2 ;;
      --worktree|--no-worktree) shift ;;  # deprecated, ignored
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$INSTRUCTION" ]]; then
    echo "Error: --instruction required" >&2
    exit 1
  fi

  # Title: explicit or first ~80 chars of instruction
  [[ -z "$TITLE" ]] && TITLE="${INSTRUCTION:0:80}"

  # Status: slack DM (user-initiated) → todo (skip triage), everything else → triage
  if [[ -z "$STATUS" ]]; then
    case "$SOURCE" in
      slack) STATUS="todo" ;;
      *) STATUS="triage" ;;
    esac
  fi

  # Generate slug and numeric ID
  local base_slug slug TASK_ID
  base_slug=$(_slugify "$TITLE")
  [[ -z "$base_slug" ]] && base_slug="task"
  slug=$(_unique_slug "$base_slug")
  TASK_ID=$(_next_id)

  local NOW
  NOW=$(_now)

  # Ensure directory exists
  mkdir -p "$TASKS_DIR/$STATUS"

  local file="$TASKS_DIR/$STATUS/${TASK_ID}-${slug}.md"

  # Generate frontmatter with safe quoting
  local goal_val="${GOAL:-}"
  [[ "$goal_val" == "null" ]] && goal_val=""
  local recurring_val="${RECURRING:-}"
  [[ "$recurring_val" == "null" ]] && recurring_val=""

  cat > "$file" << EOF
---
task_id: $TASK_ID
title: $(_yaml_val "$TITLE")
priority: $PRIORITY
size: $SIZE
source: $SOURCE
source_ref: $(_yaml_val "$SOURCE_REF")
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

_strip_yaml_quotes() { local v="$1"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; echo "$v"; }

_kv_out() {
  # Output KEY="value" — always double-quoted so values with spaces parse cleanly
  local key="$1" val="$2"
  # Strip surrounding YAML quotes if present (e.g. "foo" → foo)
  val=$(_strip_yaml_quotes "$val")
  # Escape double quotes inside the value to avoid broken output
  val="${val//\"/\\\"}"
  # Collapse newlines to literal \n for single-line output safe for eval
  val="${val//$'\n'/\\n}"
  printf '%s="%s"\n' "$key" "$val"
}

cmd_read() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "Usage: task.sh read <id|slug>" >&2; exit 1; }
  slug=$(_resolve_identifier "$slug") || exit 1

  local file
  file=$(_task_file "$slug")
  local status
  status=$(_find_task "$slug")

  _kv_out TASK_ID "$(_read_frontmatter "$file" 'task_id')"
  _kv_out SLUG    "$slug"
  _kv_out STATUS  "$status"
  _kv_out TITLE   "$(_read_frontmatter "$file" 'title')"
  _kv_out PRIORITY "$(_read_frontmatter "$file" 'priority')"
  _kv_out SIZE    "$(_read_frontmatter "$file" 'size')"
  _kv_out SOURCE  "$(_read_frontmatter "$file" 'source')"
  _kv_out SOURCE_REF "$(_read_frontmatter "$file" 'source_ref')"
  _kv_out GOAL    "$(_read_frontmatter "$file" 'goal')"
  _kv_out RECURRING "$(_read_frontmatter "$file" 'recurring')"
  _kv_out WAITING_ON "$(_read_frontmatter "$file" 'waiting_on')"
  _kv_out CREATED_AT "$(_read_frontmatter "$file" 'created_at')"
  _kv_out UPDATED_AT "$(_read_frontmatter "$file" 'updated_at')"
  _kv_out TRIAGE_SLACK_TS "$(_read_frontmatter "$file" 'triage_slack_ts')"

  # Extract instruction from body (first 5 non-empty lines)
  local instruction
  instruction=$(sed -n '/^## Instruction/,/^## /{/^## /!p}' "$file" | sed '/^$/d' | head -5)
  _kv_out INSTRUCTION "$instruction"
}

cmd_read_raw() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "Usage: task.sh read-raw <id|slug>" >&2; exit 1; }
  slug=$(_resolve_identifier "$slug") || exit 1

  local file
  file=$(_task_file "$slug")
  cat "$file"
}

cmd_update() {
  local slug="${1:-}" key="${2:-}" value="${3:-}"
  [[ -z "$slug" || -z "$key" ]] && { echo "Usage: task.sh update <id|slug> <key> <value>" >&2; exit 1; }
  slug=$(_resolve_identifier "$slug") || exit 1

  local file
  file=$(_task_file "$slug")
  _update_frontmatter "$file" "$key" "$value"
  _update_frontmatter "$file" "updated_at" "$(_now)"
}

cmd_move() {
  local slug="${1:-}" target="${2:-}"
  [[ -z "$slug" || -z "$target" ]] && { echo "Usage: task.sh move <id|slug> <status>" >&2; exit 1; }
  slug=$(_resolve_identifier "$slug") || exit 1

  local current
  current=$(_find_task "$slug") || { echo "Error: task '$slug' not found" >&2; exit 1; }

  if [[ "$current" == "$target" ]]; then
    return 0
  fi

  mkdir -p "$TASKS_DIR/$target"

  local src
  src=$(_task_file "$slug")
  local dst="$TASKS_DIR/$target/$(basename "$src")"

  mv "$src" "$dst"
  _update_frontmatter "$dst" "updated_at" "$(_now)"
}

cmd_list() {
  local status="${1:-}" sort_mode="" source_filter="" format="human"
  shift || true  # shift may fail if no args; handled by empty check below

  [[ -z "$status" ]] && { echo "Usage: task.sh list <status> [--sort priority] [--source SRC] [--format human|raw|slug-title]" >&2; exit 1; }

  local dir="$TASKS_DIR/$status"
  [[ ! -d "$dir" ]] && exit 0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sort)   sort_mode="$2";   shift 2 ;;
      --source) source_filter="$2"; shift 2 ;;
      --format) format="$2";      shift 2 ;;
      *) shift ;;
    esac
  done

  # Collect and optionally sort task files
  local files=()
  if [[ "$sort_mode" == "priority" ]]; then
    local entries="" base slug task_id priority created_at weight src
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      if [[ -n "$source_filter" ]]; then
        src=$(_read_frontmatter "$f" "source")
        [[ "$src" != "$source_filter" ]] && continue
      fi
      base=$(basename "$f" .md)
      slug=$(_slug_from_filename "$base")
      task_id=$(_id_from_filename "$base")
      priority=$(_read_frontmatter "$f" "priority")
      [[ -z "$priority" ]] && priority="medium"
      created_at=$(_read_frontmatter "$f" "created_at")
      weight=$(_priority_weight "$priority")
      entries="${entries}${weight} ${created_at} ${task_id} ${slug} ${f}\n"
    done
    if [[ -n "$entries" ]]; then
      while IFS=' ' read -r _ _ _ _ filepath; do
        files+=("$filepath")
      done < <(printf '%b' "$entries" | sort -t' ' -k1,1n -k2,2)
    fi
  else
    local src
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      if [[ -n "$source_filter" ]]; then
        src=$(_read_frontmatter "$f" "source")
        [[ "$src" != "$source_filter" ]] && continue
      fi
      files+=("$f")
    done
  fi

  # Output in requested format
  local first=true
  for f in "${files[@]}"; do
    local base task_id slug title
    base=$(basename "$f" .md)
    task_id=$(_id_from_filename "$base")
    slug=$(_slug_from_filename "$base")

    case "$format" in
      human)
        # Default: id slug
        echo "${task_id} ${slug}"
        ;;
      slug-title)
        # slug TAB title — for dedup checks in agents
        title=$(_strip_yaml_quotes "$(_read_frontmatter "$f" "title")")
        printf '%s\t%s\n' "$slug" "$title"
        ;;
      raw)
        # KEY="value" block per task, separated by ---
        [[ "$first" == "false" ]] && echo "---"
        first=false
        _kv_out TASK_ID  "$(_read_frontmatter "$f" 'task_id')"
        _kv_out SLUG     "$slug"
        _kv_out STATUS   "$status"
        _kv_out TITLE    "$(_read_frontmatter "$f" 'title')"
        _kv_out PRIORITY "$(_read_frontmatter "$f" 'priority')"
        _kv_out SIZE     "$(_read_frontmatter "$f" 'size')"
        _kv_out SOURCE   "$(_read_frontmatter "$f" 'source')"
        _kv_out SOURCE_REF "$(_read_frontmatter "$f" 'source_ref')"
        _kv_out WAITING_ON "$(_read_frontmatter "$f" 'waiting_on')"
        _kv_out CREATED_AT "$(_read_frontmatter "$f" 'created_at')"
        _kv_out UPDATED_AT "$(_read_frontmatter "$f" 'updated_at')"
        ;;
      *)
        echo "Unknown format: $format (use human|raw|slug-title)" >&2
        exit 1
        ;;
    esac
  done
}

cmd_find() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && { echo "Usage: task.sh find <id|slug>" >&2; exit 1; }
  slug=$(_resolve_identifier "$slug") || exit 1

  _find_task "$slug" || { echo "Error: task '$slug' not found" >&2; exit 1; }
}

cmd_note() {
  local slug="${1:-}" message="${2:-}"
  [[ -z "$slug" || -z "$message" ]] && { echo "Usage: task.sh note <id|slug> <message>" >&2; exit 1; }
  slug=$(_resolve_identifier "$slug") || exit 1

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

cmd_migrate() {
  local counter_file="$KVIDO_HOME/state/task_counter"
  local all_tasks=()

  # Collect all tasks without numeric prefix
  for status_dir in $STATUSES; do
    local dir="$TASKS_DIR/$status_dir"
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      # Skip already migrated files (have task_id in frontmatter)
      [[ -n "$(_read_frontmatter "$f" "task_id")" ]] && continue
      local created_at
      created_at=$(_read_frontmatter "$f" "created_at")
      all_tasks+=("${created_at:-0} $f")
    done
  done

  if [[ ${#all_tasks[@]} -eq 0 ]]; then
    echo "No tasks to migrate." >&2
    return 0
  fi

  # Sort by created_at and assign IDs
  local id=0
  [[ -f "$counter_file" ]] && id=$(cat "$counter_file")

  local sorted
  sorted=$(printf '%s\n' "${all_tasks[@]}" | sort -k1,1)

  while IFS=' ' read -r _ filepath; do
    id=$((id + 1))
    local dir_path base slug new_path
    dir_path=$(dirname "$filepath")
    base=$(basename "$filepath" .md)
    slug="$base"
    new_path="$dir_path/${id}-${slug}.md"
    mv "$filepath" "$new_path"
    _update_frontmatter "$new_path" "task_id" "$id"
    echo "Migrated: $slug → ${id}-${slug}" >&2
  done <<< "$sorted"

  local counter_tmp
  counter_tmp="$(_make_tmp "$counter_file")"
  echo "$id" > "$counter_tmp" && mv "$counter_tmp" "$counter_file"
  echo "Migrated ${#all_tasks[@]} tasks. Counter: $id" >&2
}

# --- Main ---

COMMAND="${1:-}"
shift || true  # shift may fail if no args; handled by case fallback below

case "$COMMAND" in
  --help|-h)
    cat <<'HELP'
kvido task — task queue management

Usage: kvido task <subcommand> [args...]

Subcommands:
  create --title "..." --instruction "..." [--priority urgent|high|medium|low]
         [--size s|m|l|xl] [--source SRC] [--source-ref REF] [--goal G]
  read <id|slug>              Print frontmatter fields as KEY="value" (consistently quoted)
  read-raw <id|slug>          Print raw markdown file
  update <id|slug> <field> <value>  Update a frontmatter field
  move <id|slug> <status>     Move task (triage|todo|in-progress|done|failed|cancelled)
  list <status> [--sort priority] [--source SRC] [--format human|raw|slug-title]  List tasks
  find <id|slug>              Print current status of task
  note <id|slug> "<text>"     Append text to ## Worker Notes
  count [status]              Count tasks, optionally filtered by status
  migrate-ids                 Assign numeric IDs to legacy tasks

Examples:
  kvido task create --title "Fix login" --instruction "Fix the login bug" --priority high
  kvido task list in-progress
  kvido task move 42 done
HELP
    ;;
  create)   cmd_create "$@" ;;
  read)     cmd_read "$@" ;;
  read-raw) cmd_read_raw "$@" ;;
  update)   cmd_update "$@" ;;
  move)     cmd_move "$@" ;;
  list)     cmd_list "$@" ;;
  find)     cmd_find "$@" ;;
  note)     cmd_note "$@" ;;
  count)       cmd_count "$@" ;;
  migrate-ids) cmd_migrate "$@" ;;
  *)
    echo "Usage: task.sh <create|read|read-raw|update|move|list|find|note|count|migrate-ids> [args...]" >&2
    echo "Run 'kvido task --help' for details." >&2
    exit 1
    ;;
esac
