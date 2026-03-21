---
name: source-calendar
description: Use when fetching today's calendar events or generating meeting reminders.
allowed-tools: Read, Bash
user-invocable: false
---

> **Configuration:** Via `skills/config.sh` (`sources.calendar.*` keys).

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Calendar

## Capabilities

### fetch
Run `fetch.sh [YYYY-MM-DD]` for the given day.
Returns pre-categorized data per kvido.local.md `categories` + total meeting time and free deep-work time.

### watch
If `state/today.md` contains Today's Schedule, use existing data.
Otherwise run `fetch.sh` and filter meetings starting in the next 60 min → reminder event.

## Schedule
- morning: fetch (today)
- heartbeat-quick: skip
- heartbeat-full: watch (meetings in next 60 min)
- heartbeat-maintenance: skip
- eod: skip (data already in today.md)
