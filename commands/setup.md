---
description: Setup & self-healing — first-time onboarding, structure bootstrap, health check
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, Skill
---

# Kvido Setup

Setup and self-healing command. Run on first launch, after plugin installation, or when something is broken.

## Step 0: Prerequisites

### KVIDO_HOME

```bash
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
mkdir -p "$KVIDO_HOME"
```

### kvido CLI

Install or refresh the CLI wrapper:
```bash
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  KVIDO_ROOT="$CLAUDE_PLUGIN_ROOT"
elif [[ -f ~/.claude/plugins/installed_plugins.json ]]; then
  KVIDO_ROOT=$(jq -r '.plugins | to_entries[] | select(.key | startswith("kvido@")) | .value[0].installPath' ~/.claude/plugins/installed_plugins.json 2>/dev/null | head -1)
fi
[[ -n "$KVIDO_ROOT" ]] && bash "$KVIDO_ROOT/kvido" --install
```
Verify `~/.local/bin` is in PATH. If not, inform the user.

### Required tools

Check `jq` and `kvido` are available. If missing, inform the user and do not proceed.

## Step 1: First-time Setup

Detection: `$KVIDO_HOME/settings.json` or `$KVIDO_HOME/instructions/persona.md` does not exist → run first-time setup. If both exist, skip to Step 2.

### a) Config files

If missing, create:
- `$KVIDO_HOME/settings.json` — copy `settings.json.example` from the plugin
- `$KVIDO_HOME/.env` — create with empty `SLACK_BOT_TOKEN`, `SLACK_DM_CHANNEL_ID`, `SLACK_USER_ID`, `SLACK_USER_NAME`

`settings.json` references env vars using `"$ENV_VAR"` syntax. `kvido config` resolves them from `.env`.

### b) Persona setup

If `$KVIDO_HOME/instructions/persona.md` does not exist:
1. Ask: language (default: en), assistant name, tone/personality
2. Create `instructions/persona.md` with appropriate structure
3. Create `memory/` directory if missing

### c) Slack credentials

Check `kvido config 'slack.bot_token'` and `kvido config 'slack.dm_channel_id'`. If empty:
1. Explain: secrets in `.env`, settings.json references them with `"$VAR_NAME"` syntax
2. Help fill `.env` with actual values
3. Confirm settings.json has the references

### d) Source config validation

Check enabled sources: `kvido config "$src.enabled" "true"` for each of gitlab, jira, slack, calendar, gmail, sessions. Prerequisites per source are documented in `agents/gatherer.md` and `agents/sources/*.md`.

For each enabled source, verify required config keys exist via `kvido config`. Show missing keys and help fill them from `settings.json.example`.

## Step 2: Structure Bootstrap

```bash
mkdir -p $KVIDO_HOME/memory/{journal,weekly,projects,people,decisions,archive/{journal,weekly,decisions}}
mkdir -p $KVIDO_HOME/instructions
mkdir -p $KVIDO_HOME/tasks/{triage,todo,in-progress,done,failed,cancelled}
```

Create missing files with minimal content:
- `memory/memory.md` → `# Memory` + sections (Who I am, Active projects, Key decisions, Lessons learned, People)
- `memory/this-week.md` → `# Week YYYY-Www`
- `memory/learnings.md` → `# Learnings`
- `memory/errors.md` → `# Errors`
- `memory/people/_index.md` → `# People`
- `memory/decisions/_index.md` → `# Decisions`
- Heartbeat state: initialize `heartbeat.iteration_count 0` etc. if empty
- Planner/source-health state: initializes lazily

## Step 3: Planning Bootstrap

If `$KVIDO_HOME/instructions/planner.md` does not exist, create with default content including:
- Morning briefing rule (workday, after wh_start)
- EOD journal rule (workday, after 16:00)
- Friday weekly summary rule

Template should include trigger conditions, actions (gather, summarize, journal, focus update via Write tool to `memory/current.md`), delivery template names, and state tracking keys.

## Step 4: EOD Catch-up

Check `memory/journal/` — if missing for days with git activity, dispatch librarian: "Extraction mode for YYYY-MM-DD."

## Step 5: Rotation

- **Weekly:** If `memory/this-week.md` is from previous week → move to `memory/weekly/YYYY-Www.md`, reset
- **Archive:** Journals > 14d → `archive/journal/`, weeklies > 8w → `archive/weekly/`, decisions > 90d → `archive/decisions/`

## Step 6: Health Check

1. **Slack:** Verify `kvido config 'slack.bot_token'`, `slack.dm_channel_id`, `slack.user_id`, `slack.user_name` resolve. Log warnings for empty values.
2. **Config:** `kvido config --validate` for format. Check required keys per enabled source.
3. **Source health:** For enabled sources with health capability, run check and write `source-health.<name>.status` to state.
4. **Git:** For gitlab repos, verify `.git` exists at configured paths.
5. **Uncommitted changes:** `git status --porcelain` — warn if non-empty.

## Output

- All OK → "Setup complete: all good"
- Files created → list what was created
- Catch-up performed → list what was filled in
