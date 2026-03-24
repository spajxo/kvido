---
name: slack
description: Use when sending Slack messages, formatting Block Kit payloads, or managing thread delivery.
tool-type: interactive
cli: kvido slack
allowed-tools: Read, Bash
user-invocable: false
---

> **Configuration:** Use `kvido config 'key'` for focus mode and batching settings.

# Slack

Slack is the primary communication channel. All messages go through `kvido slack` (wraps `slack.sh` over the Slack Web API with curl + jq and a bot token).
Heartbeat is the sole orchestrator of delivery policy; `kvido slack` is the LLM-facing Slack interface.

## Usage

Heartbeat decides whether to send a message immediately, batch it, or just log it. When sending, it calls `kvido slack` directly.

### Send a message

```bash
kvido slack send <channel> <template> [--var key=value]...
```

### Reply to a thread

```bash
kvido slack reply <channel> <thread_ts> <template> [--var key=value]...
```

### Edit a message

```bash
kvido slack edit <channel> <message_ts> <template> [--var key=value]...
```

### Read messages

```bash
kvido slack read <channel> [--limit N] [--oldest ts] [--thread ts]
```

Without `--thread`: reads channel history (`conversations.history`).
With `--thread <ts>`: reads replies in the given thread (`conversations.replies`).

### Delete a message

```bash
kvido slack delete <channel> <message_ts>
```

### Remove a reaction

```bash
kvido slack unreact <ts> <emoji> [channel]
```

Removes a reaction. Idempotent — succeeds even if reaction doesn't exist.

## Templates

In `templates/` — JSON files with `{{placeholder}}` variables. Unified format: `section` + `context`, emoji prefix by type, separator `━━━`.

| Template | Emoji | Vars | Usage |
|----------|-------|------|-------|
| `morning` | ☀️ | `date`, `briefing`, `triage_count`, `meeting_time`, `deepwork_time` | Morning briefing summary |
| `eod` | 🌙 | `date`, `summary`, `session_time`, `done_count`, `open_count` | EOD summary |
| `event` | (custom `{{emoji}}`) | `severity_bar`, `emoji`, `title`, `description`, `source`, `reference`, `timestamp` | Planner notifications, heartbeat events |
| `worker-report` | ⚙️ | `title`, `results`, `task_id`, `duration` | Worker task completion |
| `triage-item` | 📋 | `slug`, `title`, `description`, `priority`, `size`, `assignee` | Individual triage item |
| `maintenance` | 🩺 | `librarian`, `enricher`, `self_improver`, `health`, `timestamp` | Maintenance summary |
| `chat` | 💬 | `message` | General messages, chat replies |
| `digest` | (custom `{{emoji}}`) | `emoji`, `title`, `summary`, `stats` | Digest thread parent |
| `batch-header` | (custom `{{emoji}}`) | `emoji`, `title`, `summary`, `count`, `timestamp` | Batch flush thread parent |

**Emoji conventions:**
- 📋 triage, triage overflow
- ⚙️ worker report
- 🩺 maintenance
- 📊 planner notifications (use as `emoji` var in `event`)
- ☀️ morning
- 🌙 eod
- 💬 chat, general messages

## Notification Levels

| Level | Behavior |
|-------|----------|
| `silent` | Log via `kvido log add` only, no Slack message |
| `batch` | Heartbeat creates a notify TODO with pending status, delivers at next planner iteration |
| `immediate` | `kvido slack send` with the appropriate template — sent immediately |

## Threading

Flat messages as default. Threading applies in these cases:

1. **Single event** — `kvido slack send` (standalone, flat)
2. **Digest (2+ events from planner cycle)** — `kvido slack send` digest parent → `kvido slack reply` individual events into thread
3. **Batch flush** — `kvido slack send` batch-header parent → `kvido slack reply` batched items into thread
4. **Escalation of same event** — `kvido slack reply` into the original message's thread
5. **Morning/eod briefings** — standalone (never threaded)

## Focus Mode

Read `kvido config 'focus_mode'`. Unchanged — suppress, batching, after_focus_summary work identically.

## Batching

Read `kvido config 'skills.slack.batching'`. Batch notifications are managed by heartbeat via notify TODOs with pending status — flushed at planner iteration or on focus mode change.

## Auth

Bot token read via `kvido config 'slack.bot_token'`. Store the actual token in `$KVIDO_HOME/.env` as `SLACK_BOT_TOKEN=xoxb-...` and reference it from `settings.json` as `"slack.bot_token": "$SLACK_BOT_TOKEN"`.

Minimum required scopes (based on actually called API methods):

| Scope | API method |
|-------|-----------|
| `chat:write` | `chat.postMessage`, `chat.update`, `chat.delete` |
| `im:history` | `conversations.history`, `conversations.replies` (DM channel) |
| `reactions:write` | `reactions.add`, `reactions.remove` |
| `reactions:read` | `reactions.get` |

Optional (only if the assistant reads channels outside DM):
- `groups:history` — private channels
- `channels:history` — public channels
- `mpim:history` — group DM

Scopes `channels:read`, `groups:read`, `im:read`, `im:write`, `users:read` and `incoming-webhook` are not used by the assistant — do not add them.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Agent calling `kvido slack` directly | Only heartbeat calls `kvido slack`. Agents return NL output. |
| Using `ts` as `thread_ts` for replies | `thread_ts` is the parent message ts, not the reply ts |
| Sending without template | Always use a template from `templates/`. Raw text goes through `chat` template. |
| Threading by default | Flat messages for single events. Use digest threading for 2+ events per planner cycle. |
| Adding unauthorized scopes | Only `chat:write`, `im:history`, `reactions:write`, `reactions:read` are required. |
| Ignoring `kvido slack` exit code | Exit 1 = failure. Log error, don't retry silently. |

## Fallback

If `kvido slack` fails → log error, return exit 1. Slack MCP remains available as a manual fallback for search.
