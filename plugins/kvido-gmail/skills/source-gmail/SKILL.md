---
name: source-gmail
description: Use when fetching unread emails or watching for priority sender messages.
allowed-tools: Read, Bash, mcp__claude_ai_Gmail__gmail_search_messages, mcp__claude_ai_Gmail__gmail_read_message
user-invocable: false
---

> **Configuration:** Via `kvido config` (`sources.gmail.*` keys).

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Gmail

## Capabilities

### fetch
Run `fetch.sh`. Returns formatted summary of unread emails filtered per config.
Output: human-readable summary — from, subject, date, snippet. Max `max_results` items.

**MCP fallback:** If fetch.sh exits with code 10 (`gws` not available), use Gmail MCP directly:

1. Read config: `kvido config 'sources.gmail.watch_query'` and `kvido config 'sources.gmail.max_results'`
2. Call `mcp__claude_ai_Gmail__gmail_search_messages(query="<watch_query>", max_results=<max_results>)`
3. For each message, call `mcp__claude_ai_Gmail__gmail_read_message(message_id="<id>")`
4. Format output: `- From: ... / Subject: ... / Date: ... / Preview: ...` per message

### watch
Quick check of unread count from priority senders since last check.
If `gws` not available, use the MCP fallback from the fetch section above with a narrower query.
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
