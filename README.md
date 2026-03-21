# kvido

Personal AI workflow assistant for Claude Code — heartbeat, planner, worker, triage.

## What is kvido

Kvido is a Claude Code plugin that turns your project directory into a living workspace:
- **Heartbeat** — periodic background monitoring of Jira, GitLab, Slack, Calendar, Gmail
- **Planner** — change detection, triage, notifications, daily context
- **Worker** — async task queue via GitLab Issues
- **Morning / EOD** — daily briefing and end-of-day journal

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| glab | Yes | Worker queue (GitLab Issues) |
| jq | Yes | JSON parsing |
| yq | Yes | YAML parsing (kvido.local.md) |
| acli | No | Jira integration |
| gws | No | Google Workspace (Gmail, Calendar) |

## Installation

```bash
claude plugin install --plugin-dir /path/to/kvido-plugin
```

Then run `/setup` inside Claude Code to complete the onboarding:

1. Verify prerequisites (glab, jq, yq)
2. Create runtime directories (`state/`, `memory/`)
3. Copy config templates (`kvido.local.md`, `.env`)
4. Update `.gitignore`
5. Copy `CLAUDE.md.template` as project `CLAUDE.md`
6. Run `/setup` for verification

## Structure

```
kvido-plugin/
├── plugin.json              # Plugin manifest
├── CLAUDE.md.template       # Template for project CLAUDE.md
├── kvido.local.md.example   # Config template (sources, skills, runtime)
├── skills/                  # Skill definitions (SKILL.md + bash scripts)
│   ├── config.sh            # Unified config loader
│   ├── heartbeat/           # Orchestrator
│   ├── planner/             # Central brain
│   ├── worker/              # Task queue scripts
│   ├── morning/             # Daily briefing
│   ├── eod/                 # End of day
│   ├── triage/              # Inbox processing
│   ├── slack/               # Slack transport + templates
│   ├── source-*/            # Data source fetchers
│   └── ...                  # glab, acli-jira, gws-*, interests, etc.
├── agents/                  # Subagent definitions
├── commands/                # Slash commands (/morning, /eod, /heartbeat, /triage, /setup)
└── hooks/                   # hooks.json + pre-compact.sh
```

## Status

Version 0.1.0 — plugin packaged with full content. Ready for `--plugin-dir` testing.
