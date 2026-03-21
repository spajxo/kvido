# kvido

Kvido is a Claude Code plugin marketplace that turns your terminal into a living workspace assistant.
Install the core plugin and add source plugins for the tools you use — Jira, GitLab, Slack, Calendar, Gmail.

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

1. Create a dedicated workspace directory:

   ```bash
   mkdir ~/kvido && cd ~/kvido && git init
   ```

2. Install the core plugin and the sources you need:

   ```bash
   claude plugin install kvido
   claude plugin install kvido-gitlab
   claude plugin install kvido-jira
   # ... add more as needed
   ```

3. Launch Claude Code and run setup:

   ```bash
   claude
   ```

4. Run `/setup` inside the Claude Code session — it creates the runtime directories
   (`state/`, `memory/`), config templates (`.claude/kvido.local.md`, `.env`),
   `.gitignore`, and `CLAUDE.md`. It also detects installed source plugins and
   offers to install missing ones.

## Quick launch

After setup, use the shell alias (offered during `/setup`) or run directly:

```bash
./assistant.sh                    # default: /loop 5m /heartbeat
./assistant.sh /morning           # morning briefing
```

## Daily Usage

| Trigger | Action |
|---------|--------|
| Say "good morning" or `/morning` | Daily briefing — schedule, overnight changes, focus |
| Say "start heartbeat" or `/heartbeat` | Start the cron loop (default every 10 min) |
| Say "done for today" or `/eod` | End-of-day journal, worklog check |
| Say "going to sleep" | Pause heartbeat until morning |

## Configuration

Three config locations, all gitignored:

**`.claude/kvido.local.md`** — sources and skill behavior.
Fill in Slack channel IDs, GitLab repo paths, Jira project keys, Gmail filters.
See `kvido.local.md.example` for the full reference.

**`.env`** — credentials and IDs.
Required: `SLACK_BOT_TOKEN`, `SLACK_DM_CHANNEL_ID`, `SLACK_USER_ID`.
Optional: `ATLASSIAN_CLOUD_ID`, `ATLASSIAN_SITE`, `CLAUDE_MODEL`.

**`memory/persona.md`** — assistant name, personality, language, and tone.

## Repository Structure

```
kvido/                                # marketplace repo
├── .claude-plugin/marketplace.json   # plugin registry
├── plugins/
│   ├── kvido/                        # core assistant plugin
│   │   ├── agents/                   # planner, worker, chat-agent, ...
│   │   ├── commands/                 # /heartbeat, /morning, /eod, /triage, /setup
│   │   ├── skills/                   # heartbeat, planner, worker, slack delivery, ...
│   │   └── hooks/                    # pre-compact state injection
│   ├── kvido-gitlab/                 # GitLab source plugin
│   ├── kvido-jira/                   # Jira source plugin
│   ├── kvido-slack/                  # Slack source plugin
│   ├── kvido-calendar/               # Calendar source plugin
│   ├── kvido-gmail/                  # Gmail source plugin
│   └── kvido-sessions/               # Sessions source plugin
├── kvido.local.md.example            # annotated config template
└── CLAUDE.md.template                # workspace CLAUDE.md template
```

## How It Works

On each heartbeat tick, kvido gathers data (Slack DM check, worker queue),
then dispatches the planner subagent. The planner uses `discover-sources.sh`
to find installed source plugins, fetches live data from each, detects changes,
and sends Slack notifications. The worker queue executes tasks as isolated subagents.

## Status

v0.2.0 — ready for testing. See [LICENSE](LICENSE) for terms.
