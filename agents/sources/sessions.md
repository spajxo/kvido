### Sessions

> Config: `sessions.*` keys. No external dependencies.

#### Capabilities

**fetch:**
```bash
kvido sessions [YYYY-MM-DD]
```
Default: yesterday. Parses JSONL session files. Output per project:
```
=== group/project (2 sessions, ~1h 30m) ===
  Tickets: PROJ-123, PROJ-456
```

**fetch-messages:**
```bash
kvido sessions-messages [YYYY-MM-DD]
```
Default: today. Extracts user messages + retry patterns. Max ~2000 lines. For self-improver agent.

#### Schedule
- morning: fetch (yesterday)
- heartbeat: skip
- heartbeat-maintenance: fetch-messages (today) — for self-improver agent
- eod: fetch (today)
