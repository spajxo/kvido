### Slack

> Config: `sources.slack.*` keys. Credentials via `.env`. Requires: Slack Web API (kvido slack) + optionally Slack MCP.

#### Capabilities

**watch-dm:**
```bash
kvido slack read --limit 5
```
Filter new messages via `jq` (`.ts > "$last_dm_ts"`). Also check `sources.slack.dm_channels`:
```bash
kvido config --keys 'sources.slack.dm_channels'
```
For each with `channel_id`:
```bash
kvido slack read "$CHANNEL_ID" --limit 5 --oldest "$last_dm_ts"
```

Notification levels for new messages from other users:
| Level | When | Action |
|---|---|---|
| `silent` | FYI, informational | `kvido log add chat silent --message "..."` |
| `batch` | Less urgent, can wait | Return with `Event (batch):` prefix |
| `immediate` | Requires response | Return: `Event: DM from <name> — <text>. Urgency: high.` |

Always update: `kvido state set heartbeat.last_dm_ts "<newest ts>"`

**watch-channels:**
List via `kvido config --keys 'sources.slack.channels'`. For high+normal priority with `channel_id`:
- Without `use_mcp`: `kvido slack read "<channel_id>" --limit 5`
- With `use_mcp: true`: `mcp__claude_ai_Slack__slack_read_channel(channel_id="<channel_id>", limit=5)`

**triage-detect:** Actionable messages ("could you", "review", "please", task-like) → triage item.

**health:** `kvido slack read --limit 1` — OK if non-empty.

#### Schedule
- morning: watch-channels (mentions since yesterday)
- heartbeat: watch-dm + watch-channels (high+normal)
- heartbeat-maintenance: health
- eod: skip

#### Setup
| Prerequisite | Check |
|---|---|
| slack.bot_token | `kvido config 'slack.bot_token'` returns non-empty |
| slack.dm_channel_id | `kvido config 'slack.dm_channel_id'` returns non-empty |
| sources.slack.channels or dm_channels | At least one configured |

#### Dedup Keys
- `slack:<channel>:<thread_ts>` — channel thread activity

#### Triage Detection
Actionable content in watched channels ("could you", "review", "please", task-like requests) → triage item.
