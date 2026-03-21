---
name: source-gmail
description: Use when fetching unread emails or watching for priority sender messages.
allowed-tools: Read, Bash
user-invocable: false
---

> **Configuration:** Read `.claude/kvido.local.md` for filters and priority senders.

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Gmail

## Capabilities

### fetch
Run `fetch.sh`. Returns formatted summary of unread emails filtered per kvido.local.md.
Output: human-readable summary — from, subject, date, snippet. Max `max_results` items.

### watch
Quick check of unread count from priority senders since last check.
If new important email (from priority_senders) → emit event for heartbeat.
Event key pattern: `email:<message_id>` — for dedup in heartbeat-state.json.

### health
```bash
gws gmail users getProfile me
```
Result to `state/source-health.json` under key `gmail`.

## Schedule
- morning: `fetch` (unread inbox)
- heartbeat-quick: skip
- heartbeat-full: `watch` (new since last check)
- heartbeat-maintenance: skip
- eod: skip
