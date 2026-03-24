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

Clone this repo (it is the plugin marketplace itself) and install plugins from it:

```bash
git clone https://github.com/spajxo/kvido.git ~/kvido
cd ~/kvido

# Install core plugin + any source plugins you need
claude plugin install ./plugins/kvido
claude plugin install ./plugins/kvido-gitlab
claude plugin install ./plugins/kvido-slack
# ...

claude    # launch Claude Code in your project directory
```

Run `/kvido:setup` inside the Claude Code session — it:
- Creates `$KVIDO_HOME` (default: `~/.config/kvido`) with `state/`, `memory/`, `settings.json`, and `.env`
- Installs the `kvido` CLI wrapper to `~/.local/bin/kvido`
- Validates prerequisites and source plugin config
- Detects installed source plugins and suggests missing ones

Runtime instructions are loaded through plugin hooks — Kvido does not need a `CLAUDE.md` in your project.

## Quick Commands

After `/kvido:setup`, the `kvido` CLI is available at `~/.local/bin/kvido`:

```bash
kvido                             # launch Claude Code with /kvido:heartbeat
kvido heartbeat                   # run the heartbeat script directly
kvido task list todo              # list worker queue tasks
kvido config 'skills.heartbeat.wh_start'   # read a config value
```

Shell rule: `kvido` without arguments launches Claude Code. Any argument switches to bash script dispatch (`kvido heartbeat`, `kvido task`, `kvido slack`, `kvido config`, ...).

Slash commands (`/kvido:setup`, `/kvido:heartbeat`, `/kvido:triage`) are used inside Claude Code, not as shell subcommands.

Kvido-specific environment variables (set in `~/.config/kvido/.env` or your shell):

| Variable | Default | Purpose |
|----------|---------|---------|
| `KVIDO_HOME` | `~/.config/kvido` | Runtime state, memory, config, and secrets |
| `KVIDO_NAME` | `kvido` | Session name (`--name`) |
| `KVIDO_PERMISSION_MODE` | `default` | Permission mode (`--permission-mode`) |
| `KVIDO_EXTRA_ARGS` | | Extra CLI flags passed to Claude Code |

All official `ANTHROPIC_*` and `CLAUDE_CODE_*` env vars (model, effort, API key, proxy, ...) work automatically — just set them in `~/.config/kvido/.env` or your environment. See [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables).

## Daily Usage

Start a Claude Code session in your project directory and run `/kvido:heartbeat` to activate the cron loop. The heartbeat runs every 10 minutes unattended — checking Slack, dispatching the planner and worker agents, and delivering notifications.

| Trigger | Action |
|---------|--------|
| `/kvido:heartbeat` | Start the cron loop (default 10 min, adaptive) |
| "good morning" in Slack DM | Daily briefing — schedule, overnight changes, focus |
| "done for today" in Slack DM | End-of-day journal, worklog check |
| "going to sleep" in Slack DM | Pause heartbeat until morning |
| "turbo" in Slack DM | Switch to 1-min heartbeat interval for 30 min |
| `/kvido:triage` | Process unsorted tasks in the backlog |
| `/kvido:setup` | Re-run setup / health check |

Leave the terminal open — the heartbeat loop runs unattended in the background.

## Configuration

All runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`), created by `/kvido:setup`:

| File | Purpose |
|------|---------|
| `settings.json` | Sources config — Slack channels, GitLab repos, Jira projects, Gmail filters. See `plugins/kvido/settings.json.example` for reference. |
| `.env` | Credentials — `SLACK_BOT_TOKEN`, `SLACK_DM_CHANNEL_ID`, `SLACK_USER_ID`, `SLACK_USER_NAME`. Optional: `ATLASSIAN_CLOUD_ID`, `ATLASSIAN_SITE`. |
| `memory/persona.md` | Assistant name, personality, language, tone. |

Config is read at runtime via `kvido config 'dot.key'` — never parse `settings.json` directly.

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
