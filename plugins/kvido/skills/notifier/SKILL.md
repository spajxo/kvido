---
name: notifier
description: Single gateway to the user — formats, classifies urgency, delivers to Slack.
allowed-tools: Read, Glob, Grep, Bash, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Google_Calendar__gcal_list_events
user-invocable: false
---

# Notifier

Single gateway for all user-facing communication. Reads events from the bus, decides urgency, formats messages, and delivers to Slack directly. Does NOT fetch data, does NOT schedule tasks, does NOT dispatch agents.

---

## Step 1: Load Context

1. Read dispatch events that triggered this run (passed as context by heartbeat)
2. Load notification rules: `kvido context planner`
3. Read current focus: `kvido current get`
4. Check focus mode: `kvido config 'focus_mode'` and check calendar for active focus events

---

## Step 2: Process Change Events

Read unprocessed change events from the bus:

```bash
kvido event read --consumer notifier --type 'change.*'
```

For each `change.detected` event, decide:

### Urgency classification

| Factor | Effect |
|--------|--------|
| `kind` = `mr_review_requested` | Bump to `high` |
| `kind` = `calendar_event` (< 15min) | `high` |
| Focus mode active | Suppress `high` → `batch` |
| Night hours | Suppress `high` → `batch` |
| `kind` = `mr_updated` | `normal` |
| `kind` = `slack_mention` | `normal` |
| Everything else | `low` |

### Severity

| Urgency | Severity |
|---------|----------|
| high | `:red_circle:` |
| normal | `:large_yellow_circle:` |
| low | `:large_green_circle:` |

### Batching

- `high` urgency → emit `notification.event`, deliver immediately
- `normal` urgency → emit `notification.event`, deliver immediately
- `low` urgency → collect into batch, emit `notification.batch` at the end

---

## Step 3: Process Source Errors

Read source error events:

```bash
kvido event read --consumer notifier --type 'source.error'
```

For each `source.error`, emit:

```bash
kvido event emit notification.event \
  --data '{"title":":warning: <source> fetch failed","desc":"<error>","source":"<source>","ref":"none","urgency":"normal","severity":":large_yellow_circle:"}' \
  --producer notifier
```

---

## Step 4: Process Triage (if dispatch.triage received)

Check if `dispatch.triage` event was received. If so:

```bash
kvido task list triage
```

For each triage task (max 3):
1. Read detail: `kvido task read <slug>`
2. Parse CREATED_AT/UPDATED_AT, compute age
3. If age > 43200 (12h) → stale

For each selected task:
```bash
kvido event emit notification.triage \
  --data '{"slug":"<slug>","title":"<title>","priority":"<p>","size":"<s>","stale":false}' \
  --producer notifier
```

Write note: `kvido task note <slug> "Triage: sent for approval."`

---

## Step 5: Process Briefing (if dispatch.briefing received)

Check if `dispatch.briefing` event was received. Read its `schedule` field ("morning" or "eod").

Compose briefing from:
- Source events in the bus (`source.fetched`, `change.detected`)
- Current focus (`kvido current get`)
- Calendar (`gcal_list_events` if available)
- Recent activity (`kvido log list --today --format human --limit 20`)

```bash
kvido event emit notification.briefing \
  --data '{"schedule":"morning","sections":[{"title":"Calendar","content":"..."},{"title":"MRs","content":"..."}]}' \
  --producer notifier
```

---

## Step 6: Deliver to Slack

Read all notification events emitted in this run:

```bash
kvido event read --consumer notifier --type 'notification.*'
```

For each notification event, deliver via `kvido slack`:

| Type | Template | Delivery |
|------|----------|----------|
| `notification.event` | `event` | `kvido slack send dm event --var title="..." --var desc="..." --var severity_bar="..."` |
| `notification.batch` | `event` | One message per batch |
| `notification.briefing` | `briefing` (or `event` fallback) | `kvido slack send dm briefing --var schedule="..." --var content="..."` |
| `notification.triage` | `triage-item` | `kvido slack send dm triage-item --var slug="..." --var title="..."` — save returned `ts` to task note |
| `notification.reminder` | `event` | `kvido slack send dm event --var title="Reminder" --var desc="..."` |

After all deliveries, ack all events:

```bash
kvido event ack --consumer notifier
```

---

## Step 7: Save State

Log: `kvido log add notifier notify --message "<N> notifications delivered"`

---

## Output Format

Brief status line for logging:

```
Notifier: delivered 3 events (1 high, 2 normal), 1 triage, morning briefing
```

Or:

```
Notifier: no notifications
```

---

## Critical Rules

- **Single gateway.** All user-facing communication goes through notifier.
- **Urgency is notifier's decision.** Based on change type + focus mode + calendar + time.
- **Focus mode suppresses.** High → batch when focus event is active.
- **Max 3 triage items per run.**
- **Always include URLs.** Full clickable URL for every MR, issue, email.
- **Deliver directly.** Use `kvido slack send/reply` — no intermediary.
- **Ack after delivery.** Only advance cursor after successful Slack delivery.
