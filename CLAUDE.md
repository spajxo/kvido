# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this

A **Claude Code plugin marketplace** — not a traditional application. No compilation, no tests, no package manager. The "code" is markdown (SKILL.md, agent definitions, commands) + bash scripts.

## Marketplace layout

```
.claude-plugin/marketplace.json    ← plugin registry (lists all 7 plugins)
plugins/
├── kvido/                         ← core plugin (heartbeat, planner, worker, chat, slack delivery)
│   ├── .claude-plugin/plugin.json
│   ├── agents/                    ← subagent definitions (YAML frontmatter + markdown)
│   ├── commands/                  ← slash commands (thin wrappers → SKILL.md)
│   ├── hooks/                     ← pre-compact state injection
│   └── skills/                    ← SKILL.md + bash helpers
├── kvido-gitlab/                  ← source plugin (requires glab)
├── kvido-jira/                    ← source plugin (requires acli or Atlassian MCP)
├── kvido-slack/                   ← source plugin
├── kvido-calendar/                ← source plugin (Google Calendar MCP)
├── kvido-gmail/                   ← source plugin (requires gws)
└── kvido-sessions/                ← source plugin (no external deps)
```

Source plugins contain only `skills/source-*/` with SKILL.md + fetch scripts. They are discovered at runtime by `plugins/kvido/skills/discover-sources.sh` which reads `~/.claude/plugins/installed_plugins.json`.

## Key design decisions

- **Source plugins reference core scripts** (`skills/slack/slack.sh`, `skills/worker/task.sh`) via relative paths. This works because they are always invoked by agents running in the core plugin's context — never standalone.
- **Config** is always read via `skills/config.sh 'flat.key'` — never parse `kvido.local.md` directly.
- **All bash scripts** use `set -euo pipefail`.
- **Agents never send Slack messages directly** — they return NL output. Heartbeat delivers via `slack.sh`.
- **Prompts default to English**. Runtime language is configured in the user's `memory/persona.md`.
- **Exit code 10** in fetch scripts means "CLI tool not available, use MCP fallback". The SKILL.md for each source plugin documents the MCP fallback procedure.
- **config.sh is duplicated** across all source plugins (each has its own copy). When modifying config.sh, update all copies.

## Runtime architecture

```
heartbeat (cron, every 10 min) — plugins/kvido/skills/heartbeat/
├── reads Slack DM (via core slack.sh)
├── checks worker queue (state/tasks/)
├── dispatches planner every Nth tick → plugins/kvido/agents/planner.md
│   └── discover-sources.sh → finds kvido-* plugins in installed_plugins.json
│       ├── reads each source's SKILL.md from its installPath
│       ├── runs fetch.sh (exit 0 = success, exit 10 = use MCP fallback)
│       └── detects changes vs planner-state.md → Slack notifications
├── dispatches worker if task pending → plugins/kvido/agents/worker.md
└── dispatches chat-agent on non-trivial Slack DM
```

Source plugins are never invoked standalone. The planner agent runs in the core plugin context, reads source SKILL.md files, and executes their fetch scripts. This is why source plugins can reference core scripts (`skills/slack/slack.sh`, `skills/worker/task.sh`) via relative paths.

## Working on this codebase

- Edit SKILL.md and agent .md files directly — no build step
- Slack message templates are JSON files in `plugins/kvido/skills/slack/templates/`
- Plugin manifests: each plugin has `.claude-plugin/plugin.json` with name, version, description
- Marketplace manifest: `.claude-plugin/marketplace.json` lists all plugins with `./plugins/<name>` local source paths
- Validate changes by reading plugin conventions and running `/kvido:setup` health check in a workspace
- Core plugin CLAUDE.md (`plugins/kvido/CLAUDE.md`) is separate — it provides runtime instructions when the plugin is installed in a user's workspace
- User-facing templates: `plugins/kvido/kvido.local.md.example` (config reference) and `plugins/kvido/CLAUDE.md.template` (workspace CLAUDE.md)
