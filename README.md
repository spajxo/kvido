# kvido

A Claude Code plugin marketplace that turns your terminal into a living workspace assistant.
Install the core plugin and add source plugins for the tools you use.

## Plugins

| Plugin | Description | Prerequisites |
|--------|-------------|---------------|
| **kvido** | Core — heartbeat, planner, worker, chat, triage | `jq` |
| kvido-gitlab | GitLab MR tracking, activity monitoring | `glab` |
| kvido-jira | Jira issue tracking, status changes | `acli` or Atlassian MCP |
| kvido-slack | Slack channel monitoring, message watching | `SLACK_BOT_TOKEN` |
| kvido-calendar | Google Calendar schedule tracking, meeting alerts | Google Calendar MCP |
| kvido-gmail | Email monitoring, priority filtering | `gws` |
| kvido-sessions | Claude Code session analysis | none |

## Installation

```bash
mkdir ~/kvido && cd ~/kvido && git init

# Install core + sources you need
claude plugin install kvido
claude plugin install kvido-gitlab
claude plugin install kvido-slack
# ...

claude    # launch Claude Code
```

Run `/setup` inside the session — it bootstraps `state/`, `memory/`, `.claude/kvido.local.md`, `.env`, `.gitignore`, and `CLAUDE.md`. It detects installed source plugins and offers to install missing ones.

## Quick Launch

After setup, use the shell alias (offered during `/setup`) or:

```bash
./assistant.sh                    # default: /loop 5m /heartbeat
./assistant.sh /morning           # morning briefing
```

Environment variables for `assistant.sh`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_MODEL` | `claude-sonnet-4-6` | Model to use |
| `CLAUDE_PERMISSION_MODE` | `default` | Permission mode (`default`, `acceptEdits`, etc.) |
| `ASSISTANT_NAME` | `kvido` | Session name |
| `CLAUDE_ADDITIONAL_OPTIONS` | | Extra CLI flags |

## Daily Usage

| Trigger | Action |
|---------|--------|
| "good morning" / `/morning` | Daily briefing — schedule, overnight changes, focus |
| "start heartbeat" / `/heartbeat` | Start the cron loop (default 10 min) |
| "done for today" / `/eod` | End-of-day journal, worklog check |
| "going to sleep" | Pause heartbeat until morning |
| "turbo" | Switch to faster heartbeat interval for 30 min |

Leave the terminal open — the heartbeat loop runs unattended in the background.

## Configuration

All gitignored, created by `/setup`:

| File | Purpose |
|------|---------|
| `.claude/kvido.local.md` | Sources config — Slack channels, GitLab repos, Jira projects, Gmail filters. See `kvido.local.md.example`. |
| `.env` | Credentials — `SLACK_BOT_TOKEN`, `SLACK_DM_CHANNEL_ID`, `SLACK_USER_ID`. Optional: `ATLASSIAN_CLOUD_ID`, `ATLASSIAN_SITE`. |
| `memory/persona.md` | Assistant name, personality, language, tone. |

## How It Works

```
heartbeat (cron, every 10 min)
├── reads Slack DM → trivial: reply inline / non-trivial: dispatch chat-agent
├── checks worker queue → dispatch worker if task pending
└── every Nth tick → dispatch planner
    └── discover-sources.sh → finds installed source plugins
        ├── fetches data from each (gitlab, jira, slack, calendar, gmail, sessions)
        ├── detects changes vs previous state
        └── sends Slack notifications for new events
```

## License

MIT — see [LICENSE](LICENSE).
