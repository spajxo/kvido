### Calendar

> Config: `calendar.*` keys. Requires: `gws` CLI or Google Calendar MCP.

#### Capabilities

**fetch:**
```bash
kvido fetch-calendar [YYYY-MM-DD]
```
Returns categorized events + total meeting/free-work time.

**MCP fallback (exit 10):**
1. Call `mcp__claude_ai_Google_Calendar__gcal_list_events(calendarId="primary", timeMin="<date>T00:00:00Z", timeMax="<date>T23:59:59Z", singleEvents=true, orderBy="startTime")`
2. Categorize using `kvido config --keys 'calendar.categories'`
3. Format: `- HH:MM–HH:MM — Summary [category]`

**watch:** If `kvido state get planner.schedule` has schedule data, use it. Otherwise run fetch. Filter meetings in next 60 min → reminder event.

#### Schedule
- morning: fetch (today), write via `kvido state set planner.schedule "<text>"`
- heartbeat-quick: skip
- heartbeat-full: watch (meetings in next 60 min)
- heartbeat-maintenance: skip
- eod: skip

#### Setup
| Prerequisite | Check |
|---|---|
| Google Calendar MCP | MCP available |
