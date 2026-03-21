---
name: source-slack
description: Use when monitoring Slack DM inbox, watched channels, or detecting new mentions.
allowed-tools: Read, Bash, mcp__claude_ai_Slack__slack_search_public_and_private
user-invocable: false
---

> **Configuration:** Via `skills/config.sh` (`sources.slack.*` keys). DM credentials from `.env`.

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Slack

> **Note:** This source plugin is always invoked by the core kvido planner/heartbeat agent. All `skills/slack/` and `skills/heartbeat/` paths refer to scripts in the core kvido plugin (resolved from the agent's working context).

Reading via `slack.sh read` (Slack Web API). Search via Slack MCP (requires user context).

## Capabilities

### watch-dm

```bash
skills/slack/slack.sh read --limit 5
```

Output: JSON array. Filter via `jq`:
- `.[] | select(.user == "$SLACK_USER_ID")` — messages from the user
- `.[] | select(.ts > "$last_dm_ts")` — newer than last scan

List DM channels to monitor:
```bash
skills/config.sh --keys 'sources.slack.dm_channels'
```
For each entry where `channel_id` is defined (skip entries without `channel_id`):
```bash
CHANNEL_ID=$(skills/config.sh "sources.slack.dm_channels.<name>.channel_id")
skills/slack/slack.sh read "$CHANNEL_ID" --limit 5 --oldest "$last_dm_ts"
```

For new messages from other users (not from `SLACK_USER_ID`) determine notification level:

| Level | When | Action |
|-------|------|--------|
| `silent` | FYI, informational messages | Log: `- **HH:MM** [dm/<name>] <truncated text>` to `state/today.md` |
| `batch` | Less urgent, can wait | Return in NL output with `Event (batch):` prefix — heartbeat delivers at next full heartbeat |
| `immediate` | Requires response — question, request, blocking someone | `slack.sh send event --var emoji="💬" --var title="DM from <name>" --var description="<text max 100 chars>" --var source="Slack DM" --var reference="open DM" --var timestamp="<HH:MM>"` |

Decide based on context — who's writing, what they need, how urgent it is.

Always update timestamp after processing:
```bash
skills/heartbeat/heartbeat-state.sh set last_dm_ts "<newest ts>"
```

### watch-channels

List watched channels via `skills/config.sh --keys 'sources.slack.channels'`. For channels with `priority: high` and `priority: normal` where `channel_id` is set:

**Transport selection:**
- Channel without `use_mcp` (or `use_mcp: false`) → use `slack.sh read` (Bot token, standard):
  ```bash
  skills/slack/slack.sh read "<channel_id>" --limit 5
  ```
- Channel with `use_mcp: true` → use Slack MCP `slack_read_channel` (reads as user — for channels where bot has no access or user context is required):
  ```
  mcp__claude_ai_Slack__slack_read_channel(channel_id="<channel_id>", limit=5)
  ```

For channels without `channel_id` → skip (or add ID to `.claude/kvido.local.md`).

For channels with `watch_for: marvin_qa`: analyze messages from the perspective of Marvin AI bot quality.
Signals to report (desktop level):
- User complains about bot response
- Bot did not respond or responded with empty output
- User repeats the same question
Report format: `[ds-parking/marvin] <description of issue or opportunity>`

After analysis, write findings to `state/today.md` as a separate section `## Marvin QA`.
If the section does not yet exist in today.md, append it at the end of the file.
If it exists, append new findings below the existing section content.
Format for each finding: `- **HH:MM** <description of issue or opportunity>`
If no new findings were found, write nothing to today.md (silent output).

### triage-detect

Slack messages with actionable content: "could you", "we need", "review", "take a look", "deadline", "please"
→ triage item: `- [ ] description (from @author in #channel) #source:slack #added:YYYY-MM-DD`

### health

```bash
skills/slack/slack.sh read --limit 1
```
OK if returns non-empty result.

## Schedule

- morning: watch-channels (mentions since yesterday)
- heartbeat-quick: watch-dm
- heartbeat-full: watch-dm + watch-channels (high+normal)
- heartbeat-maintenance: health
- eod: skip
