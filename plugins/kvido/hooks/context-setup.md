# Setup Rules — Core

## Prerequisites

| Tool | Required | Check |
|------|----------|-------|
| jq | yes | command -v jq |
| kvido | yes | command -v kvido |

## Config

Config file: $KVIDO_HOME/kvido.local.md
Env file: $KVIDO_HOME/.env

### Required .env keys
- SLACK_DM_CHANNEL_ID
- SLACK_USER_ID
- SLACK_USER_NAME
- SLACK_BOT_TOKEN

## Directory structure

```
$KVIDO_HOME/
├── .env
├── kvido.local.md
├── memory/{journal,weekly,projects,people,decisions,archive/{journal,weekly,decisions}}
└── state/tasks/{triage,todo,in-progress,done,failed,cancelled}
```
