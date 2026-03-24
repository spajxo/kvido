# Slack Setup

## Config Keys
| Key | Required | Check |
|-----|----------|-------|
| slack.bot_token | yes | kvido config 'slack.bot_token' returns non-empty |
| slack.dm_channel_id | yes | kvido config 'slack.dm_channel_id' |
| sources.slack.channels or sources.slack.dm_channels | yes, at least one | kvido config --keys returns non-empty |
