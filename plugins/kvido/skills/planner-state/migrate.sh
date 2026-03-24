#!/usr/bin/env bash
# migrate.sh — one-time migration: state/planner-state.md → state/planner-state.json
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
MD_FILE="${KVIDO_HOME}/state/planner-state.md"
JSON_FILE="${KVIDO_HOME}/state/planner-state.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOCK_FILE="${JSON_FILE}.lock"
LOCK_TIMEOUT=10

if [[ ! -f "$MD_FILE" ]]; then
  echo "No planner-state.md found — nothing to migrate." >&2
  exit 0
fi

if [[ -f "$JSON_FILE" ]]; then
  echo "planner-state.json already exists — skipping migration." >&2
  exit 0
fi

echo "Migrating planner-state.md → planner-state.json ..." >&2

# Initialize empty JSON structure
bash "$SCRIPT_DIR/planner-state.sh" reset

# Helper: extract a section's lines from the markdown file.
# Prints lines between "## Section" and the next "## " heading,
# stripping blank lines and HTML comments.
_section() {
  local heading="$1"
  sed -n "/^## ${heading}$/,/^## /{/^## /d; /^[[:space:]]*$/d; /^<!--/d; p;}" "$MD_FILE"
}

# Helper: flock + atomic jq write (same pattern as planner-state.sh)
_locked_write() {
  local jq_filter="$1"
  shift
  (
    exec 200>"$LOCK_FILE"
    if ! flock -w "$LOCK_TIMEOUT" 200; then
      echo "migrate.sh: timeout acquiring lock ($LOCK_TIMEOUT s)" >&2
      exit 1
    fi
    updated=$(jq "$@" "$jq_filter" "$JSON_FILE")
    local tmp
    tmp="$(mktemp "${JSON_FILE}.tmp.XXXXXX")"
    echo "$updated" > "$tmp"
    mv "$tmp" "$JSON_FILE"
  )
}

# --- Timestamps section ---
# Lines: "- key: value"
while IFS= read -r line; do
  # Strip leading "- "
  kv="${line#- }"
  key="${kv%%:*}"
  value="${kv#*: }"
  key="$(echo "$key" | xargs)"
  value="$(echo "$value" | xargs)"
  [[ -z "$key" || -z "$value" ]] && continue
  bash "$SCRIPT_DIR/planner-state.sh" timestamp set "$key" "$value"
done < <(_section "Timestamps")

# --- Reported Events section ---
# Lines: "- event_key | first_seen: ts | last_reported: ts"
while IFS= read -r line; do
  # Strip leading "- "
  line="${line#- }"
  # Split on " | "
  IFS='|' read -r raw_key raw_first raw_last <<< "$line"
  key="$(echo "$raw_key" | xargs)"
  first_seen="$(echo "$raw_first" | sed 's/first_seen:[[:space:]]*//' | xargs)"
  last_reported="$(echo "$raw_last" | sed 's/last_reported:[[:space:]]*//' | xargs)"
  [[ -z "$key" || -z "$first_seen" || -z "$last_reported" ]] && continue
  _locked_write \
    '.events[$k] = {"first_seen": $fs, "last_reported": $lr}' \
    --arg k "$key" \
    --arg fs "$first_seen" \
    --arg lr "$last_reported"
done < <(_section "Reported Events")

# --- User Task Reminders section ---
# Lines: "- slug: last_reminded=date (extra text)"
# Skip lines where date is "not-yet"
while IFS= read -r line; do
  # Strip leading "- "
  line="${line#- }"
  slug="${line%%:*}"
  slug="$(echo "$slug" | xargs)"
  rest="${line#*: }"
  # Extract the value after "last_reminded="
  reminded_raw="${rest#last_reminded=}"
  # Take only the date part (stop before space or '(')
  date_val="${reminded_raw%%[ (]*}"
  date_val="$(echo "$date_val" | xargs)"
  [[ -z "$slug" || -z "$date_val" ]] && continue
  [[ "$date_val" == "not-yet" ]] && continue
  _locked_write \
    '.reminders[$s].last_reminded = $d' \
    --arg s "$slug" \
    --arg d "$date_val"
done < <(_section "User Task Reminders")

# --- Today's Schedule section ---
# Pipe entire section as a single string to "schedule set"
schedule_content="$(_section "Today's Schedule")"
if [[ -n "$schedule_content" ]]; then
  echo "$schedule_content" | bash "$SCRIPT_DIR/planner-state.sh" schedule set
fi

# --- Rename old file ---
mv "$MD_FILE" "${MD_FILE}.bak"
echo "Migration complete. Backup: ${MD_FILE}.bak" >&2
