---
name: slack
description: Use when sending Slack messages, formatting Block Kit payloads, or managing thread delivery.
tool-type: interactive
cli: slack.sh
allowed-tools: Read, Bash
user-invocable: false
---

**Language:** Communicate in the language set in memory/persona.md. Default: English.

> **Configuration:** Read `.claude/kvido.local.md` for focus mode and batching settings.

# Slack

Slack is the primary communication channel. All messages go through the `slack.sh` wrapper over the Slack Web API (curl + jq) with a bot token.
Heartbeat is the sole orchestrator of delivery policy; `slack.sh` is the LLM-facing Slack interface.

## Usage

Heartbeat decides whether to send a message immediately, batch it, or just log it. When sending, it calls `slack.sh` directly.

### Send a message

```bash
skills/slack/slack.sh send <channel> <template> [--var key=value]...
```

### Reply to a thread

```bash
skills/slack/slack.sh reply <channel> <thread_ts> <template> [--var key=value]...
```

### Edit a message

```bash
skills/slack/slack.sh edit <channel> <message_ts> <template> [--var key=value]...
```

### Read messages

```bash
skills/slack/slack.sh read <channel> [--limit N] [--oldest ts] [--thread ts]
```

Without `--thread`: reads channel history (`conversations.history`).
With `--thread <ts>`: reads replies in the given thread (`conversations.replies`).

### Delete a message

```bash
skills/slack/slack.sh delete <channel> <message_ts>
```

## Templates

In `templates/` — JSON files with `{{placeholder}}` variables. Unified format: `section` + `context`, emoji prefix by type, separator `━━━`.

| Template | Emoji | Vars | Usage |
|----------|-------|------|-------|
| `morning` | ☀️ | `date`, `briefing`, `triage_count`, `meeting_time`, `deepwork_time` | Morning briefing summary |
| `eod` | 🌙 | `date`, `summary`, `session_time`, `done_count`, `open_count` | EOD summary |
| `event` | (custom `{{emoji}}`) | `emoji`, `title`, `description`, `source`, `reference`, `timestamp` | Planner notifications, heartbeat events |
| `worker-report` | 🔧 | `title`, `results`, `task_id`, `duration` | Worker task completion |
| `triage-item` | 📋 | `issue`, `title`, `description`, `priority`, `size`, `assignee`, `issue_url` | Individual triage item |
| `maintenance` | 🔧 | `librarian`, `enricher`, `self_improver`, `health`, `timestamp` | Maintenance summary |
| `chat` | 💬 | `message` | General messages, chat replies |

**Emoji conventions:**
- 📋 triage, triage overflow
- 🔧 worker report, maintenance
- 📊 planner notifications (use as `emoji` var in `event`)
- ☀️ morning
- 🌙 eod
- 💬 chat, general messages

## Notification Levels

| Level | Behavior |
|-------|----------|
| `silent` | Write to `state/today.md` only, no Slack message |
| `batch` | Heartbeat creates a notify TODO with pending status, delivers at next full heartbeat |
| `immediate` | `slack.sh send` with the appropriate template — sent immediately |

## Threading

Flat messages as default. Thread only on escalation:
1. First notification → `slack.sh send` → save `ts` to `reported` entry
2. Escalation of the same event → `slack.sh reply` into the original message's thread

## Focus Mode

Read `.claude/kvido.local.md` → `focus_mode`. Unchanged — suppress, batching, after_focus_summary work identically.

## Batching

Read `.claude/kvido.local.md` → `batching`. Batch notifications are managed by heartbeat via notify TODOs with pending status — flushed at full heartbeat or on focus mode change.

## Auth

`SLACK_BOT_TOKEN` (xoxb) from `.env`.

Minimum required scopes (based on actually called API methods):

| Scope | API method |
|-------|-----------|
| `chat:write` | `chat.postMessage`, `chat.update`, `chat.delete` |
| `im:history` | `conversations.history`, `conversations.replies` (DM channel) |
| `reactions:write` | `reactions.add` |
| `reactions:read` | `reactions.get` |

Optional (only if the assistant reads channels outside DM):
- `groups:history` — private channels
- `channels:history` — public channels
- `mpim:history` — group DM

Scopes `channels:read`, `groups:read`, `im:read`, `im:write`, `users:read` and `incoming-webhook` are not used by the assistant — do not add them.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Agent calling `slack.sh` directly | Only heartbeat calls `slack.sh`. Agents return NL output. |
| Using `ts` as `thread_ts` for replies | `thread_ts` is the parent message ts, not the reply ts |
| Sending without template | Always use a template from `templates/`. Raw text goes through `chat` template. |
| Threading by default | Flat messages are default. Thread only for escalation of same event. |
| Adding unauthorized scopes | Only `chat:write`, `im:history`, `reactions:write`, `reactions:read` are required. |
| Ignoring `slack.sh` exit code | Exit 1 = failure. Log error, don't retry silently. |

## Fallback

If `slack.sh` fails → log error, return exit 1. Slack MCP remains available as a manual fallback for search.
