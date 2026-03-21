---
name: source-calendar
description: Use when fetching today's calendar events or generating meeting reminders.
allowed-tools: Read, Bash
user-invocable: false
---

> **Konfigurace:** Přečti `.claude/kvido.local.md` pro event kategorizaci.

# Source: Calendar

## Capabilities

### fetch
Spusť `fetch.sh [YYYY-MM-DD]` pro daný den.
Vrátí pre-kategorizovaná data dle kvido.local.md `categories` + celkový meeting čas a free deep-work čas.

### watch
Pokud `state/today.md` obsahuje Today's Schedule, použij existující data.
Jinak spusť `fetch.sh` a filtruj meetingy začínající v příštích 60 min → reminder event.

## Schedule
- morning: fetch (dnešek)
- heartbeat-quick: skip
- heartbeat-full: watch (meetingy v příštích 60 min)
- heartbeat-maintenance: skip
- eod: skip (data už v today.md)
