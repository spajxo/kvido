---
name: source-sessions
description: Use when parsing Claude Code session data for time tracking or message extraction.
allowed-tools: Read, Bash
user-invocable: false
---

> **Konfigurace:** Přečti `.claude/kvido.local.md` pro idle threshold.

# Source: Sessions

## Capabilities

### fetch
```bash
skills/source-sessions/fetch.sh [YYYY-MM-DD]
```
Default: včera. Parsuje JSONL session soubory v `~/.claude/projects/`.

Output per projekt:
```
=== group/project (2 sessions, ~1h 30m) ===
  Tickets: PROJ-123, PROJ-456
```

### fetch-messages
```bash
skills/source-sessions/fetch-messages.sh [YYYY-MM-DD]
```
Default: dnes. Extrahuje user messages a assistant retry/error vzory z JSONL sessions.

Output: plain text se session markery, max ~2000 řádků (nejnovější první).
```
=== projekt/repo (session-id) ===
USER: zpráva od uživatele
RETRY: assistant opravuje předchozí výstup...
```

Určeno pro self-improver agenta — předfiltrovaný vstup pro detekci vzorů.

## Schedule
- morning: fetch (včera)
- heartbeat-quick: skip
- heartbeat-full: skip
- heartbeat-maintenance: fetch-messages (dnes) — pro self-improver agent
- eod: fetch (dnes)
