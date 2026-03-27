# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this

A **Claude Code plugin marketplace** — not a traditional application. No compilation, no tests, no package manager. The "code" is markdown (agent definitions, commands) + bash scripts.

## Marketplace layout

```
.claude-plugin/marketplace.json    ← plugin registry (lists all 7 plugins)
plugins/
├── kvido/                         ← core plugin (heartbeat, planner, worker, chat, slack delivery)
│   ├── .claude-plugin/plugin.json
│   ├── agents/                    ← subagent definitions (YAML frontmatter + markdown)
│   ├── commands/                  ← slash commands (heartbeat, setup)
│   ├── hooks/                     ← context-<phase>.md hook files
│   └── scripts/                   ← bash helper scripts (CLI, state, config, heartbeat data)
├── kvido-gitlab/                  ← source plugin (requires glab)
├── kvido-jira/                    ← source plugin (requires acli or Atlassian MCP)
├── kvido-slack/                   ← source plugin
├── kvido-calendar/                ← source plugin (Google Calendar MCP)
├── kvido-gmail/                   ← source plugin (requires gws)
└── kvido-sessions/                ← source plugin (no external deps)
```

Source plugins contain only `skills/source-*/` with SKILL.md + fetch scripts. They are discovered at runtime by `plugins/kvido/scripts/discover-sources.sh` which reads `~/.claude/plugins/installed_plugins.json` (source plugin discovery always uses the registry — `CLAUDE_PLUGIN_ROOT` is only relevant for the core `kvido` plugin path).

## Key design decisions

- **Source plugins reference core scripts** (`scripts/slack/slack.sh`, `scripts/worker/task.sh`) via relative paths. This works because they are always invoked by agents running in the core plugin's context — never standalone.
- **Config** is always read via `kvido config 'dot.key'` in source plugin scripts, or via `scripts/config.sh 'dot.key'` in core plugin scripts — never parse `$KVIDO_HOME/settings.json` directly with jq.
- **All bash scripts** use `set -euo pipefail`.
- **Agents communicate via NL stdout output** — heartbeat interprets and acts. No event bus.
- **Heartbeat is the sole Slack communicator** — no agent calls `kvido slack` directly. They return NL output, heartbeat delivers.
- **Planner is a pure scheduler** — returns NL dispatch instructions, does not execute anything.
- **Prompts default to English**. Runtime language is configured in the user's `memory/persona.md`.
- **Exit code 10** in fetch scripts means "CLI tool not available, use MCP fallback". The SKILL.md for each source plugin documents the MCP fallback procedure.
- **config.sh lives only in the core plugin** (`plugins/kvido/scripts/config.sh`). Source plugins call `kvido config 'a.b.c'` instead of maintaining their own copy. The `kvido config` CLI delegates to `scripts/config.sh`.
- **Memory files** are accessed via `kvido memory read <name>` / `kvido memory write <name>` / `kvido memory tree` — never via hardcoded paths. This ensures subagents resolve `$KVIDO_HOME/memory/` correctly regardless of CWD.
- **Agent instructions** are self-contained in `agents/*.md` files. Source plugin SKILL.md files are read by the gatherer agent at runtime.

## KVIDO_HOME

All runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`):
- `state/` — ephemeral runtime (current.md, session-context.md, log.jsonl, state.json, tasks/, dashboard.html)
- `memory/` — persistent (memory.md, journals, projects, weekly, learnings)
- `settings.json` — configuration (JSON, parsed via `scripts/config.sh`)
- `.env` — secrets (Slack tokens, channel IDs)

The `kvido` CLI exports `$KVIDO_HOME` and all scripts resolve state/memory paths from there. PWD stays as the project directory. Config is at `$KVIDO_HOME/settings.json`.

## Plugin Hook System

Plugins contribute instructions via `hooks/context-<phase>.md` files. Assembled by `kvido context <phase>`.

| Phase | When | What plugins contribute |
|-------|------|------------------------|
| session | Before Claude launch | State summary, project info |
| heartbeat | Step 6 delivery | Notification templates, delivery rules |
| planner | Step 4 scheduling | Dispatch rules, maintenance tasks |
| setup | Validation | Prerequisites, config schema |
| compact | Before compaction | State summary per plugin |

## Runtime architecture

```
heartbeat (cron, every 10 min) — plugins/kvido/scripts/heartbeat/
├── reads Slack DM (via core slack.sh)
├── handles trivial chat inline
├── dispatches chat-agent on non-trivial Slack DM
├── runs planner (always, foreground)
│   └── planner returns NL output: which agents to dispatch, in what order
├── dispatches agents per planner instructions (parallel by default)
│   ├── gatherer — fetches sources, detects changes, recommends notifications
│   ├── triager — manages triage lifecycle, polls reactions, recommends notifications
│   ├── worker — executes tasks
│   └── maintenance agents (librarian, scout, project-enricher, self-improver)
├── collects NL outputs from all agents
└── delivers notifications to Slack (heartbeat is the sole communicator)
```

Agents return NL output to heartbeat via stdout. State is managed via unified store (`kvido state get/set`). Source plugins are never invoked standalone — the gatherer agent runs in the core plugin context, reads source SKILL.md files, and executes their fetch scripts. This is why source plugins can reference core scripts (`scripts/slack/slack.sh`, `scripts/worker/task.sh`) via relative paths.

### Agents

| Agent | Role | Dispatch |
|-------|------|----------|
| planner | Pure scheduler — decides what to dispatch | heartbeat runs every tick |
| gatherer | Fetches data from source plugins, detects changes | planner instruction |
| triager | Manages triage lifecycle — polls reactions, recommends notifications | planner instruction |
| worker | Executes tasks from the queue | planner instruction |
| chat-agent | Handles non-trivial Slack DM messages | heartbeat inline |
| librarian | Memory consolidation and cleanup | planner instruction (daily) |
| project-enricher | Updates project knowledge from git/MRs | planner instruction (daily) |
| self-improver | Conversation analysis, improvement proposals | planner instruction (daily) |
| scout | Checks interest topics via web search | planner instruction (daily) |

## Task system

Tasks live in `$KVIDO_HOME/state/tasks/<status>/` as markdown files with YAML frontmatter. Canonical statuses (defined in `plugins/kvido/scripts/worker/task.sh`):

```
triage → todo → in-progress → done
                             → failed
                             → cancelled
```

CLI: `kvido task <create|read|move|list|count|find|note> [args]` (delegates to `scripts/worker/task.sh`).

## kvido CLI

Entry point: `plugins/kvido/kvido` (symlinked to `~/.local/bin/kvido` via `kvido --install`). Resolves plugin root from `CLAUDE_PLUGIN_ROOT` → script directory → plugin registry fallback.

Key commands: `kvido heartbeat`, `kvido task ...`, `kvido state ...`, `kvido config ...`, `kvido slack ...`, `kvido log ...`, `kvido memory ...`, `kvido context <phase>`, `kvido dashboard`. Run `kvido --help` for full reference.

## Working on this codebase

- Edit agent .md files and commands directly — no build step
- Slack message templates are JSON files in `plugins/kvido/scripts/slack/templates/`
- Plugin manifests: each plugin has `.claude-plugin/plugin.json` with name, version, description
- Marketplace manifest: `.claude-plugin/marketplace.json` lists all plugins with `./plugins/<name>` local source paths
- Validate changes by running `/kvido:setup` health check in a workspace
- User-facing template: `plugins/kvido/settings.json.example` (config reference — copy to `$KVIDO_HOME/settings.json`)
- Dashboard: `kvido dashboard` opens `state/dashboard.html` (generated by `scripts/heartbeat/generate-dashboard.sh`)
- Releasing: bump version in all `plugin.json` files (same version everywhere), commit, push, `gh release create v<version>`, then `claude plugin marketplace update` to refresh local installs
