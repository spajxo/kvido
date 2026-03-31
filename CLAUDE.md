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
skills/
├── heartbeat-planner.md           ← Step 4: planner dispatch (lazy-loaded)
├── heartbeat-dispatch.md          ← Step 5: agent dispatch (lazy-loaded)
└── heartbeat-deliver.md           ← Step 6: output collection & delivery (lazy-loaded)
scripts/
├── config.sh                      ← configuration reader (dot-notation, env var resolution)
├── fetch/                         ← source fetch scripts (gitlab, jira, calendar, gmail, sessions)
├── heartbeat/                     ← heartbeat data scripts
├── slack/                         ← Slack messaging + templates
├── worker/                        ← task management (task.sh)
├── state/                         ← unified state store
├── log/                           ← activity logging
└── migrate/                       ← state migration
kvido                              ← CLI entry point
settings.json.example              ← config reference template
```

## Key design decisions

- **Config** is always read via `kvido config 'dot.key'` — never parse `$KVIDO_HOME/settings.json` directly with jq.
- **All bash scripts** use `set -euo pipefail`.
- **Agents communicate via NL stdout output** — heartbeat interprets and acts. No event bus.
- **Heartbeat is the sole Slack communicator** — no agent calls `kvido slack` directly.
- **Planner is a pure scheduler** — returns NL dispatch instructions, does not execute anything.
- **Prompts default to English**. Runtime language is configured in `instructions/persona.md`.
- **Exit code 10** in fetch scripts means "CLI tool not available, use MCP fallback".
- **Memory files** are read/written directly via Read/Write tools at `$KVIDO_HOME/memory/<name>.md`. Librarian manages organization.
- **Per-agent instructions** are at `$KVIDO_HOME/instructions/<agent-name>.md` (Read tool to read, `kvido instructions write` to write).
- **Agent instructions** are self-contained in `agents/*.md` files. Each agent has a `## Context Loading` block listing what to read at start.
- **Sources are toggled** via `<name>.enabled` in `settings.json` (default: `true`). Details in `agents/gatherer.md` and `agents/sources/*.md`.
- **Agent-memory** (`memory: user`) gives agents persistent per-agent knowledge at `~/.claude/agent-memory/<name>/`. Used for operational self-knowledge (patterns, calibration, preferences). Shared `$KVIDO_HOME/memory/` remains for facts, projects, and decisions. Agents: kvido, chat, planner, improver, reviewer.

## KVIDO_HOME

All runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`):
- `state/` — ephemeral runtime (log.jsonl, state.json, dashboard.html)
- `tasks/` — task queue (`<status>/<id>-<slug>.md` files, task_counter)
- `instructions/` — per-agent instruction files (Read tool)
- `memory/` — persistent, unstructured (memory.md, current.md, journals, projects, weekly, learnings)
- `settings.json` — configuration (parsed via `scripts/config.sh`)
- `.env` — secrets (Slack tokens, channel IDs)

## KVIDO_WORKDIR

When run from a project directory, the `kvido` wrapper saves `$PWD` to `workdir.current` state and passes it via `--add-dir`. CWD changes to `$KVIDO_HOME` for consistent memory scoping. Agents read: `kvido state get workdir.current 2>/dev/null || true`.

## Assistant Behavior

- Communicate in the language set in `instructions/persona.md`. Default: English.
- Be concise. No filler, no fluff. Silence by default.
- Write durable findings to state or memory files, not only to the conversation.
- Always include full clickable URLs for MRs, Jira issues, and similar references.
- Run `/kvido:setup` when runtime files are missing or the environment looks broken.

## Runtime architecture

```
kvido wrapper → claude --agent kvido:kvido → /loop 10m /kvido:heartbeat

heartbeat (cron, every 10 min) — commands/heartbeat.md
├── chat check → inline or dispatch chat agent
├── planner (skill: kvido:heartbeat-planner, when PLANNER_DUE=true)
├── dispatch (skill: kvido:heartbeat-dispatch, when DISPATCH/NOTIFY lines)
├── deliver (skill: kvido:heartbeat-deliver, when agents complete)
└── adaptive interval
```

Agents: planner, gatherer, triager, worker, chat, librarian, enricher, improver, researcher. Each defined in `agents/<name>.md` with role, tools, and output format.

## Task system

Tasks live in `$KVIDO_HOME/tasks/<status>/` as markdown files with YAML frontmatter. Statuses: `triage → todo → in-progress → done/failed/cancelled`. CLI: `kvido task <create|read|move|list|count|find|note>`.

## kvido CLI

Entry point: `./kvido` (symlinked via `kvido --install`). Key commands: `kvido heartbeat`, `kvido task ...`, `kvido state ...`, `kvido config ...`, `kvido slack ...`, `kvido log ...`, `kvido instructions ...`, `kvido dashboard`. Run `kvido --help` for full reference.

## Natural Language Triggers

| Trigger | Patterns | Action |
|---------|----------|--------|
| Sleep | `going to sleep`, `good night`, `pause` | `kvido state set heartbeat.sleep_until <tomorrow 06:00>` |
| Heartbeat | `start heartbeat`, `heartbeat loop` | `/loop 10m /kvido:heartbeat` |
| Dashboard | `dashboard`, `status`, `overview` | Regenerate and open dashboard |

## Working on this codebase

- Edit agent .md files and commands directly — no build step
- Slack message templates are JSON files in `scripts/slack/templates/`
- Plugin manifest: `.claude-plugin/plugin.json` with name, version, description
- Validate changes by running `/kvido:setup` health check in a workspace
- User-facing template: `settings.json.example` (config reference — copy to `$KVIDO_HOME/settings.json`)
- Dashboard: `kvido dashboard` opens `state/dashboard.html`
- Releasing: bump version in `.claude-plugin/plugin.json`, commit, push, `gh release create v<version>`, then `claude plugin marketplace update` to refresh local installs
