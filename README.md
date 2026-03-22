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

Run `/kvido:setup` inside the session — it bootstraps `state/`, `memory/`, `.claude/kvido.local.md`, `.env`, `.gitignore`, and `CLAUDE.md`. It detects installed source plugins and offers to install missing ones.

## Quick Launch

After setup, use the shell alias (offered during `/kvido:setup`) or:

```bash
kvido                             # default: /loop 5m /kvido:heartbeat
kvido /kvido:morning              # morning briefing
```

Kvido-specific environment variables (set in `.env` or shell):

| Variable | Default | Purpose |
|----------|---------|---------|
| `KVIDO_NAME` | `kvido` | Session name (`--name`) |
| `KVIDO_PERMISSION_MODE` | `default` | Permission mode (`--permission-mode`) |
| `KVIDO_EXTRA_ARGS` | | Extra CLI flags |

All official `ANTHROPIC_*` and `CLAUDE_CODE_*` env vars (model, effort, API key, proxy, ...) work automatically — just set them in `.env` or your environment. See [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables).

## Daily Usage

| Trigger | Action |
|---------|--------|
| "good morning" / `/kvido:morning` | Daily briefing — schedule, overnight changes, focus |
| "start heartbeat" / `/kvido:heartbeat` | Start the cron loop (default 10 min) |
| "done for today" / `/kvido:eod` | End-of-day journal, worklog check |
| "going to sleep" | Pause heartbeat until morning |
| "turbo" | Switch to faster heartbeat interval for 30 min |

Leave the terminal open — the heartbeat loop runs unattended in the background.

## Configuration

All gitignored, created by `/kvido:setup`:

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
