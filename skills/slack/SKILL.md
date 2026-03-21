---
name: slack
description: Use when sending Slack messages, formatting Block Kit payloads, or managing thread delivery.
tool-type: interactive
cli: slack.sh
allowed-tools: Read, Bash
user-invocable: false
---

> **Konfigurace:** Přečti `.claude/kvido.local.md` pro focus mode a batching nastavení.

# Slack

Slack je primární komunikační kanál. Všechny zprávy jdou přes `slack.sh` wrapper nad Slack Web API (curl + jq) s bot tokenem.
Heartbeat je jediný orchestrátor delivery policy; `slack.sh` je LLM-facing Slack interface.

## Použití

Heartbeat sám rozhoduje, zda zprávu poslat hned, batchnout nebo jen zalogovat. Pokud se posílá, používá přímo `slack.sh`.

### Odeslání zprávy

```bash
skills/slack/slack.sh send <channel> <template> [--var key=value]...
```

### Reply do vlákna

```bash
skills/slack/slack.sh reply <channel> <thread_ts> <template> [--var key=value]...
```

### Editace zprávy

```bash
skills/slack/slack.sh edit <channel> <message_ts> <template> [--var key=value]...
```

### Čtení zpráv

```bash
skills/slack/slack.sh read <channel> [--limit N] [--oldest ts] [--thread ts]
```

Bez `--thread`: čte channel history (`conversations.history`).
S `--thread <ts>`: čte replies v daném vlákně (`conversations.replies`).

### Smazání zprávy

```bash
skills/slack/slack.sh delete <channel> <message_ts>
```

## Šablony

V `templates/` — JSON soubory s `{{placeholder}}` proměnnými. Unified formát: `section` + `context`, emoji prefix dle typu, separátor `━━━`.

| Šablona | Emoji | Vars | Použití |
|---------|-------|------|---------|
| `morning` | ☀️ | `date`, `briefing`, `triage_count`, `meeting_time`, `deepwork_time` | Morning briefing souhrn |
| `eod` | 🌙 | `date`, `summary`, `session_time`, `done_count`, `open_count` | EOD souhrn |
| `event` | (custom `{{emoji}}`) | `emoji`, `title`, `description`, `source`, `reference`, `timestamp` | Planner notifikace, heartbeat events |
| `worker-report` | 🔧 | `title`, `results`, `task_id`, `duration` | Worker task dokončení |
| `triage-item` | 📋 | `issue`, `title`, `description`, `priority`, `size`, `assignee`, `issue_url` | Individuální triage položka |
| `maintenance` | 🔧 | `librarian`, `enricher`, `self_improver`, `health`, `timestamp` | Maintenance souhrn |
| `chat` | 💬 | `message` | Obecné zprávy, chat odpovědi |

**Emoji konvence:**
- 📋 triage, triage overflow
- 🔧 worker report, maintenance
- 📊 planner notifikace (použij jako `emoji` var v `event`)
- ☀️ morning
- 🌙 eod
- 💬 chat, obecné zprávy

## Úrovně notifikací

| Úroveň | Chování |
|---------|---------|
| `silent` | Jen zápis do `state/today.md`, žádná Slack zpráva |
| `batch` | Heartbeat vytvoří notify TODO s pending statusem, doručí při dalším full heartbeatu |
| `immediate` | `slack.sh send` s odpovídající šablonou — okamžitě |

## Threading

Flat zprávy jako default. Thread jen při eskalaci:
1. První notifikace → `slack.sh send` → uložit `ts` do `reported` entry
2. Eskalace téhož eventu → `slack.sh reply` do vlákna původní zprávy

## Focus Mode

Přečti `.claude/kvido.local.md` → `focus_mode`. Beze změny — suppress, batching, after_focus_summary fungují identicky.

## Batching

Přečti `.claude/kvido.local.md` → `batching`. Batch notifikace řídí heartbeat přes notify TODO s pending statusem — flush při full heartbeatu nebo změně focus mode.

## Auth

`SLACK_BOT_TOKEN` (xoxb) z `.env`.

Minimální required scopes (dle skutečně volaných API metod):

| Scope | API metoda |
|-------|-----------|
| `chat:write` | `chat.postMessage`, `chat.update`, `chat.delete` |
| `im:history` | `conversations.history`, `conversations.replies` (DM kanál) |
| `reactions:write` | `reactions.add` |
| `reactions:read` | `reactions.get` |

Volitelné (jen pokud asistent čte kanály mimo DM):
- `groups:history` — soukromé kanály
- `channels:history` — veřejné kanály
- `mpim:history` — group DM

Scopes `channels:read`, `groups:read`, `im:read`, `im:write`, `users:read` a `incoming-webhook` asistent nepoužívá — nepřidávat.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Agent calling `slack.sh` directly | Only heartbeat calls `slack.sh`. Agents return NL output. |
| Using `ts` as `thread_ts` for replies | `thread_ts` is the parent message ts, not the reply ts |
| Sending without template | Always use a template from `templates/`. Raw text goes through `chat` template. |
| Threading by default | Flat messages are default. Thread only for escalation of same event. |
| Adding unauthorized scopes | Only `chat:write`, `im:history`, `reactions:write`, `reactions:read` are required. |
| Ignoring `slack.sh` exit code | Exit 1 = failure. Log error, don't retry silently. |

## Fallback

Pokud `slack.sh` selže → loguj error, vrať exit 1. Slack MCP zůstává dostupný jako manuální fallback pro search.
