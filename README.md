<p align="center">
  <img src="assets/kvido-avatar.png" alt="Kvido" width="200">
</p>

# kvido

A Claude Code plugin that turns your terminal into a living workspace assistant. Kvido runs in the background, watches your tools (GitLab, Jira, Slack, Calendar, Gmail), and keeps you informed — all through Slack.

## What does it do?

- **Heartbeat loop** — runs every 10 minutes unattended, checking your sources for changes and delivering Slack notifications
- **Planner** — detects new MRs, Jira status changes, calendar events, unread emails, and Slack mentions
- **Worker** — picks up tasks from a queue and executes them autonomously (code reviews, research, follow-ups)
- **Chat** — reply to Kvido in Slack DM and it responds, delegates tasks, or gives you a daily briefing

Just type `kvido` in your terminal, leave it running, and interact through Slack.

## How It Works

```
heartbeat (cron, every 10 min)
├── reads Slack DM → trivial: reply inline / non-trivial: dispatch chat
├── checks worker queue → dispatch worker if task pending
└── every Nth tick → dispatch planner
    └── gatherer fetches all enabled sources (gitlab, jira, slack, calendar, gmail, sessions)
        ├── detects changes vs previous state
        └── sends Slack notifications for new events
```

## Daily Usage

| Trigger | Action |
|---------|--------|
| `/kvido:heartbeat` | Start the cron loop (default 10 min, adaptive) |
| "good morning" in Slack DM | Daily briefing — schedule, overnight changes, focus |
| "done for today" in Slack DM | End-of-day journal, worklog check |
| "going to sleep" in Slack DM | Pause heartbeat until morning |
| "turbo" in Slack DM | Switch to 1-min heartbeat interval for 30 min |
| `/kvido:setup` | Re-run setup / health check |

## Sources

Kvido comes with built-in sources for the tools you use. Enable/disable each in `settings.json`:

| Source | Description | Prerequisites |
|--------|-------------|---------------|
| gitlab | GitLab MR tracking, activity monitoring | `glab` |
| jira | Jira issue tracking, status changes | `acli` or Atlassian MCP |
| slack | Slack channel monitoring, message watching | `SLACK_BOT_TOKEN` |
| calendar | Google Calendar schedule tracking, meeting alerts | `gws` or Google Calendar MCP |
| gmail | Email monitoring, priority filtering | `gws` or Gmail MCP |
| sessions | Claude Code session analysis | none |

## Installation

Install the plugin from the marketplace — no need to clone this repo:

```bash
# Add the marketplace
claude plugin marketplace add https://github.com/spajxo/kvido

# Install the plugin
claude plugin install kvido@kvido-assistant
```

Then open Claude Code in any project directory and run `/kvido:setup`:

```bash
claude    # in your project directory
# inside the session: /kvido:setup
```

Setup will:
- Create `$KVIDO_HOME` (default: `~/.config/kvido`) with `state/`, `memory/`, `settings.json`, and `.env`
- Install the `kvido` CLI wrapper to `~/.local/bin/kvido`
- Validate prerequisites and source config
- Disable sources you don't need via `<name>.enabled: false`

Runtime instructions are loaded through plugin hooks — Kvido does not need a `CLAUDE.md` in your project.

## Quick Commands

After `/kvido:setup`, the `kvido` CLI is available at `~/.local/bin/kvido`:

```bash
kvido                             # launch Claude Code with /kvido:heartbeat
kvido heartbeat                   # run the heartbeat script directly
kvido task list todo              # list worker queue tasks
kvido config 'heartbeat.wh_start'          # read a config value
```

Shell rule: `kvido` without arguments launches Claude Code. Any argument switches to bash script dispatch (`kvido heartbeat`, `kvido task`, `kvido slack`, `kvido config`, ...).

Slash commands (`/kvido:setup`, `/kvido:heartbeat`) are used inside Claude Code, not as shell subcommands.

## Configuration

All runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`), created by `/kvido:setup`:

| File | Purpose |
|------|---------|
| `settings.json` | Sources config — Slack channels, GitLab repos, Jira projects, Gmail filters. See `settings.json.example` for reference. |
| `.env` | Credentials — `SLACK_BOT_TOKEN`, `SLACK_DM_CHANNEL_ID`, `SLACK_USER_ID`, `SLACK_USER_NAME`. Optional: `ATLASSIAN_CLOUD_ID`, `ATLASSIAN_SITE`. |
| `instructions/persona.md` | Assistant name, personality, language, tone. |

Config is read at runtime via `kvido config 'dot.key'` — never parse `settings.json` directly.

Kvido-specific environment variables (set in `~/.config/kvido/.env` or your shell):

| Variable | Default | Purpose |
|----------|---------|---------|
| `KVIDO_HOME` | `~/.config/kvido` | Runtime state, memory, config, and secrets |
| `KVIDO_NAME` | `kvido` | Session name (`--name`) |
| `KVIDO_PERMISSION_MODE` | `default` | Permission mode (`--permission-mode`) |
| `KVIDO_EXTRA_ARGS` | | Extra CLI flags passed to Claude Code |

All official `ANTHROPIC_*` and `CLAUDE_CODE_*` env vars (model, effort, API key, proxy, ...) work automatically — just set them in `~/.config/kvido/.env` or your environment. See [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables).

## License

MIT — see [LICENSE](LICENSE).
