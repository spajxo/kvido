# State CLI Wrappers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace direct `state/` file references in LLM instruction markdowns with `kvido` CLI wrapper commands.

**Architecture:** Three new bash scripts (`planner-state.sh`, `current.sh`, `source-health.sh`) following the `heartbeat-state.sh` pattern (jq + flock + atomic writes). The `kvido` dispatcher auto-resolves them by name. Instruction markdowns are then updated to use CLI commands instead of raw file paths.

**Tech Stack:** Bash, jq, flock, mktemp+mv atomic writes

**Spec:** `docs/superpowers/specs/2026-03-24-state-cli-wrappers-design.md`

**Reference implementation:** `plugins/kvido/skills/heartbeat/heartbeat-state.sh`

---

### Task 1: Create `planner-state.sh` — JSON skeleton and core helpers

**Files:**
- Create: `plugins/kvido/skills/planner-state/planner-state.sh`

- [ ] **Step 1: Create the script with header, env setup, and helper functions**

```bash
#!/usr/bin/env bash
# planner-state.sh — CRUD interface for state/planner-state.json
# Follows heartbeat-state.sh pattern: jq + flock + atomic writes.
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/planner-state.json"
LOCK_FILE="${STATE_FILE}.lock"
LOCK_TIMEOUT=10

EMPTY_SKELETON='{"last_run":{},"timestamps":{},"events":{},"reminders":{},"interests":{},"schedule":""}'

_ensure_file() {
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$EMPTY_SKELETON" > "$STATE_FILE"
  fi
}

_atomic_write() {
  local content="$1"
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  echo "$content" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

_locked_write() {
  local jq_filter="$1"
  shift
  (
    exec 200>"$LOCK_FILE"
    if ! flock -w "$LOCK_TIMEOUT" 200; then
      echo "planner-state.sh: timeout acquiring lock ($LOCK_TIMEOUT s)" >&2
      exit 1
    fi
    _ensure_file
    updated=$(jq "$@" "$jq_filter" "$STATE_FILE")
    _atomic_write "$updated"
  )
}
```

- [ ] **Step 2: Add the `reset` command and main case dispatch**

Append to the script:

```bash
CMD="${1:-}"
shift || true
SUB="${1:-}"

case "$CMD" in
  reset)
    mkdir -p "$(dirname "$STATE_FILE")"
    _atomic_write "$EMPTY_SKELETON"
    ;;
  *)
    echo "Usage: planner-state.sh <event|timestamp|reminder|schedule|interests|last-run|reset> [args...]" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 3: Make executable and verify reset works**

Run:
```bash
chmod +x plugins/kvido/skills/planner-state/planner-state.sh
KVIDO_HOME=/tmp/kvido-test bash plugins/kvido/skills/planner-state/planner-state.sh reset
cat /tmp/kvido-test/state/planner-state.json
```
Expected: JSON with empty skeleton keys.

- [ ] **Step 4: Commit**

```bash
git add plugins/kvido/skills/planner-state/planner-state.sh
git commit -m "feat: add planner-state.sh skeleton with reset command (#74)"
```

---

### Task 2: Add `planner-state event` subcommands

**Files:**
- Modify: `plugins/kvido/skills/planner-state/planner-state.sh`

- [ ] **Step 1: Add `event` case block before the `*` fallback**

Insert before `*)` in the case statement:

```bash
  event)
    shift || true
    ECMD="${1:-}"
    case "$ECMD" in
      check)
        key="${2:?Usage: planner-state.sh event check <key>}"
        _ensure_file
        jq -e --arg k "$key" '.events[$k] != null' "$STATE_FILE" >/dev/null 2>&1
        ;;
      report)
        key="${2:?Usage: planner-state.sh event report <key>}"
        now=$(date -Iseconds)
        _locked_write \
          '.events[$k] = if .events[$k] then .events[$k] | .last_reported = $now else {first_seen: $now, last_reported: $now} end' \
          --arg k "$key" --arg now "$now"
        ;;
      list)
        _ensure_file
        jq '.events' "$STATE_FILE"
        ;;
      cleanup)
        max_age="72h"
        shift || true
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --max-age) max_age="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        # Convert max_age to seconds
        hours="${max_age%h}"
        cutoff=$(date -Iseconds -d "-${hours} hours")
        _locked_write \
          '.events |= ([to_entries[] | select(.value.last_reported >= $cutoff)] | from_entries)' \
          --arg cutoff "$cutoff"
        ;;
      *)
        echo "Usage: planner-state.sh event <check|report|list|cleanup> [args...]" >&2
        exit 1
        ;;
    esac
    ;;
```

- [ ] **Step 2: Verify event subcommands**

Run:
```bash
export KVIDO_HOME=/tmp/kvido-test
PS=plugins/kvido/skills/planner-state/planner-state.sh
bash $PS reset
bash $PS event report "test:key:1"
bash $PS event check "test:key:1" && echo "EXISTS" || echo "MISSING"
bash $PS event check "nonexistent" && echo "EXISTS" || echo "MISSING"
bash $PS event list
bash $PS event report "test:key:1"  # update last_reported
bash $PS event list
```
Expected: EXISTS for test:key:1, MISSING for nonexistent, list shows JSON with updated last_reported.

- [ ] **Step 3: Commit**

```bash
git add plugins/kvido/skills/planner-state/planner-state.sh
git commit -m "feat: add planner-state event check/report/list/cleanup (#74)"
```

---

### Task 3: Add `planner-state timestamp`, `reminder`, `interests` subcommands

**Files:**
- Modify: `plugins/kvido/skills/planner-state/planner-state.sh`

- [ ] **Step 1: Add `timestamp` case block**

```bash
  timestamp)
    shift || true
    TCMD="${1:-}"
    case "$TCMD" in
      get)
        key="${2:?Usage: planner-state.sh timestamp get <key>}"
        _ensure_file
        val=$(jq -r --arg k "$key" '.timestamps[$k] // empty' "$STATE_FILE")
        [[ -z "$val" ]] && exit 1
        echo "$val"
        ;;
      set)
        key="${2:?Usage: planner-state.sh timestamp set <key> <value>}"
        value="${3:?Usage: planner-state.sh timestamp set <key> <value>}"
        _locked_write '.timestamps[$k] = $v' --arg k "$key" --arg v "$value"
        ;;
      *)
        echo "Usage: planner-state.sh timestamp <get|set> [args...]" >&2
        exit 1
        ;;
    esac
    ;;
```

- [ ] **Step 2: Add `reminder` case block**

```bash
  reminder)
    shift || true
    RCMD="${1:-}"
    case "$RCMD" in
      get)
        slug="${2:?Usage: planner-state.sh reminder get <slug>}"
        _ensure_file
        val=$(jq -r --arg k "$slug" '.reminders[$k].last_reminded // empty' "$STATE_FILE")
        [[ -z "$val" ]] && exit 1
        echo "$val"
        ;;
      set)
        slug="${2:?Usage: planner-state.sh reminder set <slug>}"
        today=$(date +%Y-%m-%d)
        _locked_write '.reminders[$k] = {last_reminded: $d}' --arg k "$slug" --arg d "$today"
        ;;
      *)
        echo "Usage: planner-state.sh reminder <get|set> [args...]" >&2
        exit 1
        ;;
    esac
    ;;
```

- [ ] **Step 3: Add `interests` case block**

```bash
  interests)
    shift || true
    ICMD="${1:-}"
    case "$ICMD" in
      get)
        topic="${2:?Usage: planner-state.sh interests get <topic>}"
        _ensure_file
        val=$(jq -r --arg k "$topic" '.interests[$k].last_checked // empty' "$STATE_FILE")
        [[ -z "$val" ]] && exit 1
        echo "$val"
        ;;
      set)
        topic="${2:?Usage: planner-state.sh interests set <topic>}"
        now=$(date -Iseconds)
        _locked_write '.interests[$k] = {last_checked: $now}' --arg k "$topic" --arg now "$now"
        ;;
      list)
        _ensure_file
        jq '.interests' "$STATE_FILE"
        ;;
      *)
        echo "Usage: planner-state.sh interests <get|set|list> [args...]" >&2
        exit 1
        ;;
    esac
    ;;
```

- [ ] **Step 4: Verify all three**

Run:
```bash
export KVIDO_HOME=/tmp/kvido-test
PS=plugins/kvido/skills/planner-state/planner-state.sh
bash $PS reset
bash $PS timestamp set last_morning_check 2026-03-24
bash $PS timestamp get last_morning_check
bash $PS reminder set "#13"
bash $PS reminder get "#13"
bash $PS interests set ai-agents
bash $PS interests get ai-agents
bash $PS interests list
```
Expected: Each get returns the set value. interests list returns JSON object.

- [ ] **Step 5: Commit**

```bash
git add plugins/kvido/skills/planner-state/planner-state.sh
git commit -m "feat: add planner-state timestamp/reminder/interests (#74)"
```

---

### Task 4: Add `planner-state schedule` and `last-run` subcommands

**Files:**
- Modify: `plugins/kvido/skills/planner-state/planner-state.sh`

- [ ] **Step 1: Add `schedule` case block**

```bash
  schedule)
    shift || true
    SCMD="${1:-}"
    case "$SCMD" in
      get)
        _ensure_file
        jq -r '.schedule // empty' "$STATE_FILE"
        ;;
      set)
        text=$(cat)
        _locked_write '.schedule = $v' --arg v "$text"
        ;;
      *)
        echo "Usage: planner-state.sh schedule <get|set>" >&2
        exit 1
        ;;
    esac
    ;;
```

- [ ] **Step 2: Add `last-run` case block**

```bash
  last-run)
    shift || true
    LCMD="${1:-}"
    case "$LCMD" in
      get)
        _ensure_file
        jq '.last_run' "$STATE_FILE"
        ;;
      set)
        json=$(cat)
        _locked_write '.last_run = $v' --argjson v "$json"
        ;;
      *)
        echo "Usage: planner-state.sh last-run <get|set>" >&2
        exit 1
        ;;
    esac
    ;;
```

- [ ] **Step 3: Verify**

Run:
```bash
export KVIDO_HOME=/tmp/kvido-test
PS=plugins/kvido/skills/planner-state/planner-state.sh
echo "- 11:00 -- Meeting" | bash $PS schedule set
bash $PS schedule get
echo '{"timestamp":"2026-03-24T12:00:00+01:00","sources_checked":["gitlab"],"tasks_created":0,"notifications_sent":1,"triage_processed":0}' | bash $PS last-run set
bash $PS last-run get
```
Expected: schedule get returns the text, last-run get returns the JSON.

- [ ] **Step 4: Commit**

```bash
git add plugins/kvido/skills/planner-state/planner-state.sh
git commit -m "feat: add planner-state schedule and last-run (#74)"
```

---

### Task 5: Create `current.sh`

**Files:**
- Create: `plugins/kvido/skills/current/current.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# current.sh — read/write state/current.md (atomic writes)
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/current.md"

case "${1:-}" in
  get)
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE"
    ;;
  set)
    mkdir -p "$(dirname "$STATE_FILE")"
    tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
    cat > "$tmp"
    mv "$tmp" "$STATE_FILE"
    ;;
  *)
    echo "Usage: current.sh <get|set>" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make executable and verify**

Run:
```bash
chmod +x plugins/kvido/skills/current/current.sh
export KVIDO_HOME=/tmp/kvido-test
echo "# Test Focus" | bash plugins/kvido/skills/current/current.sh set
bash plugins/kvido/skills/current/current.sh get
```
Expected: Prints `# Test Focus`.

- [ ] **Step 3: Commit**

```bash
git add plugins/kvido/skills/current/current.sh
git commit -m "feat: add current.sh for state/current.md access (#74)"
```

---

### Task 6: Create `source-health.sh`

**Files:**
- Create: `plugins/kvido/skills/source-health/source-health.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# source-health.sh — read/write state/source-health.json
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/source-health.json"
LOCK_FILE="${STATE_FILE}.lock"
LOCK_TIMEOUT=10

_ensure_file() {
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    echo '{}' > "$STATE_FILE"
  fi
}

_atomic_write() {
  local content="$1"
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  echo "$content" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

case "${1:-}" in
  get)
    _ensure_file
    source="${2:-}"
    if [[ -z "$source" ]]; then
      cat "$STATE_FILE"
    else
      jq -r --arg k "$source" '.[$k].status // empty' "$STATE_FILE"
    fi
    ;;
  set)
    source="${2:?Usage: source-health.sh set <source> <status>}"
    status="${3:?Usage: source-health.sh set <source> <status>}"
    now=$(date -Iseconds)
    (
      exec 200>"$LOCK_FILE"
      if ! flock -w "$LOCK_TIMEOUT" 200; then
        echo "source-health.sh: timeout acquiring lock" >&2
        exit 1
      fi
      _ensure_file
      updated=$(jq --arg k "$source" --arg s "$status" --arg t "$now" \
        '.[$k] = {status: $s, timestamp: $t}' "$STATE_FILE")
      _atomic_write "$updated"
    )
    ;;
  *)
    echo "Usage: source-health.sh <get|set> [args...]" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make executable and verify**

Run:
```bash
chmod +x plugins/kvido/skills/source-health/source-health.sh
export KVIDO_HOME=/tmp/kvido-test
bash plugins/kvido/skills/source-health/source-health.sh set gitlab OK
bash plugins/kvido/skills/source-health/source-health.sh set gmail "FAIL: auth error"
bash plugins/kvido/skills/source-health/source-health.sh get
bash plugins/kvido/skills/source-health/source-health.sh get gitlab
```
Expected: Full JSON shows both entries with timestamp; single get returns `OK`.

- [ ] **Step 3: Commit**

```bash
git add plugins/kvido/skills/source-health/source-health.sh
git commit -m "feat: add source-health.sh for state/source-health.json access (#74)"
```

---

### Task 7: Register new commands in `kvido` dispatcher

**Files:**
- Modify: `plugins/kvido/kvido:104-155` (help text)
- Modify: `plugins/kvido/kvido:194-218` (auto-resolve case)

The dispatcher already auto-resolves commands via `skills/<name>/<name>.sh` pattern (line 201). The new scripts follow this convention:
- `skills/planner-state/planner-state.sh` → `kvido planner-state ...`
- `skills/current/current.sh` → `kvido current ...`
- `skills/source-health/source-health.sh` → `kvido source-health ...`

- [ ] **Step 1: Verify auto-resolution works without dispatcher changes**

Run:
```bash
export KVIDO_HOME=/tmp/kvido-test
# Test from the plugin root context
CLAUDE_PLUGIN_ROOT=$(pwd)/plugins/kvido bash plugins/kvido/kvido planner-state reset
CLAUDE_PLUGIN_ROOT=$(pwd)/plugins/kvido bash plugins/kvido/kvido planner-state timestamp set test_key 2026-03-24
CLAUDE_PLUGIN_ROOT=$(pwd)/plugins/kvido bash plugins/kvido/kvido planner-state timestamp get test_key
echo "# Focus test" | CLAUDE_PLUGIN_ROOT=$(pwd)/plugins/kvido bash plugins/kvido/kvido current set
CLAUDE_PLUGIN_ROOT=$(pwd)/plugins/kvido bash plugins/kvido/kvido current get
CLAUDE_PLUGIN_ROOT=$(pwd)/plugins/kvido bash plugins/kvido/kvido source-health set gitlab OK
CLAUDE_PLUGIN_ROOT=$(pwd)/plugins/kvido bash plugins/kvido/kvido source-health get gitlab
```
Expected: All commands resolve and work correctly via the auto-resolve mechanism.

- [ ] **Step 2: Update `kvido --help` text**

Add new commands to the help text after the `slack` line (around line 121). Add:

```
  current <get|set>                 Read/write current focus (state/current.md)
  planner-state <subcommand>        Planner state (events, timestamps, reminders, schedule, interests)
  source-health <get|set> [args]    Source health status
```

Also add a new subcommand help section after the existing ones:

```
Planner-state subcommands:
  event check <key>               Check if event was reported (exit 0/1)
  event report <key>              Report event (upsert first_seen/last_reported)
  event list                      List all events as JSON
  event cleanup [--max-age 72h]   Remove events older than threshold
  timestamp get <key>             Get timestamp value
  timestamp set <key> <value>     Set timestamp value
  reminder get <slug>             Get last_reminded date
  reminder set <slug>             Set last_reminded to today
  schedule get                    Print today's schedule
  schedule set                    Read schedule from stdin
  interests get <topic>           Get last_checked for topic
  interests set <topic>           Set last_checked to now
  interests list                  List all interest topics as JSON
  last-run get                    Print last run metadata as JSON
  last-run set                    Read last run JSON from stdin
  reset                           Reset to empty skeleton
```

- [ ] **Step 3: Commit**

```bash
git add plugins/kvido/kvido
git commit -m "feat: add new state commands to kvido --help (#74)"
```

---

### Task 8: Add `--source` filter to `kvido task list`

**Files:**
- Modify: `plugins/kvido/skills/worker/task.sh:261-299` (`cmd_list` function)

- [ ] **Step 1: Add `--source` flag parsing to `cmd_list`**

In `cmd_list`, add `source_filter=""` alongside `sort_mode=""`, parse `--source` in the while loop, then filter by reading the `source` frontmatter field:

```bash
cmd_list() {
  local status="${1:-}" sort_mode="" source_filter=""
  shift || true

  [[ -z "$status" ]] && { echo "Usage: task.sh list <status> [--sort priority] [--source SRC]" >&2; exit 1; }

  local dir="$TASKS_DIR/$status"
  [[ ! -d "$dir" ]] && exit 0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sort) sort_mode="$2"; shift 2 ;;
      --source) source_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ "$sort_mode" == "priority" ]]; then
    local entries="" slug priority created_at weight src
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      slug=$(basename "$f" .md)
      if [[ -n "$source_filter" ]]; then
        src=$(_read_frontmatter "$f" "source")
        [[ "$src" != "$source_filter" ]] && continue
      fi
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
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      if [[ -n "$source_filter" ]]; then
        local src
        src=$(_read_frontmatter "$f" "source")
        [[ "$src" != "$source_filter" ]] && continue
      fi
      basename "$f" .md
    done
  fi
}
```

- [ ] **Step 2: Verify the filter works**

Run:
```bash
export KVIDO_HOME=/tmp/kvido-test
TS=plugins/kvido/skills/worker/task.sh
bash $TS create --title "Test planner task" --instruction "test" --source planner --status todo
bash $TS create --title "Test manual task" --instruction "test" --source manual --status todo
bash $TS list todo
bash $TS list todo --source planner
bash $TS list todo --source manual
```
Expected: Full list shows both, filtered lists show one each.

- [ ] **Step 3: Update help text in task.sh**

Update the usage comment at top of file — change `list` line to:
```
#   list     <status> [--sort priority] [--source SRC]  # list slugs
```

- [ ] **Step 4: Commit**

```bash
git add plugins/kvido/skills/worker/task.sh
git commit -m "feat: add --source filter to kvido task list (#74)"
```

---

### Task 9: Create migration script for `planner-state.md` → JSON

**Files:**
- Create: `plugins/kvido/skills/planner-state/migrate.sh`

- [ ] **Step 1: Write the migration script**

```bash
#!/usr/bin/env bash
# migrate.sh — one-time migration: state/planner-state.md → state/planner-state.json
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
MD_FILE="${KVIDO_HOME}/state/planner-state.md"
JSON_FILE="${KVIDO_HOME}/state/planner-state.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$MD_FILE" ]]; then
  echo "No planner-state.md found — nothing to migrate." >&2
  exit 0
fi

if [[ -f "$JSON_FILE" ]]; then
  echo "planner-state.json already exists — skipping migration." >&2
  exit 0
fi

echo "Migrating planner-state.md → planner-state.json ..." >&2

# Initialize with reset
bash "$SCRIPT_DIR/planner-state.sh" reset

# Parse timestamps section
while IFS= read -r line; do
  if [[ "$line" =~ ^-\ ([a-z_]+):\ (.+)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    bash "$SCRIPT_DIR/planner-state.sh" timestamp set "$key" "$val"
  fi
done < <(sed -n '/^## Timestamps$/,/^## /{ /^## /d; /^$/d; p; }' "$MD_FILE")

# Parse reported events
while IFS= read -r line; do
  if [[ "$line" =~ ^-\ ([^|]+)\|\ first_seen:\ ([^|]+)\|\ last_reported:\ (.+)$ ]]; then
    key=$(echo "${BASH_REMATCH[1]}" | xargs)
    first=$(echo "${BASH_REMATCH[2]}" | xargs)
    last=$(echo "${BASH_REMATCH[3]}" | xargs)
    # Direct jq write for preserving original timestamps
    (
      exec 200>"${JSON_FILE}.lock"
      flock -w 10 200
      updated=$(jq --arg k "$key" --arg f "$first" --arg l "$last" \
        '.events[$k] = {first_seen: $f, last_reported: $l}' "$JSON_FILE")
      tmp="$(mktemp "${JSON_FILE}.tmp.XXXXXX")"
      echo "$updated" > "$tmp"
      mv "$tmp" "$JSON_FILE"
    )
  fi
done < <(sed -n '/^## Reported Events$/,/^## /{ /^## /d; /^$/d; p; }' "$MD_FILE")

# Parse user task reminders
while IFS= read -r line; do
  if [[ "$line" =~ ^-\ ([^:]+):\ last_reminded=(.+)$ ]]; then
    slug=$(echo "${BASH_REMATCH[1]}" | xargs)
    date_val=$(echo "${BASH_REMATCH[2]}" | xargs)
    if [[ "$date_val" != "not-yet" ]]; then
      (
        exec 200>"${JSON_FILE}.lock"
        flock -w 10 200
        updated=$(jq --arg k "$slug" --arg d "$date_val" \
          '.reminders[$k] = {last_reminded: $d}' "$JSON_FILE")
        tmp="$(mktemp "${JSON_FILE}.tmp.XXXXXX")"
        echo "$updated" > "$tmp"
        mv "$tmp" "$JSON_FILE"
      )
    fi
  fi
done < <(sed -n '/^## User Task Reminders$/,/^## /{ /^## /d; /^$/d; p; }' "$MD_FILE")

# Parse today's schedule
schedule=$(sed -n '/^## Today'\''s Schedule$/,/^## /{ /^## /d; /^$/d; p; }' "$MD_FILE")
if [[ -n "$schedule" ]]; then
  echo "$schedule" | bash "$SCRIPT_DIR/planner-state.sh" schedule set
fi

# Backup old file
mv "$MD_FILE" "${MD_FILE}.bak"

echo "Migration complete. Backup: ${MD_FILE}.bak" >&2
echo "Verify: cat $JSON_FILE | jq ." >&2
```

- [ ] **Step 2: Make executable and test with a copy of live data**

Run:
```bash
chmod +x plugins/kvido/skills/planner-state/migrate.sh
export KVIDO_HOME=/tmp/kvido-migrate-test
mkdir -p "$KVIDO_HOME/state"
cp ~/.config/kvido/state/planner-state.md "$KVIDO_HOME/state/"
bash plugins/kvido/skills/planner-state/migrate.sh
jq . "$KVIDO_HOME/state/planner-state.json"
```
Expected: JSON with populated events, timestamps, reminders, and schedule from live data.

- [ ] **Step 3: Commit**

```bash
git add plugins/kvido/skills/planner-state/migrate.sh
git commit -m "feat: add planner-state.md to JSON migration script (#74)"
```

---

### Task 10: Migrate instruction markdowns — planner agent and skill

**Files:**
- Modify: `plugins/kvido/agents/planner.md`
- Modify: `plugins/kvido/skills/planner/SKILL.md`

- [ ] **Step 1: Update `agents/planner.md`**

Replace line 20 (`3. Read state/planner-state.md for context from the previous run (if it exists).`) with:
```
3. Load planner state: `kvido planner-state last-run get` and `kvido planner-state event list` for context from the previous run.
```

Remove line referencing `state/current.md` — replace with:
```
Read current focus via `kvido current get`.
```

Remove any `state/session-context.md` reference (already injected via context).

- [ ] **Step 2: Update `skills/planner/SKILL.md` Step 1 (Load Context)**

Replace raw file reads with CLI commands:
- `state/planner-state.md` → `kvido planner-state last-run get`, `kvido planner-state event list`, `kvido planner-state timestamp get <key>`
- `state/current.md` → `kvido current get`
- Remove `state/session-context.md` line (injected via context)

- [ ] **Step 3: Update `skills/planner/SKILL.md` Step 2 (Scheduled Tasks)**

Replace `planner-state.md` checks with:
- Check: `kvido planner-state timestamp get last_morning_check` (exit 1 = not done today)
- Write: `kvido planner-state timestamp set last_morning_check $(date +%Y-%m-%d)`

- [ ] **Step 4: Update `skills/planner/SKILL.md` Step 4 (Change Detection)**

Replace `planner-state.md "## Reported Events"` with:
- Check: `kvido planner-state event check <event_key>` (exit 0 = skip, exit 1 = new)
- Report: `kvido planner-state event report <event_key>`

- [ ] **Step 5: Update `skills/planner/SKILL.md` Step 6b (User Context)**

Replace `state/current.md` with `kvido current get`.
Replace reminder tracking with:
- Check: `kvido planner-state reminder get <slug>` (exit 1 = never reminded)
- Set: `kvido planner-state reminder set <slug>`

- [ ] **Step 6: Update `skills/planner/SKILL.md` Step 7 (Maintenance)**

Replace `last_*_date` timestamps in planner-state.md with:
- Check: `kvido planner-state timestamp get <key>`
- Set: `kvido planner-state timestamp set <key> <value>`

- [ ] **Step 7: Update `skills/planner/SKILL.md` Step 8 (Save State)**

Replace "Update planner-state.md" with CLI commands:
```
kvido planner-state last-run set <<< '{"timestamp":"...","sources_checked":[...],...}'
kvido planner-state event cleanup
```

- [ ] **Step 8: Commit**

```bash
git add plugins/kvido/agents/planner.md plugins/kvido/skills/planner/SKILL.md
git commit -m "refactor: migrate planner to kvido CLI state commands (#74)"
```

---

### Task 11: Migrate instruction markdowns — heartbeat and hooks

**Files:**
- Modify: `plugins/kvido/commands/heartbeat.md`
- Modify: `plugins/kvido/hooks/context-session.md`
- Modify: `plugins/kvido/hooks/context-planner.md`
- Modify: `plugins/kvido/hooks/context-setup.md`

- [ ] **Step 1: Read all four files**

Read each file to understand exact references to replace.

- [ ] **Step 2: Update `commands/heartbeat.md`**

Replace:
- `state/current.md` → `kvido current get`
- `state/planner-state.md` → `kvido planner-state` subcommands
- `state/session-context.md` → remove (injected via context)
- `state/heartbeat-state.json` references should already use `kvido heartbeat-state`; fix any that don't

- [ ] **Step 3: Update `hooks/context-session.md`**

In the "Context Loading" section, replace raw file paths:
- `state/current.md` → `kvido current get`
- `state/session-context.md` → remove (auto-injected)
- `state/heartbeat-state.json` → `kvido heartbeat-state get-json`

Keep `memory/memory.md` as-is (memory system is separate scope).

- [ ] **Step 4: Update `hooks/context-planner.md`**

Replace `planner-state.md` references with `kvido planner-state` subcommands.

- [ ] **Step 5: Update `hooks/context-setup.md`**

Replace `state/tasks/{...}` validation with CLI-based checks.

- [ ] **Step 6: Commit**

```bash
git add plugins/kvido/commands/heartbeat.md plugins/kvido/hooks/context-session.md plugins/kvido/hooks/context-planner.md plugins/kvido/hooks/context-setup.md
git commit -m "refactor: migrate heartbeat and hooks to kvido CLI state commands (#74)"
```

---

### Task 12: Migrate instruction markdowns — remaining skills and agents

**Files:**
- Modify: `plugins/kvido/skills/interests/SKILL.md`
- Modify: `plugins/kvido/skills/daily-questions/SKILL.md`
- Modify: `plugins/kvido/skills/worker/SKILL.md`
- Modify: `plugins/kvido/skills/triage/SKILL.md`
- Modify: `plugins/kvido/agents/self-improver.md`
- Modify: `plugins/kvido/agents/project-enricher.md`

- [ ] **Step 1: Read all files to understand exact references**

- [ ] **Step 2: Update `skills/interests/SKILL.md`**

Replace `state/interests.md` with `kvido planner-state interests` subcommands.

- [ ] **Step 3: Update `skills/daily-questions/SKILL.md`**

Replace `state/current.md` → `kvido current get`.

- [ ] **Step 4: Update `skills/worker/SKILL.md`**

Replace `state/tasks/` paths → `kvido task` commands. Replace `state/current.md` → `kvido current get`.

- [ ] **Step 5: Update `skills/triage/SKILL.md`**

Replace `state/tasks/triage/` → `kvido task list triage`.

- [ ] **Step 6: Update `agents/self-improver.md`**

Replace `state/tasks/*.md` glob patterns → `kvido task list <status> --source <source>`. Keep `state/plugin-proposals/` as-is (deferred).

- [ ] **Step 7: Update `agents/project-enricher.md`**

Replace `state/heartbeat-state.json` → `kvido heartbeat-state get last_enriched_project`.

- [ ] **Step 8: Commit**

```bash
git add plugins/kvido/skills/interests/SKILL.md plugins/kvido/skills/daily-questions/SKILL.md \
  plugins/kvido/skills/worker/SKILL.md plugins/kvido/skills/triage/SKILL.md \
  plugins/kvido/agents/self-improver.md plugins/kvido/agents/project-enricher.md
git commit -m "refactor: migrate remaining skills and agents to kvido CLI state commands (#74)"
```

---

### Task 13: Migrate source plugin instructions

**Files:**
- Modify: `plugins/kvido-calendar/skills/source-calendar/SKILL.md`
- Modify: `plugins/kvido-gmail/skills/source-gmail/SKILL.md`
- Modify: `plugins/kvido-jira/skills/source-jira/SKILL.md`
- Modify: `plugins/kvido-gitlab/hooks/context-planner.md`

- [ ] **Step 1: Read all four files**

- [ ] **Step 2: Update `kvido-calendar` SKILL.md**

Replace `state/planner-state.md` schedule section with:
```bash
kvido planner-state schedule get   # read current
kvido planner-state schedule set   # write new (pipe from stdin)
```

- [ ] **Step 3: Update `kvido-gmail` SKILL.md**

Replace `state/source-health.json` with `kvido source-health set gmail <status>`.

- [ ] **Step 4: Update `kvido-jira` SKILL.md**

Replace `state/tasks/*/` references with `kvido task list`.

- [ ] **Step 5: Update `kvido-gitlab` context-planner.md**

Replace `state/tasks/` references with `kvido task` commands.

- [ ] **Step 6: Commit**

```bash
git add plugins/kvido-calendar/skills/source-calendar/SKILL.md \
  plugins/kvido-gmail/skills/source-gmail/SKILL.md \
  plugins/kvido-jira/skills/source-jira/SKILL.md \
  plugins/kvido-gitlab/hooks/context-planner.md
git commit -m "refactor: migrate source plugins to kvido CLI state commands (#74)"
```

---

### Task 14: Update setup validation and help

**Files:**
- Modify: `plugins/kvido/commands/setup.md`
- Modify: `plugins/kvido/kvido` (help text already done in Task 7)

- [ ] **Step 1: Read `commands/setup.md`**

- [ ] **Step 2: Update setup validation**

Add checks for:
- `kvido planner-state last-run get` (or create if missing)
- Migration detection: if `state/planner-state.md` exists but `state/planner-state.json` does not → run `kvido skills/planner-state/migrate.sh`
- `kvido source-health get` (ensure file exists)

- [ ] **Step 3: Commit**

```bash
git add plugins/kvido/commands/setup.md
git commit -m "refactor: update setup to validate new state CLI wrappers (#74)"
```

---

### Task 15: Post-migration verification

- [ ] **Step 1: Grep for remaining raw `state/` paths in instruction markdowns**

Run:
```bash
grep -rn 'state/' plugins/kvido/agents/*.md plugins/kvido/skills/*/SKILL.md \
  plugins/kvido/commands/*.md plugins/kvido/hooks/context-*.md \
  plugins/kvido-*/skills/*/SKILL.md plugins/kvido-*/hooks/*.md 2>/dev/null \
  | grep -v 'kvido task\|kvido heartbeat-state\|kvido log\|kvido current\|kvido planner-state\|kvido source-health\|state/plugin-proposals\|state/ —\|`state/`' \
  || echo "CLEAN: No raw state/ paths found in instruction markdowns"
```
Expected: `CLEAN` or only `state/plugin-proposals/` references (deferred).

- [ ] **Step 2: Run live migration on user's kvido instance**

This is destructive — confirm with user before running:
```bash
bash plugins/kvido/skills/planner-state/migrate.sh
```

- [ ] **Step 3: Verify live instance works**

```bash
kvido planner-state last-run get
kvido planner-state event list | jq 'length'
kvido planner-state timestamp get last_morning_check
kvido current get | head -3
kvido source-health get
```
Expected: All return data from migrated state.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: post-migration cleanup (#74)"
```
