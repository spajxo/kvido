---
name: eod
description: Konec dne — journal entry, worklog check, update stavu, weekly summary (pátek). Spouštěj při EOD triggeru nebo manuálně přes /eod.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronList, CronDelete, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian__addWorklogToJiraIssue
---

# End-of-Day

Postupuj krok za krokem.

## Tone Guidelines

Tón a styl dle `memory/persona.md` (sekce EOD). Pokud persona neexistuje, buď stručný a věcný.

---

## Step 1: Gather Today's Data

Přečti `state/today.md` (heartbeat log) a `state/current.md` (focus, WIP).

Zjisti dnešní datum (YYYY-MM-DD).

### Activity log sumarizace

Pokud existuje `state/activity-log.jsonl`, spočítej dnešní statistiky:
```bash
TODAY=$(date +%Y-%m-%d)
jq -s --arg today "${TODAY}T00:00:00" '[.[] | select(.ts >= $today)]' state/activity-log.jsonl
```

Z filtrovaných záznamů extrahuj:
- **Celkové tokeny za den:** `map(.tokens // 0) | add`
- **Top agent by tokens:** `group_by(.agent) | map({agent: .[0].agent, tokens: (map(.tokens // 0) | add)}) | sort_by(-.tokens)`
- **Počet tasků:** `map(.task_id // empty) | unique | length`
- **Počet dispatch/execute cyklů:** `map(select(.action == "execute")) | length`

Zahrň souhrn do journal entry (Step 2) jako sekci `## Token Usage`.

Spusť source skills pro EOD data:
- `skills/source-sessions/fetch.sh <dnešní-datum>`
- `skills/source-gitlab/fetch-activity.sh <dnešní-datum>`

**Detekce uncommitted work** — přečti `.claude/kvido.local.md`, pro každý repo:

```bash
git -C <repo_path> status --porcelain
git -C <repo_path> stash list
```

Sbírej repo s uncommitted changes nebo stashes.

---

## Step 2: Create Journal Entry

Vytvoř journal kombinací:
- Session parser (na čem, jak dlouho)
- Git activity (commity dnes)
- Heartbeat log z `state/today.md`
- WIP a blocker status z `state/current.md`
- Uncommitted work (repo: N modified, M untracked, K stashes)

Formát:

```
# Journal — YYYY-MM-DD

## Summary
<!-- 2-3 věty: hlavní focus, co se udělalo -->

## Work Done
<!-- Per projekt, bullet points -->

## Goals Progress
<!-- Hotové tasky dnes seskupené per goal. Načti z GitLab Issues closed today s label goal:* -->
<!-- glab issue list --repo $REPO --state closed --label "result:done" --updated-after YYYY-MM-DDT00:00:00Z -->
<!-- Seskup podle goal:* labelu. Tasky bez goalu zobraz pod "Ostatní". -->
<!-- Format: ### Goal Name\n- #N title -->

## MRs
<!-- Status MRs: created, updated, merged, reviewed -->

## Blockers & Issues
<!-- Nevyřešené, carry forward -->

## Token Usage
<!-- Celkové tokeny, top agent, počet runs — z activity-log.jsonl. Přeskoč pokud JSONL neexistuje. -->

## Unfinished Work
<!-- Repos s uncommitted changes -->

## Tomorrow
<!-- Co pokračovat, deadlines -->
```

Zapiš do `memory/journal/YYYY-MM-DD.md`.

---

## Step 3: Worklog Check

Sestav přehled odpracovaného času ze session-parser + git-activity + kalendáře:
- Seskup podle Jira ticketu/projektu
- Odhadni čas (zaokrouhli na 15 min; git-only = 15 min/commit, max 2h)
- Meetingy z `state/today.md` jako samostatné řádky
- Bez ticketu = `(interní)`

Načti existující worklogy přes Atlassian MCP:
```
searchJiraIssuesUsingJql:
  cloudId: $ATLASSIAN_CLOUD_ID  # from .env
  jql: worklogAuthor = currentUser() AND worklogDate = "YYYY-MM-DD"
  fields: ["summary", "worklog", "timespent"]
```

Porovnej. Tolerance: ±30 min. Vypiš tabulku:

```
## Worklog — YYYY-MM-DD

| Ticket | Projekt | Čas | Popis | Status |
|--------|---------|-----|-------|--------|
| PROJ-123 | my-project | 3h | Feature implementation | ✗ nezalogováno |
```

Pokud vše ✓: "Vše zalogováno ✓". Jinak zobraz tabulku + "Chceš zalogovat?"

Na potvrzení zaloguj přes `addWorklogToJiraIssue`.

---

## Step 4: Dispatch Librarian

Dispatni librarian subagent pro extraction:

```
Agent tool:
  prompt: "Extraction mode. Parsuj memory/journal/YYYY-MM-DD.md, extrahuj fakta do memory/projects/, memory/people/, memory/decisions/. Aktualizuj memory/this-week.md. Aktualizuj memory/memory.md pokud se změnil stav projektů nebo rozhodnutí."
```

---

## Step 5: Work Sync

Zjisti stav osobní práce z `state/current.md`, dnešních změn a živých zdrojů. GitLab work queue kontroluj jen pro assistant tasky.

- Jira / GitLab / mail / kalendář:
  - zapiš, co se dnes skutečně posunulo
  - zvýrazni, co zůstává rozdělané nebo čeká na reakci
  - pokud dnes proběhla práce mimo předchozí current context, doplň ji do journalu a `state/current.md`; nevytvářej kvůli tomu user issue
- Assistant work queue:
  - můžeš zkontrolovat `status:todo|status:in-progress` pro worker tasky a zmínit relevantní stav v journalu, pokud je to důležité

---

## Step 6: Update Working Memory

Aktualizuj `state/current.md`:
- **Active Focus** — vyčisti
- **Pinned Today** — vyčisti nebo převeď do `Notes for Tomorrow`
- **Work in Progress** — aktualizuj statusy, označ dokončené, přidej nové
- **Blockers** — aktuální stav
- **Parked** — beze změny
- **Notes for Tomorrow** — uncommitted work, follow-ups, deadlines

Reset `state/heartbeat-state.json`: `iteration_count` na 0, vyčisti `reported`.

---

## Step 7: Friday — Weekly Summary

Zjisti den v týdnu. Pokud pátek:

Přečti všechny journaly z tohoto týdne v `memory/journal/`.

Vytvoř weekly summary:

```
# Weekly Summary — YYYY-Www

## Highlights
<!-- 3-5 klíčových accomplishments -->

## Per Project
<!-- Projekt — co se dělalo — aktuální stav -->

## MRs
<!-- Created, merged, reviewed tento týden -->

## Blockers & Carry-forward
<!-- Co se nestihlo a proč -->

## Backlog Stats
<!-- Done items tento týden, open items count -->

## Next Week
<!-- Priority, deadlines -->
```

Zapiš do `memory/weekly/YYYY-Www.md`.

**Archive rotation:**
```bash
mkdir -p memory/archive/journal memory/archive/weekly memory/archive/decisions
```

Přesuň journals starší 14 dní do `memory/archive/journal/`.
Přesuň weekly starší 8 týdnů do `memory/archive/weekly/`.

---

## Step 7b: Daily Questions

Přečti `skills/daily-questions/SKILL.md` a postupuj dle instrukcí.
Pokud je skill disabled nebo není pracovní den, přeskoč.

---

## Step 8: Cleanup & Confirm

Heartbeat loop běží dál v night mode (jen chat check + silent git watch). Neruš cron.

Vrať NL výstup se souhrnem dne — heartbeat ho doručí do Slacku přímo přes `slack.sh`. Neposílej přes `slack.sh` přímo. Výstup strukturuj dle `eod` šablony (date, summary, session_time, done_count, open_count).

Výstup:
> "Journal zapsán do `memory/journal/YYYY-MM-DD.md`. Heartbeat přechází do nočního režimu. Hezký večer!"

Pokud weekly: přidej info o weekly summary.

Buď stručný.
