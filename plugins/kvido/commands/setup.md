---
description: Setup & self-healing — first-time onboarding, structure bootstrap, health check
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent
---

# Kvido Setup

Setup and self-healing command. Run on first launch, after plugin installation, or when something is broken.

## Step 0: Prerequisites

### KVIDO_HOME

```bash
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
mkdir -p "$KVIDO_HOME"
```

All state, memory, config, and .env files live in `$KVIDO_HOME` (default: `~/.config/kvido`).

### kvido CLI

Install or refresh the `kvido` CLI wrapper in `~/.local/bin/`:

```bash
# Prefer CLAUDE_PLUGIN_ROOT (set by Claude Code in plugin context)
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  KVIDO_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  KVIDO_ROOT=$(jq -r '.plugins | to_entries[] | select(.key | startswith("kvido@")) | .value[0].installPath' ~/.claude/plugins/installed_plugins.json 2>/dev/null | head -1)
fi
bash "$KVIDO_ROOT/kvido" --install
```

This always refreshes `~/.local/bin/kvido` to a wrapper that prefers `CLAUDE_PLUGIN_ROOT` at runtime and falls back to the registry for standalone shell invocations.

Verify `~/.local/bin` is in PATH. If not, inform the user.

### Required tools

```bash
for cmd in jq kvido; do
  if command -v "$cmd" &>/dev/null; then
    echo "OK: $cmd $(command -v $cmd)"
  else
    echo "MISSING: $cmd — required"
  fi
done
```

If a required tool is missing, inform the user and offer installation. Do not proceed until required prerequisites are met.

### Source plugins

Run `kvido discover-sources` to list installed source plugins.

Load setup requirements:
```bash
kvido context setup
```

The assembled context lists prerequisites (binaries, env vars, MCP services) and required config keys for each installed plugin. Validate each.

For each not-installed plugin, check if prerequisites are available and suggest installation:
```
claude plugin install kvido-gitlab
```

Skip this step if this is a re-run and all desired sources are already installed.

## Step 1: First-time Setup

Detection: `$KVIDO_HOME/settings.json` does not exist OR `$KVIDO_HOME/memory/persona.md` does not exist → run first-time setup.
If both exist, skip to Step 2.

### a) Config files

If files don't exist, create them:
- `$KVIDO_HOME/settings.json` — copy `settings.json.example` from the plugin
- `$KVIDO_HOME/.env` — create with empty values (these are the secrets referenced from settings.json):
  ```
  SLACK_BOT_TOKEN=
  SLACK_DM_CHANNEL_ID=
  SLACK_USER_ID=
  SLACK_USER_NAME=
  ```

`settings.json` references these env vars using `"$ENV_VAR"` syntax (e.g. `"slack.bot_token": "$SLACK_BOT_TOKEN"`).
`kvido config` resolves the references automatically from `.env`.

### b) Persona setup

If `$KVIDO_HOME/memory/persona.md` does not exist:
1. Ask the user:
   - "What language should Kvido use? (default: en)"
   - "What's your assistant's name? What tone and personality should it have? (e.g. brief and factual, friendly, formal...)"
2. From the answers, create `memory/persona.md` with the appropriate structure (name, language, tone, personality, URL formats). Store language as `language: en` (or the chosen language code).
3. Also create the `memory/` directory if it doesn't exist.

### c) Slack credentials (settings.json + .env)

Check that Slack credentials resolve correctly:
```bash
kvido config 'slack.bot_token'
kvido config 'slack.dm_channel_id'
```
If these return empty or fail:
1. Explain the two-file approach: secrets live in `.env`, settings.json references them with `"$VAR_NAME"` syntax
2. Help the user fill in `.env` with actual token and channel values
3. Confirm that `settings.json` has the `"$SLACK_BOT_TOKEN"` references (default from `settings.json.example`)

### d) Source plugin config validation

For each installed source plugin (via `kvido discover-sources`), verify that `settings.json` contains the required config keys. Use `kvido config` to check.

The assembled context from `kvido context setup` (loaded in Step 0) lists required config keys per plugin. Validate each using `kvido config`.

For each missing config:
1. Show which keys are missing and what they configure
2. Offer to help fill them in (show examples from `settings.json.example`)
3. If the user provides values, update the corresponding keys in `settings.json`

Skip this step for plugins that are not installed.


## Step 2: Structure Bootstrap

Create missing directories:

```bash
mkdir -p $KVIDO_HOME/memory/{journal,weekly,projects,people,decisions,archive/{journal,weekly,decisions}}
mkdir -p $KVIDO_HOME/state/tasks/{triage,todo,in-progress,done,failed,cancelled}
```

For each missing file, create with minimal content:
- `$KVIDO_HOME/memory/memory.md` → `# Memory` + sections (Who I am, Active projects, Key decisions, Lessons learned, People)
- `$KVIDO_HOME/memory/this-week.md` → `# Week YYYY-Www`
- `$KVIDO_HOME/memory/learnings.md` → `# Learnings`
- `$KVIDO_HOME/memory/errors.md` → `# Errors`
- `$KVIDO_HOME/memory/people/_index.md` → `# People`
- `$KVIDO_HOME/memory/decisions/_index.md` → `# Decisions`
- `$KVIDO_HOME/state/heartbeat-state.json` → default schema (iteration_count: 0, all timestamps null, last_chat_ts: "0", cron_job_id: "", active_preset: "10m", last_interaction_ts: null)

### State CLI wrappers validation

#### planner-state migration

Check if the legacy markdown file exists without its replacement JSON file — this means migration has not run yet:

```bash
if [[ -f "$KVIDO_HOME/state/planner-state.md" && ! -f "$KVIDO_HOME/state/planner-state.json" ]]; then
  echo "planner-state.md found without planner-state.json — running migration"
  kvido skills/planner-state/migrate.sh
fi
```

#### planner-state last-run

Verify that `kvido planner-state last-run get` returns a value. If the JSON file is missing or the command fails, initialise with reset:

```bash
if ! kvido planner-state last-run get &>/dev/null; then
  echo "planner-state missing or unreadable — initialising with reset"
  kvido planner-state reset
fi
```

#### source-health

Verify that `kvido source-health get` works. The command auto-creates `state/source-health.json` if missing, so a failure here indicates a deeper problem:

```bash
kvido source-health get &>/dev/null || echo "WARNING: kvido source-health get failed"
```

#### current

Verify that `kvido current get` works. No initialisation is needed — an empty or missing file is valid:

```bash
kvido current get &>/dev/null || echo "WARNING: kvido current get failed"
```

## Step 3: Planning Bootstrap

If `$KVIDO_HOME/memory/planner.md` does not exist, create it with default content:

```markdown
# Planner — personal instructions

Add your personal instructions for the planner here.

## Examples
- 11:00: Remind me to take a stretch break
- Monday: Review the status of all open MRs from last week

## Scheduled Rules

### Morning briefing
- Trigger: workday, after wh_start, not yet today
- Actions:
  1. Gather data from all sources (full fetch)
  2. Summarize yesterday's work, overnight changes
  3. Show today's calendar + recommendations
  4. Set focus in state/current.md
  5. Run log purge: kvido log purge --before today --archive
- Deliver: slack (template: morning)
- Track: planner-state.md last_morning_date

### EOD journal
- Trigger: workday, after 16:00 (or user invokes), not yet today
- Actions:
  1. Gather data from all sources
  2. Create journal in memory/journal/YYYY-MM-DD.md
  3. Worklog check (Jira — compare time vs logged)
  4. Dispatch librarian for memory extraction
  5. Update state/current.md (clear focus, set notes for tomorrow)
  6. Reset heartbeat-state.json iteration_count
- Deliver: slack (template: eod)
- Track: planner-state.md last_eod_date

### Friday weekly summary
- Trigger: friday, after EOD journal
- Actions:
  1. Read all journals from this week
  2. Create weekly summary in memory/weekly/YYYY-Www.md
  3. Archive journals older than 14 days
- Deliver: slack (template: event)
```

## Step 4: EOD Catch-up

Check `memory/journal/` — if a journal is missing for days where git activity exists:
- Dispatch librarian: "Extraction mode for YYYY-MM-DD. Create a catch-up journal from available data."

## Step 5: Rotation

### Weekly
If `memory/this-week.md` contains a previous week:
- Move content to `memory/weekly/YYYY-Www.md`
- Reset to the current week

### Archive
- Journals older than 14 days → `memory/archive/journal/`
- Weeklies older than 8 weeks → `memory/archive/weekly/`
- Decisions older than 90 days → `memory/archive/decisions/`

## Step 6: Health Check

### Slack config check
Verify that Slack credentials resolve correctly via `kvido config`:
```bash
kvido config 'slack.bot_token'
kvido config 'slack.dm_channel_id'
kvido config 'slack.user_id'
kvido config 'slack.user_name'
```
If any return empty → log warning. Remind user to fill `.env` with actual values.

### Binary check
```bash
command -v jq &>/dev/null || echo "WARNING: jq not found"
```

### Config validation
Run `kvido config --validate` to check config format. Load `kvido context setup` for source-specific required keys. For each installed source plugin, verify required keys exist. Log warnings for missing keys.

### Source health
Run `kvido discover-sources` to get installed source plugins. For each installed source, read its SKILL.md. If the SKILL.md defines a `health` capability, run it and write results to `state/source-health.json`.

Skip sources that are not installed or do not define a health capability.

### Git connectivity
For each repo in `settings.json` (only if kvido-gitlab is installed):
```bash
test -d <path>/.git || echo "WARNING: repo <name> missing at <path>"
```

### Uncommitted assistant changes
```bash
git status --porcelain
```
If non-empty → warning.

## Output

If everything is OK → "Setup complete: all good"
If files were created → list what was created
If catch-up was performed → list what was filled in
