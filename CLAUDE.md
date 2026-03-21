# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this

Kvido is a **Claude Code plugin** distributed via plugin marketplace. This repo IS the plugin — it gets installed into `~/.claude/plugins/cache/` and provides skills, agents, commands, and hooks.

It is **not** a traditional application. There is no compilation, no test suite, no package manager, no build step. The "code" is markdown (SKILL.md, agent definitions, commands) + bash scripts.

**Usage model:** Uživatel si vytvoří vlastní workspace složku (např. `~/kvido/`), nainstaluje plugin lokálně (`claude plugin install kvido --scope local`) a spouští Claude Code v té složce. Kvido pak běží jako rezidentní asistent — monitoruje externí zdroje (Jira, GitLab, Slack, Calendar, Gmail) a komunikuje přes Slack DM. Runtime soubory (`state/`, `memory/`, `.env`, `.claude/kvido.local.md`) žijí v uživatelově workspace, ne v tomto repo. Vytváří je `/setup`.

## Prerequisites (pro uživatelův workspace)

Required: `glab`, `jq`, `yq`. Optional: `acli` (Jira), `gws` (Google Workspace).

## Architecture

### Plugin structure

Claude Code plugin (`.claude-plugin/plugin.json`). Installed via `claude plugin install --plugin-dir`.

### Core loop

1. **Heartbeat** (`skills/heartbeat/`) — cron-based orchestrator (default 10min). Manages chat, worker, planner dispatch via TodoWrite/TodoRead. Owns all Slack delivery through `skills/slack/slack.sh`.
2. **Planner** (`agents/planner.md` + `skills/planner/`) — runs every Nth heartbeat. Fetches data from sources, detects changes, generates notifications/triage items, dispatches agents (morning/eod).
3. **Worker** (`agents/worker.md` + `skills/worker/`) — async task queue backed by GitLab Issues. Max 1 concurrent. Model selected by task size (s/m → sonnet, l/xl → opus).
4. **Chat-agent** (`agents/chat-agent.md`) — dispatched by heartbeat for non-trivial Slack DM messages (lookups, task creation, pipeline responses). Trivial messages (greetings, sleep, turbo, cancel) heartbeat handles inline.

### Data flow

- **Sources** (`skills/source-*/`) — bash fetch scripts for GitLab, Jira, Slack, Calendar, Gmail, Sessions
- **Config** — `skills/config.sh '<yq_expression>'` reads YAML frontmatter from `.claude/kvido.local.md`
- **State** (`state/`) — ephemeral runtime: `current.md`, `today.md`, `heartbeat-state.json`
- **Memory** (`memory/`) — persistent: `memory.md`, journals, projects, people, decisions, learnings
- **Librarian** (`agents/librarian.md`) — memory consolidation, extraction from journals, cleanup, auto-memory sync

### Slash commands

| Command | Entry point | Purpose |
|---------|-------------|---------|
| `/heartbeat` | `commands/heartbeat.md` | Start heartbeat cron loop |
| `/morning` | `commands/morning.md` | Daily briefing |
| `/eod` | `commands/eod.md` | End-of-day journal + worklog |
| `/triage` | `commands/triage.md` | Process backlog items |
| `/setup` | `commands/setup.md` | Onboarding, bootstrap, health check |

### Agents

All agents are dispatched by heartbeat with `run_in_background: true`. They return NL output — **never send Slack messages directly**. Heartbeat parses output and delivers via `slack.sh`. Triviální chat zprávy (pozdravy, sleep, turbo, cancel) heartbeat řeší inline bez dispatch agenta.

| Agent | Trigger | Purpose |
|-------|---------|---------|
| planner | Every Nth heartbeat | Change detection, notifications, agent dispatch |
| worker | Heartbeat when queue non-empty | Async task execution (GitLab Issues) |
| chat-agent | Heartbeat on non-trivial Slack DM | Lookups, task creation, pipeline responses |
| librarian | EOD / maintenance | Memory consolidation, extraction, cleanup |
| morning | Dispatched by planner | Daily briefing (also available as `/morning`) |
| eod | Dispatched by planner | End-of-day journal (also available as `/eod`) |
| project-enricher | Maintenance heartbeat (haiku) | Lightweight project knowledge update from git/MR activity |
| self-improver | Daily (sonnet) | Analyzes conversations and Slack DM for improvement proposals |

### Key conventions

- All bash scripts use `set -euo pipefail`
- Config access: `skills/config.sh '.path.to.key'` (never parse kvido.local.md directly)
- Worker queue: GitLab Issues with labels `status:triage`, `status:todo`, `status:in-progress`, `status:review`
- Dispatch tracking: TodoWrite/TodoRead (not file-based locks)
- Language: Czech (codebase, prompts, agent output)
- Hook: `hooks/pre-compact.sh` injects state summary before context compaction

## Working on this codebase

- Skills are markdown files (`SKILL.md`) with optional bash helpers — edit directly
- Agents are markdown templates in `agents/` with YAML frontmatter (name, description, tools, model)
- Commands in `commands/` are thin wrappers that delegate to SKILL.md files
- Templates for Slack messages are JSON files in `skills/slack/templates/`
- No build step, no tests — validate by reading the plugin conventions and running `/setup` health check
