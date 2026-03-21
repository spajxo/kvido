---
name: source-sessions
description: Use when parsing Claude Code session data for time tracking or message extraction.
allowed-tools: Read, Bash
user-invocable: false
---

> **Configuration:** Read `.claude/kvido.local.md` for idle threshold.

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Sessions

## Capabilities

### fetch
```bash
skills/source-sessions/fetch.sh [YYYY-MM-DD]
```
Default: yesterday. Parses JSONL session files in `~/.claude/projects/`.

Output per project:
```
=== group/project (2 sessions, ~1h 30m) ===
  Tickets: PROJ-123, PROJ-456
```

### fetch-messages
```bash
skills/source-sessions/fetch-messages.sh [YYYY-MM-DD]
```
Default: today. Extracts user messages and assistant retry/error patterns from JSONL sessions.

Output: plain text with session markers, max ~2000 lines (newest first).
```
=== project/repo (session-id) ===
USER: message from user
RETRY: assistant correcting previous output...
```

Intended for the self-improver agent — pre-filtered input for pattern detection.

## Schedule
- morning: fetch (yesterday)
- heartbeat-quick: skip
- heartbeat-full: skip
- heartbeat-maintenance: fetch-messages (today) — for self-improver agent
- eod: fetch (today)
