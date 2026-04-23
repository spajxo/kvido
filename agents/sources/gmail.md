### Gmail

> Config: `gmail.*` keys. Requires: `gws` CLI or Gmail MCP.

#### Capabilities

**fetch:**
```bash
kvido fetch-gmail
```
Returns formatted summary of unread emails (from, subject, date, snippet).

**MCP fallback (exit 10):**
1. Read: `kvido config 'gmail.watch_query'` and `kvido config 'gmail.max_results'`
2. Call `mcp__claude_ai_Gmail__gmail_search_messages(query="<watch_query>", max_results=<max_results>)`
3. For each: `mcp__claude_ai_Gmail__gmail_read_message(message_id="<id>")`
4. Format: `- From: ... / Subject: ... / Date: ... / Preview: ...`

**watch:** Quick check of unread from priority senders. Dedup key: `email:<message_id>`.

**health:** `gws gmail users getProfile me` → set status via `kvido state`.

#### Schedule
- morning: fetch (unread inbox)
- heartbeat: watch (new since last check)
- heartbeat-maintenance: skip
- eod: skip

#### Setup
| Prerequisite | Check |
|---|---|
| gws or Gmail MCP | `command -v gws` or MCP available |
| gmail.watch_query | `kvido config 'gmail.watch_query'` returns non-empty |
