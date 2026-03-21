# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this

Kvido is a **Claude Code plugin marketplace** containing the core assistant and optional source plugins. The repo is organized as a marketplace with plugins in `plugins/` subdirectories.

It is **not** a traditional application. There is no compilation, no test suite, no package manager, no build step. The "code" is markdown (SKILL.md, agent definitions, commands) + bash scripts.

**Usage model:** The user creates their own workspace folder (e.g. `~/kvido/`), installs the core plugin (`claude plugin install kvido-assistant`) and optional source plugins (e.g. `claude plugin install kvido-gitlab`). Runtime files (`state/`, `memory/`, `.env`, `.claude/kvido.local.md`) live in the user's workspace. They are created by `/setup`.

## Prerequisites (for the user's workspace)

Required: `jq`. Source plugins have their own prerequisites (see each plugin's description).

## Architecture

### Marketplace structure

This repo is a Claude Code plugin marketplace. Each plugin is in `plugins/<name>/` with its own `.claude-plugin/plugin.json`.

| Plugin | Description | Prerequisites |
|--------|-------------|---------------|
| `kvido-assistant` | Core — heartbeat, planner, worker, triage | `jq` |
| `kvido-gitlab` | GitLab MR tracking, activity monitoring | `glab` |
| `kvido-jira` | Jira issue tracking, status changes | `acli` or Atlassian MCP |
| `kvido-slack` | Slack channel monitoring | `SLACK_BOT_TOKEN` |
| `kvido-calendar` | Google Calendar schedule tracking | Google Calendar MCP |
| `kvido-gmail` | Email monitoring, priority filtering | `gws` |
| `kvido-sessions` | Claude Code session analysis | none |

### Core loop

1. **Heartbeat** (`skills/heartbeat/`) — cron-based orchestrator (default 10min). Manages chat, worker, planner dispatch via TodoWrite/TodoRead. Owns all Slack delivery through `skills/slack/slack.sh`.
2. **Planner** (`agents/planner.md` + `skills/planner/`) — runs every Nth heartbeat. Fetches data from sources, detects changes, generates notifications/triage items, dispatches agents (morning/eod).
3. **Worker** (`agents/worker.md` + `skills/worker/`) — async task queue backed by local markdown files in `state/tasks/`. Max 1 concurrent. Model selected by task size (s/m → sonnet, l/xl → opus). All task operations via `skills/worker/task.sh`.
4. **Chat-agent** (`agents/chat-agent.md`) — dispatched by heartbeat for non-trivial Slack DM messages (lookups, task creation, pipeline responses). Trivial messages (greetings, sleep, turbo, cancel) heartbeat handles inline.

### Data flow

- **Sources** — separate plugins (`kvido-gitlab`, `kvido-jira`, etc.). Discovered at runtime via `skills/discover-sources.sh` which reads `~/.claude/plugins/installed_plugins.json`.
- **Config** — `skills/config.sh 'flat.key'` reads flat dot-notation YAML frontmatter from `.claude/kvido.local.md`
- **State** (`state/`) — ephemeral runtime: `current.md`, `today.md`, `heartbeat-state.json`, `tasks/{triage,todo,in-progress,done,failed,cancelled}/`
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

All agents are dispatched by heartbeat with `run_in_background: true`. They return NL output — **never send Slack messages directly**. Heartbeat parses output and delivers via `slack.sh`. Trivial chat messages (greetings, sleep, turbo, cancel) are handled by heartbeat inline without dispatching an agent.

| Agent | Trigger | Purpose |
|-------|---------|---------|
| planner | Every Nth heartbeat | Change detection, notifications, agent dispatch |
| worker | Heartbeat when queue non-empty | Async task execution (local task files) |
| chat-agent | Heartbeat on non-trivial Slack DM | Lookups, task creation, pipeline responses |
| librarian | EOD / maintenance | Memory consolidation, extraction, cleanup |
| morning | Dispatched by planner | Daily briefing (also available as `/morning`) |
| eod | Dispatched by planner | End-of-day journal (also available as `/eod`) |
| project-enricher | Maintenance heartbeat (haiku) | Lightweight project knowledge update from git/MR activity |
| self-improver | Daily (sonnet) | Analyzes conversations and Slack DM for improvement proposals |

### Key conventions

- All bash scripts use `set -euo pipefail`
- Config access: `skills/config.sh '.path.to.key'` (never parse kvido.local.md directly)
- Worker queue: local markdown files in `state/tasks/` organized by status folders (triage, todo, in-progress, done, failed, cancelled). All operations via `skills/worker/task.sh`
- Dispatch tracking: TodoWrite/TodoRead (not file-based locks)
- Language: All prompts default to English. Runtime language is configured in the user's `memory/persona.md`.
- Hook: `hooks/pre-compact.sh` injects state summary before context compaction

## Working on this codebase

- Skills are markdown files (`SKILL.md`) with optional bash helpers — edit directly
- Agents are markdown templates in `agents/` with YAML frontmatter (name, description, tools, model)
- Commands in `commands/` are thin wrappers that delegate to SKILL.md files
- Templates for Slack messages are JSON files in `skills/slack/templates/`
- No build step, no tests — validate by reading the plugin conventions and running `/setup` health check
