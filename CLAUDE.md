# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this

A **Claude Code plugin** — not a traditional application. No compilation, no tests, no package manager. The "code" is markdown (agent definitions, commands) + bash scripts.

## Plugin layout

```
.claude-plugin/
├── marketplace.json               ← single plugin entry (source: ".")
└── plugin.json                    ← plugin metadata (name, version)
agents/                            ← subagent definitions (YAML frontmatter + markdown)
commands/                          ← slash commands (heartbeat, setup)
scripts/
├── config.sh                      ← configuration reader (dot-notation, env var resolution)
├── fetch/                         ← source fetch scripts
│   ├── gitlab-activity.sh
│   ├── gitlab-mrs.sh
│   ├── jira.sh
│   ├── calendar.sh
│   ├── gmail.sh
│   ├── sessions.sh
│   └── sessions-messages.sh
├── heartbeat/                     ← heartbeat data scripts
├── slack/                         ← Slack messaging + templates
├── worker/                        ← task management (task.sh)
├── state/                         ← unified state store
├── current/                       ← current focus management
├── log/                           ← activity logging
├── memory/                        ← memory file access
├── instructions/                  ← per-agent instruction file access
└── migrate/                       ← state migration
kvido                              ← CLI entry point
settings.json.example              ← config reference template
```

## Key design decisions

- **Config** is always read via `kvido config 'dot.key'` — never parse `$KVIDO_HOME/settings.json` directly with jq.
- **All bash scripts** use `set -euo pipefail`.
- **Agents communicate via NL stdout output** — heartbeat interprets and acts. No event bus.
- **Heartbeat is the sole Slack communicator** — no agent calls `kvido slack` directly. They return NL output, heartbeat delivers.
- **Planner is a pure scheduler** — returns NL dispatch instructions, does not execute anything.
- **Prompts default to English**. Runtime language is configured in the user's `instructions/persona.md`.
- **Exit code 10** in fetch scripts means "CLI tool not available, use MCP fallback". The gatherer agent documents MCP fallback procedures for each source.
- **Memory files** are read and written directly via the Read/Write tools with `$KVIDO_HOME/memory/<name>.md`. To list, use Glob on `$KVIDO_HOME/memory/**/*.md`. Memory is unstructured — librarian manages organization autonomously.
- **Per-agent instructions** are read directly via the Read tool (`$KVIDO_HOME/instructions/<agent-name>.md`) and written via `kvido instructions write <agent-name>`.
- **Agent instructions** are self-contained in `agents/*.md` files. The gatherer agent contains all source fetch instructions inline.
- **Sources are toggled** via `sources.<name>.enabled` in `settings.json` (default: `true`). No separate plugin installation needed.
- **Agent output contract** is formally defined in `docs/agent-output-contract.md` — specifies what heartbeat expects from each agent's stdout output.

## KVIDO_HOME

All runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`):
- `state/` — ephemeral runtime (log.jsonl, state.json, dashboard.html)
- `tasks/` — task queue (`<status>/<id>-<slug>.md` files, task_counter)
- `instructions/` — per-agent instruction files (read directly via Read tool)
- `memory/` — persistent, unstructured (memory.md, current.md, journals, projects, weekly, learnings) — librarian manages organization
- `settings.json` — configuration (JSON, parsed via `scripts/config.sh`)
- `.env` — secrets (Slack tokens, channel IDs)

The `kvido` CLI exports `$KVIDO_HOME` and all scripts resolve state/memory paths from there. Config is at `$KVIDO_HOME/settings.json`.

## KVIDO_WORKDIR

When the user runs `kvido` from a project directory (not from `$KVIDO_HOME`), the wrapper:

1. Captures the original `$PWD` before changing directories.
2. Saves it to state: `kvido state set workdir.current "$PWD"`.
3. Passes it to Claude via `--add-dir "$PWD"` so Claude can read project files.
4. Changes CWD to `$KVIDO_HOME` — this ensures Claude Code memory (CLAUDE.md, conversation history) is always scoped to one consistent location.

Agents read the original project directory via:
```bash
kvido state get workdir.current 2>/dev/null || true
```

If the user launched `kvido` from `$KVIDO_HOME` itself, `workdir.current` is not set and `--add-dir` is skipped.

## Assistant Behavior

- Communicate in the language set in `instructions/persona.md`. Default: English.
- Read `instructions/persona.md` for assistant name, tone, personality, and language.
- Be concise. No filler, no fluff.
- Silence by default. Do not output anything unless it is useful.
- Write durable findings to state or memory files, not only to the conversation.
- Always include full clickable URLs for MRs, Jira issues, and similar references.
- Run `/kvido:setup` when runtime files are missing or the environment looks broken.

## Context Loading

- Runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`).
- Treat the current working directory as the project context and `$KVIDO_HOME` as Kvido runtime state.
- Before making workflow decisions, read:
  - `memory/memory.md`
  - `memory/index.md` (if present) — overview of what's stored in memory; use it to decide which files to read — don't load everything
  - `kvido current get`
  - `kvido state get` (unified state store; replaces heartbeat-state and planner-state)
- Review recent activity with `kvido log list --today --format human`.
- Use `kvido config 'key.subkey'` for configuration lookups instead of parsing files directly.

## Runtime architecture

```
heartbeat (cron, every 10 min) — scripts/heartbeat/
├── reads Slack DM (via core slack.sh)
├── handles trivial chat inline
├── dispatches chat on non-trivial Slack DM
├── runs planner (every Nth tick via planning_interval, foreground)
│   └── planner returns DISPATCH/NOTIFY lines parsed by heartbeat
├── dispatches agents per planner DISPATCH lines (parallel by default)
│   ├── gatherer — fetches all enabled sources, detects changes
│   ├── triager — manages triage lifecycle, polls reactions
│   ├── worker — executes tasks
│   └── maintenance agents (librarian, researcher, enricher, improver)
├── collects NL outputs from all agents
└── delivers notifications to Slack (heartbeat is the sole communicator)
```

Agents return NL output to heartbeat via stdout. State is managed via unified store (`kvido state get/set`). The gatherer agent contains all source fetch instructions and executes fetch scripts from `scripts/fetch/`.

### Agents

| Agent | Role | Dispatch |
|-------|------|----------|
| planner | Pure scheduler — reads planner memory, returns DISPATCH lines | heartbeat runs every Nth tick (planning_interval) |
| gatherer | Fetches data from all enabled sources, detects changes | planner instruction |
| triager | Manages triage lifecycle — polls reactions, recommends notifications | planner instruction |
| worker | Executes tasks from the queue | planner instruction |
| chat | Handles non-trivial Slack DM messages | heartbeat inline |
| librarian | Memory consolidation and cleanup | planner instruction (daily) |
| enricher | Updates project knowledge from git/MRs | planner instruction (daily) |
| improver | Conversation analysis, improvement proposals | planner instruction (daily) |
| researcher | Checks interest topics via web search | planner instruction (daily) |

### Sources

Sources are configured in `settings.json` as top-level keys. Each source can be disabled via `<name>.enabled: false`.

| Source | Fetch scripts | Prerequisites |
|--------|---------------|---------------|
| gitlab | fetch/gitlab-activity.sh, fetch/gitlab-mrs.sh | glab CLI |
| jira | fetch/jira.sh | acli or Atlassian MCP |
| slack | (inline in gatherer) | Slack Bot Token |
| calendar | fetch/calendar.sh | gws or Google Calendar MCP |
| gmail | fetch/gmail.sh | gws or Gmail MCP |
| sessions | fetch/sessions.sh, fetch/sessions-messages.sh | none |

## Task system

Tasks live in `$KVIDO_HOME/tasks/<status>/` as markdown files with YAML frontmatter. Canonical statuses (defined in `scripts/worker/task.sh`):

```
triage → todo → in-progress → done
                             → failed
                             → cancelled
```

CLI: `kvido task <create|read|move|list|count|find|note> [args]` (delegates to `scripts/worker/task.sh`).

## kvido CLI

Entry point: `./kvido` (symlinked to `~/.local/bin/kvido` via `kvido --install`). Resolves plugin root from `CLAUDE_PLUGIN_ROOT` → script directory → plugin registry fallback.

Key commands: `kvido heartbeat`, `kvido task ...`, `kvido state ...`, `kvido config ...`, `kvido slack ...`, `kvido log ...`, `kvido instructions ...`, `kvido dashboard`. Run `kvido --help` for full reference.

## Natural Language Triggers

Certain user phrases trigger specific kvido actions:

### Sleep Mode

Patterns: `going to sleep`, `good night`, `pause`, `sleep` and similar.

Action: `kvido state set heartbeat.sleep_until <value>`. Default: tomorrow 06:00.

### Heartbeat Loop

Patterns: `start heartbeat`, `set up loop`, `heartbeat loop`, `loop heartbeat` and similar.

Action: run `/loop 10m /kvido:heartbeat`.

### Dashboard

Patterns: `show dashboard`, `open dashboard`, `dashboard`, `status`, `overview` and similar.

Action: regenerate and open the dashboard.

## Working on this codebase

- Edit agent .md files and commands directly — no build step
- Slack message templates are JSON files in `scripts/slack/templates/`
- Plugin manifest: `.claude-plugin/plugin.json` with name, version, description
- Marketplace manifest: `.claude-plugin/marketplace.json` with single plugin entry
- Validate changes by running `/kvido:setup` health check in a workspace
- User-facing template: `settings.json.example` (config reference — copy to `$KVIDO_HOME/settings.json`)
- Dashboard: `kvido dashboard` opens `state/dashboard.html` (generated by `scripts/heartbeat/generate-dashboard.sh`)
- Releasing: bump version in `.claude-plugin/plugin.json`, commit, push, `gh release create v<version>`, then `claude plugin marketplace update` to refresh local installs
