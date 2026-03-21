# kvido

Personal AI workflow assistant for Claude Code — heartbeat, planner, worker, triage.

## What is kvido

Kvido is a Claude Code plugin — rezidentni asistent ktery bezi ve vlastni workspace slozce. Monitoruje vase pracovni nastroje (Jira, GitLab, Slack, Calendar, Gmail) a komunikuje s vami pres Slack DM.

- **Heartbeat** — periodic background monitoring, chat dispatch, worker orchestration
- **Planner** — change detection, triage, notifications, daily context
- **Worker** — async task queue via local markdown files
- **Morning / EOD** — daily briefing and end-of-day journal

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| jq | Yes | JSON parsing |
| glab | No | GitLab monitoring (MR status, git activity) |
| acli | No | Jira integration |
| gws | No | Google Workspace (Gmail, Calendar) |

## Installation

1. Vytvor si workspace slozku:
   ```bash
   mkdir ~/kvido && cd ~/kvido
   git init
   ```

2. Nainstaluj plugin lokalne:
   ```bash
   claude plugin install kvido --scope local
   ```

3. Spust Claude Code a proved onboarding:
   ```bash
   claude
   ```
   Uvnitr session spust `/setup` — vytvori runtime adresare (`state/`, `memory/`), config sablony (`.claude/kvido.local.md`, `.env`), `.gitignore` a `CLAUDE.md`.

4. Vyplň config (`.claude/kvido.local.md`) a env promenne (`.env`) — `/setup` te provede.

## Daily usage

```bash
cd ~/kvido && claude
```

- **Rano:** rekni "dobre rano" → spusti ranní briefing
- **Heartbeat:** rekni "spust heartbeat" nebo `/heartbeat` → nastavi cron loop (default 10min), monitoruje zdroje, odpovida na Slack DM
- **Konec dne:** rekni "koncim" nebo `/eod` → denni journal, worklog check
- **Pauza:** rekni "jdu spat" → uspí heartbeat do rana

Heartbeat bezi na pozadi — muzete nechat terminal otevreny a kvido pracuje autonomne.

## Structure

```
kvido/                        # vase workspace slozka
├── .claude/kvido.local.md    # konfigurace zdroju a skillu (gitignored)
├── .env                      # Slack tokens, IDs (gitignored)
├── state/                    # ephemeral runtime (gitignored)
│   └── tasks/                # work queue (triage/, todo/, in-progress/, done/, ...)
├── memory/                   # persistent kontext (gitignored)
└── CLAUDE.md                 # instrukce pro Claude Code
```

Plugin samotny (toto repo):

```
kvido-plugin/
├── .claude-plugin/plugin.json
├── skills/                   # SKILL.md + bash helpers
├── agents/                   # subagent definitions
├── commands/                 # slash commands (/morning, /eod, /heartbeat, /triage, /setup)
└── hooks/                    # pre-compact state injection
```

## Status

Version 0.1.0 — plugin packaged with full content.
