# Setup Rules — Core

## Prerequisites

| Tool | Required | Check |
|------|----------|-------|
| jq | yes | command -v jq |
| kvido | yes | command -v kvido |

## Config

Config file: $KVIDO_HOME/settings.json
Env file: $KVIDO_HOME/.env (secrets only — referenced via "$ENV_VAR" in settings.json)

### Required settings.json keys (via kvido config)
- slack.bot_token — Slack bot token (xoxb-...), typically "$SLACK_BOT_TOKEN"
- slack.dm_channel_id — Self DM channel ID for assistant delivery
- slack.user_id — Slack user ID
- slack.user_name — Slack display name

Values like "$SLACK_BOT_TOKEN" in settings.json are resolved from .env automatically by `kvido config`.

## Directory structure

```
$KVIDO_HOME/
├── .env          (secrets — keys referenced from settings.json)
├── settings.json
├── memory/{journal,weekly,projects,people,decisions,archive/{journal,weekly,decisions}}
└── state/tasks/          (managed via `kvido task` commands; subdirs: triage, todo, in-progress, done, failed, cancelled)
```
