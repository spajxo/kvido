---
name: morning
description: Ranní briefing — přehled včerejší práce, overnight změn, dnešního kalendáře a doporučení. Spouštěj při ranním pozdravu nebo manuálně přes /morning.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel
---

# Morning Briefing

Postupuj krok za krokem. Buď stručný. Nepřeskakuj kroky.

## Tone Guidelines

Tón a styl dle `memory/persona.md` (sekce Morning). Pokud persona neexistuje, buď stručný a věcný.

---

## Step 1: Load Context

### Activity log rotace

Rotuj včerejší activity log do archivu:
```bash
mkdir -p state/archive
YESTERDAY=$(date -d yesterday +%Y-%m-%d)
if [[ -f state/activity-log.jsonl ]]; then
  mv state/activity-log.jsonl "state/archive/activity-log-${YESTERDAY}.jsonl"
fi
# Smazat archivy starší 7 dní
find state/archive -name "activity-log-*.jsonl" -mtime +7 -delete 2>/dev/null || true
```

### Load state

Přečti `state/current.md`. Poznamenej si Active Focus, WIP, Blockers, Parked, Notes for Tomorrow.

Přečti `memory/memory.md` pro dlouhodobý kontext.

List files v `memory/journal/`. Pokud existují, přečti nejnovější (nejvyšší datum v názvu). Poznamenej si co se včera dělalo a co zůstalo otevřené.

---

## Step 2: Gather Fresh Data

Zjisti včerejší datum (YYYY-MM-DD).

Spusť source skills pro morning data:
- `skills/source-gitlab/fetch-activity.sh <včerejší-datum>` + `skills/source-gitlab/fetch-mrs.sh`
- `skills/source-sessions/fetch.sh <včerejší-datum>`
- `skills/source-jira/fetch.sh`
- `skills/source-slack/SKILL.md` → watch-channels + search overnight mentions
- `skills/source-calendar/fetch.sh`
- `skills/source-gmail/fetch.sh`

Datum předej jako literal string (ne command substitution).

Extrahuj: aktivní repo, délky sessions, dotčené úkoly, MR status.

---

## Step 3: Query External Sources

Spusť všechny dotazy před syntézou.

### Jira

Jira data jsou součástí gather morning režimu (source-jira fetch).
Zaznamenej klíče, summary, statusy. Poznamenej issues se změnami statusu.

### Google Calendar

Calendar data přijdou z gather (source-calendar fetch.sh) — kategorizace a deep-work výpočet je součástí fetch.sh výstupu.
Extrahuj: přehled událostí dle kategorie, celkový meeting čas, zbývající free deep-work čas.

### Slack

Slack data jsou součástí gather morning režimu (source-slack watch-channels).
Přečti `.claude/kvido.local.md` → `sources.slack` pro priority kanálů.

Filtruj na: přímé mentions, odpovědi ve vláknech, DMs.

Mentions z nesledovaných kanálů → zapiš do Recommendations: "Zmínky z nesledovaného kanálu #X — přidat do sources?"

---

## Step 4: Synthesize Briefing

Vypiš briefing v tomto formátu:

```
# Morning Briefing — YYYY-MM-DD

## Yesterday's Work
<!-- Pro každý projekt s > 30 min: jeden řádek s popisem aktivit.
     Zdroje (dle priority): 1. git commity (subject lines, max 3), 2. user messages ze sessions (klíčová slova).
     Formát: - projekt (~Xh Ym) — co se dělalo, max 10 slov
     Projekty s ≤ 30 min: jen - projekt (~Xm) bez popisu -->

## Overnight Changes
<!-- Nové commity ostatních, MR status changes, Jira updates, Slack mentions -->

## Today's Schedule
<!-- Události chronologicky s kategorií -->
<!-- Celkový meeting čas + free time -->

## Inbox
<!-- Počet nepřečtených emailů celkem -->
<!-- Důležité emaily od priority senderů (dle kvido.local.md) — od, předmět -->
<!-- Pokud prázdno: "Inbox: prázdno" -->

## Recommendations
<!-- 2-3 akční položky s konkrétními referencemi (MR čísla, ticket keys) -->
```

Buď stručný. Bullet points. Žádné vycpávky.

### Triage check

Spočítej triage issues:
```bash
GITLAB_REPO=$(skills/config.sh '.sources.gitlab.repo')
glab issue list --repo "$GITLAB_REPO" --label "status:triage" --output json | jq length
```
Pokud > 0:
> "X položek v agent triage — spusť `/triage` pro zpracování."

---

## Step 5: Set Today's Focus

Zeptej se:

> "Na čem se dneska chceš zaměřit?"

Počkej na odpověď. Pak aktualizuj `state/current.md`:

- **Active Focus** — co uživatel řekl
- **Pinned Today** — 1-3 nejdůležitější priority dne odvozené z focusu a ranního kontextu
- **Work in Progress** — ponech otevřené, odstraň dokončené
- **Blockers** — vyčisti vyřešené, ponech nevyřešené
- **Parked** — beze změny
- **Notes for Tomorrow** — vyčisti (bylo surfacnuto)

Zapiš aktualizovaný `state/current.md`.

Zapiš briefing do `state/today.md` (přepiš pokud existuje).

Vrať NL výstup s přehledem dne — heartbeat ho doručí do Slacku přímo přes `slack.sh`. Neposílej přes `slack.sh` přímo. Výstup strukturuj dle `morning` šablony (date, briefing body, triage_count, meeting_time, deepwork_time).

---

## Step 6: Start Heartbeat

> "Spouštím heartbeat. Spouštím `/loop 10m`."

Spusť `/loop 10m`.
