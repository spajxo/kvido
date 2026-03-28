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
hooks/
├── hooks.json                     ← SessionStart, PreCompact hooks
├── build-context.sh               ← generates session context markdown
├── session-start.sh               ← SessionStart hook
├── pre-compact.sh                 ← PreCompact hook
└── session-context.md             ← runtime instructions injected at session start
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
- **Prompts default to English**. Runtime language is configured in the user's `memory/persona.md`.
- **Exit code 10** in fetch scripts means "CLI tool not available, use MCP fallback". The gatherer agent documents MCP fallback procedures for each source.
- **Memory files** are accessed via `kvido memory read <name>` / `kvido memory write <name>` / `kvido memory tree` — never via hardcoded paths. Memory is unstructured — librarian manages organization autonomously.
- **Per-agent instructions** are accessed via `kvido instructions read <agent-name>` / `kvido instructions write <agent-name>` — stored in `$KVIDO_HOME/instructions/`.
- **Agent instructions** are self-contained in `agents/*.md` files. The gatherer agent contains all source fetch instructions inline.
- **Sources are toggled** via `sources.<name>.enabled` in `settings.json` (default: `true`). No separate plugin installation needed.
- **Agent output contract** is formally defined in `docs/agent-output-contract.md` — specifies what heartbeat expects from each agent's stdout output.

## KVIDO_HOME

All runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`):
- `state/` — ephemeral runtime (current.md, session-context.md, log.jsonl, state.json, dashboard.html)
- `tasks/` — task queue (`<status>/<id>-<slug>.md` files, task_counter)
- `instructions/` — per-agent instruction files (read via `kvido instructions read <agent>`)
- `memory/` — persistent, unstructured (memory.md, journals, projects, weekly, learnings) — librarian manages organization
- `settings.json` — configuration (JSON, parsed via `scripts/config.sh`)
- `.env` — secrets (Slack tokens, channel IDs)

The `kvido` CLI exports `$KVIDO_HOME` and all scripts resolve state/memory paths from there. PWD stays as the project directory. Config is at `$KVIDO_HOME/settings.json`.

## Runtime architecture

```
heartbeat (cron, every 10 min) — scripts/heartbeat/
├── reads Slack DM (via core slack.sh)
├── handles trivial chat inline
├── dispatches chat-agent on non-trivial Slack DM
├── runs planner (every Nth tick via planning_interval, foreground)
│   └── planner returns DISPATCH/NOTIFY lines parsed by heartbeat
├── dispatches agents per planner DISPATCH lines (parallel by default)
│   ├── gatherer — fetches all enabled sources, detects changes
│   ├── triager — manages triage lifecycle, polls reactions
│   ├── worker — executes tasks
│   └── maintenance agents (librarian, scout, project-enricher, self-improver)
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
| chat-agent | Handles non-trivial Slack DM messages | heartbeat inline |
| librarian | Memory consolidation and cleanup | planner instruction (daily) |
| project-enricher | Updates project knowledge from git/MRs | planner instruction (daily) |
| self-improver | Conversation analysis, improvement proposals | planner instruction (daily) |
| scout | Checks interest topics via web search | planner instruction (daily) |

### Sources

Sources are configured in `settings.json` under `sources.*`. Each source can be disabled via `sources.<name>.enabled: false`.

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

Key commands: `kvido heartbeat`, `kvido task ...`, `kvido state ...`, `kvido config ...`, `kvido slack ...`, `kvido log ...`, `kvido memory ...`, `kvido instructions ...`, `kvido dashboard`. Run `kvido --help` for full reference.

## Working on this codebase

- Edit agent .md files and commands directly — no build step
- Slack message templates are JSON files in `scripts/slack/templates/`
- Plugin manifest: `.claude-plugin/plugin.json` with name, version, description
- Marketplace manifest: `.claude-plugin/marketplace.json` with single plugin entry
- Validate changes by running `/kvido:setup` health check in a workspace
- User-facing template: `settings.json.example` (config reference — copy to `$KVIDO_HOME/settings.json`)
- Dashboard: `kvido dashboard` opens `state/dashboard.html` (generated by `scripts/heartbeat/generate-dashboard.sh`)
- Releasing: bump version in `.claude-plugin/plugin.json`, commit, push, `gh release create v<version>`, then `claude plugin marketplace update` to refresh local installs
