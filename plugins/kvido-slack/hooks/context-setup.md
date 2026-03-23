# Slack Setup

## Prerequisites
| Key | Required | Check |
|-----|----------|-------|
| SLACK_BOT_TOKEN | yes (in .env) | non-empty in $KVIDO_HOME/.env |

## Config Keys
| Key | Required | Check |
|-----|----------|-------|
| sources.slack.channels or sources.slack.dm_channels | yes, at least one | kvido config --keys returns non-empty |
