---
name: source-slack
description: Use when monitoring Slack DM inbox, watched channels, or detecting new mentions.
allowed-tools: Read, Bash, mcp__claude_ai_Slack__slack_search_public_and_private
user-invocable: false
---

> **Configuration:** Via `kvido config` (`sources.slack.*` keys). Credentials (`slack.bot_token`, `slack.dm_channel_id`) resolved from `.env` references in `settings.json`.

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Slack

> **Note:** This source plugin is always invoked by the core kvido planner/heartbeat agent. All `skills/slack/` and `skills/heartbeat/` paths refer to scripts in the core kvido plugin (resolved from the agent's working context).

Reading via `kvido slack read` (Slack Web API). Search via Slack MCP (requires user context).

## Capabilities

### watch-dm

```bash
kvido slack read --limit 5
```

Output: JSON array. Filter via `jq`:
- `.[] | select(.user == "$SLACK_USER_ID")` — messages from the user
- `.[] | select(.ts > "$last_dm_ts")` — newer than last scan

List DM channels to monitor:
```bash
kvido config --keys 'sources.slack.dm_channels'
```
For each entry where `channel_id` is defined (skip entries without `channel_id`):
```bash
CHANNEL_ID=$(kvido config "sources.slack.dm_channels.<name>.channel_id")
kvido slack read "$CHANNEL_ID" --limit 5 --oldest "$last_dm_ts"
```

For new messages from other users (not from `SLACK_USER_ID`) determine notification level:

| Level | When | Action |
|-------|------|--------|
| `silent` | FYI, informational messages | `kvido log add chat silent --message "[dm/<name>] <truncated text>"` |
| `batch` | Less urgent, can wait | Return in NL output with `Event (batch):` prefix — heartbeat delivers at next planner iteration |
| `immediate` | Requires response — question, request, blocking someone | `kvido slack send event --var emoji="💬" --var title="DM from <name>" --var description="<text max 100 chars>" --var source="Slack DM" --var reference="open DM" --var timestamp="<HH:MM>"` |

Decide based on context — who's writing, what they need, how urgent it is.

Always update timestamp after processing:
```bash
kvido heartbeat-state set last_dm_ts "<newest ts>"
```

### watch-channels

List watched channels via `kvido config --keys 'sources.slack.channels'`. For channels with `priority: high` and `priority: normal` where `channel_id` is set:

**Transport selection:**
- Channel without `use_mcp` (or `use_mcp: false`) → use `kvido slack read` (Bot token, standard):
  ```bash
  kvido slack read "<channel_id>" --limit 5
  ```
- Channel with `use_mcp: true` → use Slack MCP `slack_read_channel` (reads as user — for channels where bot has no access or user context is required):
  ```
  mcp__claude_ai_Slack__slack_read_channel(channel_id="<channel_id>", limit=5)
  ```

For channels without `channel_id` → skip (or add ID to `settings.json`).

For channels with `watch_for: marvin_qa`: analyze messages from the perspective of Marvin AI bot quality.
Signals to report (desktop level):
- User complains about bot response
- Bot did not respond or responded with empty output
- User repeats the same question
Report format: `[ds-parking/marvin] <description of issue or opportunity>`

After analysis, log each finding via:
```bash
kvido log add planner marvin-qa --message "<description of issue or opportunity>"
```
If no new findings were found, log nothing (silent output).

### triage-detect

Slack messages with actionable content: "could you", "we need", "review", "take a look", "deadline", "please"
→ triage item: `- [ ] description (from @author in #channel) #source:slack #added:YYYY-MM-DD`

### health

```bash
kvido slack read --limit 1
```
OK if returns non-empty result.

## Schedule

- morning: watch-channels (mentions since yesterday)
- heartbeat: watch-dm + watch-channels (high+normal)
- heartbeat-maintenance: health
- eod: skip
