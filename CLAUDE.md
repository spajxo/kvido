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
│   ├── commands/                  ← slash commands (thin wrappers → SKILL.md)
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
- **Agents never send Slack messages directly** — they return NL output. Heartbeat delivers via `slack.sh`.
- **Prompts default to English**. Runtime language is configured in the user's `memory/persona.md`.
- **Exit code 10** in fetch scripts means "CLI tool not available, use MCP fallback". The SKILL.md for each source plugin documents the MCP fallback procedure.
- **config.sh lives only in the core plugin** (`plugins/kvido/scripts/config.sh`). Source plugins call `kvido config 'a.b.c'` instead of maintaining their own copy. The `kvido config` CLI delegates to `scripts/config.sh`.
- **Memory files** are accessed via `kvido memory read <name>` / `kvido memory write <name>` / `kvido memory tree` — never via hardcoded paths. This ensures subagents resolve `$KVIDO_HOME/memory/` correctly regardless of CWD.
- **Agent instructions** are self-contained in `agents/*.md` files. Source plugin SKILL.md files are read by the gatherer agent at runtime.

## KVIDO_HOME

All runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`):
- `state/` — ephemeral runtime (current.md, session-context.md, log.jsonl, state.json, events.jsonl, tasks/, dashboard.html)
- `memory/` — persistent (memory.md, journals, projects, weekly, learnings)
- `settings.json` — configuration (JSON, parsed via `scripts/config.sh`)
- `.env` — secrets (Slack tokens, channel IDs)

The `kvido` CLI exports `$KVIDO_HOME` and all scripts resolve state/memory paths from there. PWD stays as the project directory. Config is at `$KVIDO_HOME/settings.json`.

## Plugin Hook System

Plugins contribute instructions via `hooks/context-<phase>.md` files. Assembled by `kvido context <phase>`.

| Phase | When | What plugins contribute |
|-------|------|------------------------|
| session | Before Claude launch | State summary, project info |
| heartbeat | Step 2c delivery | Notification templates, delivery rules |
| planner | Step 3-7 | Event keys, triage rules, maintenance tasks |
| setup | Validation | Prerequisites, config schema |
| compact | Before compaction | State summary per plugin |

## Runtime architecture

```
heartbeat (cron, every 10 min) — plugins/kvido/scripts/heartbeat/
├── reads Slack DM (via core slack.sh)
├── reads dispatch events from event bus (state/events.jsonl)
├── dispatches agents based on dispatch.* events:
│   ├── dispatch.planner → planner (pure scheduler, emits further dispatch events)
│   ├── dispatch.gather → gatherer (fetches sources, emits change.detected events)
│   ├── dispatch.notify → notifier (reads changes, delivers to Slack directly)
│   ├── dispatch.worker → worker (executes tasks)
│   └── dispatch.agent → maintenance/custom agents
└── dispatches chat-agent on non-trivial Slack DM
```

Agents communicate via event bus (`kvido event emit/read/ack`). State is managed via unified store (`kvido state get/set`). Source plugins are never invoked standalone — the gatherer agent runs in the core plugin context, reads source SKILL.md files, and executes their fetch scripts. This is why source plugins can reference core scripts (`scripts/slack/slack.sh`, `scripts/worker/task.sh`) via relative paths.

## Task system

Tasks live in `$KVIDO_HOME/state/tasks/<status>/` as markdown files with YAML frontmatter. Canonical statuses (defined in `plugins/kvido/scripts/worker/task.sh`):

```
triage → todo → in-progress → done
                             → failed
                             → cancelled
```

CLI: `kvido task <create|read|move|list|count|find|note> [args]` (delegates to `scripts/worker/task.sh`).

## Working on this codebase

- Edit agent .md files and commands directly — no build step
- Slack message templates are JSON files in `plugins/kvido/scripts/slack/templates/`
- Plugin manifests: each plugin has `.claude-plugin/plugin.json` with name, version, description
- Marketplace manifest: `.claude-plugin/marketplace.json` lists all plugins with `./plugins/<name>` local source paths
- Validate changes by reading plugin conventions and running `/kvido:setup` health check in a workspace
- Runtime instructions for installed Kvido sessions now live in `plugins/kvido/hooks/context-session.md` and are injected via the plugin `SessionStart` hook.
- User-facing template: `plugins/kvido/settings.json.example` (config reference — copy to `$KVIDO_HOME/settings.json`)
- Dashboard: `kvido dashboard` opens `state/dashboard.html` (generated by `scripts/heartbeat/generate-dashboard.sh`)
- Releasing: bump version in `plugins/kvido/.claude-plugin/plugin.json`, commit, push, `gh release create v<version>`, then `claude plugin marketplace update` to refresh local installs
