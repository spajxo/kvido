---
name: source-calendar
description: Use when fetching today's calendar events or generating meeting reminders.
allowed-tools: Read, Bash, mcp__claude_ai_Google_Calendar__gcal_list_events
user-invocable: false
---

> **Configuration:** Via `kvido config` (`sources.calendar.*` keys).

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Calendar

## Capabilities

### fetch
Run `fetch.sh [YYYY-MM-DD]` for the given day.
Returns pre-categorized data per settings.json `categories` + total meeting time and free deep-work time.

**MCP fallback:** If fetch.sh exits with code 10 (`gws` not available), use Google Calendar MCP directly:

1. Call `mcp__claude_ai_Google_Calendar__gcal_list_events(calendarId="primary", timeMin="<date>T00:00:00Z", timeMax="<date>T23:59:59Z", singleEvents=true, orderBy="startTime")`
2. Categorize events using config: `kvido config --keys 'sources.calendar.categories'`
3. Format output: `- HH:MM–HH:MM — Summary [category]` per event, then total count

### watch
If `kvido state get planner.schedule` returns a `## Today's Schedule` section (written by morning run), use existing data.
Otherwise run `fetch.sh`. If it returns exit code 10, follow the MCP fallback from the fetch section above.
Filter meetings starting in the next 60 min → reminder event.

## Schedule
- morning: fetch (today), write schedule via `kvido state set planner.schedule "<text>"`
- heartbeat-quick: skip
- heartbeat-full: watch (meetings in next 60 min)
- heartbeat-maintenance: skip
- eod: skip (schedule data already stored via kvido state)
