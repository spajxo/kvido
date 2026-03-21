---
name: setup
description: Setup & self-healing — first-time onboarding, structure bootstrap, health check
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent
---

# Kvido Setup

**Language:** Communicate in the language set in memory/persona.md. Default: English.

Setup and self-healing command. Run on first launch, after plugin installation, or when something is broken.

## Step 0: Prerequisites

```bash
for cmd in jq; do
  if command -v "$cmd" &>/dev/null; then
    echo "OK: $cmd $(command -v $cmd)"
  else
    echo "MISSING: $cmd — required"
  fi
done
for cmd in glab acli gws; do
  if command -v "$cmd" &>/dev/null; then
    echo "OK: $cmd $(command -v $cmd)"
  else
    echo "OPTIONAL: $cmd not found"
  fi
done
```

If a required tool is missing, inform the user and offer installation. Do not proceed until required prerequisites are met.

## Step 1: First-time Setup

Detection: `.env` does not exist OR `memory/persona.md` does not exist → run first-time setup.
If both exist, skip to Step 2.

### a) Config files

If files don't exist, create them:
- `.claude/kvido.local.md` — copy `kvido.local.md.example` from the plugin
- `.env` — create with empty values:
  ```
  SLACK_DM_CHANNEL_ID=
  SLACK_USER_ID=
  SLACK_USER_NAME=
  SLACK_BOT_TOKEN=
  ```

### b) Persona setup

If `memory/persona.md` does not exist:
1. Ask the user:
   - "What language should Kvido use? (default: en)"
   - "What's your assistant's name? What tone and personality should it have? (e.g. brief and factual, friendly, formal...)"
2. From the answers, create `memory/persona.md` with the appropriate structure (name, language, tone, personality, URL formats). Store language as `language: en` (or the chosen language code).
3. Also create the `memory/` directory if it doesn't exist.

### c) .env values

Read `.env`. If it contains empty values (keys with `=""` or `=`):
1. List the missing values and what they are used for
2. Offer help filling them in (how to find Slack IDs, where to get tokens, etc.)
3. If the user provides values, write them to `.env`

### d) .gitignore

Add to `.gitignore` if not already present:
```
.claude/kvido.local.md
.env
state/
memory/
```

### e) CLAUDE.md

If the project does not have a `CLAUDE.md`, copy `CLAUDE.md.template` from the plugin as a starting point.

### f) Shell alias

Offer the user a shell alias for quick launching:

1. Derive alias name from `memory/persona.md` assistant name (lowercase, strip diacritics via `iconv -f utf-8 -t ascii//TRANSLIT`). Fallback: `kvido`.
2. Ask: "Do you want to create a shell alias `<name>` for quick launching?"
3. If yes:
   - Detect shell rc file: if `$SHELL` contains `zsh` → `~/.zshrc`, else `~/.bashrc`
   - Resolve plugin path: the `assistant.sh` script is located in the plugin root (parent of this `commands/` directory). Use the absolute path.
   - Append to rc file (only if alias not already present):
     ```bash
     alias <name>='<absolute_path_to_plugin>/assistant.sh'
     ```
   - Inform user: "Alias created. Run `source ~/.zshrc` (or `~/.bashrc`) or restart your shell to activate it."
4. If no: skip silently.


## Step 2: Structure Bootstrap

Create missing directories:

```bash
mkdir -p memory/{journal,weekly,projects,people,decisions,archive/{journal,weekly,decisions}}
mkdir -p state/tasks/{triage,todo,in-progress,done,failed,cancelled}
```

For each missing file, create with minimal content:
- `memory/memory.md` → `# Memory` + sections (Who I am, Active projects, Key decisions, Lessons learned, People)
- `memory/this-week.md` → `# Week YYYY-Www`
- `memory/learnings.md` → `# Learnings`
- `memory/errors.md` → `# Errors`
- `memory/people/_index.md` → `# People`
- `memory/decisions/_index.md` → `# Decisions`
- `state/heartbeat-state.json` → default schema (iteration_count: 0, all timestamps null, last_chat_ts: "0", cron_job_id: "", active_preset: "10m", last_interaction_ts: null)
- `state/current.md` → empty template (Active Focus, WIP, Blockers, Parked, Notes for Tomorrow)
- `state/planner-state.md` → empty planner state template

## Step 3: Planning Bootstrap

If `memory/planner.md` does not exist, create it with example content:

```markdown
# Planner — personal instructions

Add your personal instructions for the planner here.

## Examples
- 11:00: Remind me to take a stretch break
- Monday: Review the status of all open MRs from last week
- Friday 15:00: Prepare for weekly standup
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

### Env check
Verify that `.env` contains all required keys (`SLACK_DM_CHANNEL_ID`, `SLACK_USER_ID`, `SLACK_USER_NAME`, `SLACK_BOT_TOKEN`) and that they are not empty.
Missing or empty → log warning.

### Binary check
```bash
for cmd in jq glab acli gws; do
  command -v "$cmd" &>/dev/null || echo "WARNING: $cmd not found"
done
```

### Git connectivity
For each repo in `.claude/kvido.local.md`:
```bash
test -d <path>/.git || echo "WARNING: repo <name> missing at <path>"
```

### Source health
Run health check from each source skill (per SKILL.md → health capability).
Write results to `state/source-health.json`.

### Uncommitted assistant changes
```bash
git status --porcelain
```
If non-empty → warning.

## Output

If everything is OK → "Setup complete: all good"
If files were created → list what was created
If catch-up was performed → list what was filled in
