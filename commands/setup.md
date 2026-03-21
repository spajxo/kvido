---
name: setup
description: Setup & self-healing — first-time onboarding, structure bootstrap, health check
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent
---

# Kvido Setup

Setup a self-healing command. Spouštěj při prvním spuštění, po instalaci pluginu, nebo po problémech.

## Step 0: Prerequisites

```bash
for cmd in jq; do
  if command -v "$cmd" &>/dev/null; then
    echo "OK: $cmd $(command -v $cmd)"
  else
    echo "MISSING: $cmd — required"
  fi
done
for cmd in glab acli gws; do
  if command -v "$cmd" &>/dev/null; then
    echo "OK: $cmd $(command -v $cmd)"
  else
    echo "OPTIONAL: $cmd not found"
  fi
done
```

Pokud chybí povinný nástroj, informuj uživatele a nabídni instalaci. Nepokračuj dokud nejsou splněny povinné prerekvizity.

## Step 1: First-time Setup

Detekce: `.env` neexistuje NEBO `memory/persona.md` neexistuje → spusť first-time setup.
Pokud obojí existuje, přeskoč na Step 2.

### a) Config soubory

Pokud neexistují, vytvoř:
- `.claude/kvido.local.md` — zkopíruj `kvido.local.md.example` z pluginu
- `.env` — vytvoř s prázdnými hodnotami:
  ```
  SLACK_DM_CHANNEL_ID=
  SLACK_USER_ID=
  SLACK_USER_NAME=
  SLACK_BOT_TOKEN=
  ```

### b) Persona setup

Pokud `memory/persona.md` neexistuje:
1. Zeptej se uživatele: "Jak se má tvůj asistent jmenovat? Jaký má mít tón a osobnost? (např. stručný a věcný, přátelský, formální...)"
2. Z odpovědi vytvoř `memory/persona.md` s odpovídající strukturou (jméno, jazyk, tón, osobnost, URL formáty)
3. Vytvoř i `memory/` adresář pokud neexistuje

### c) .env vyplnění

Přečti `.env`. Pokud obsahuje prázdné hodnoty (klíče s `=""` nebo `=`):
1. Vypiš seznam chybějících hodnot a k čemu slouží
2. Nabídni pomoc s vyplněním (jak najít Slack IDs, kde vzít tokeny atd.)
3. Pokud uživatel poskytne hodnoty, zapiš je do `.env`

### d) .gitignore

Přidej do `.gitignore` pokud tam ještě nejsou:
```
.claude/kvido.local.md
.env
state/
memory/
```

### e) CLAUDE.md

Pokud projekt nemá `CLAUDE.md`, zkopíruj `CLAUDE.md.template` z pluginu jako základ.


## Step 2: Structure Bootstrap

Vytvoř chybějící adresáře:

```bash
mkdir -p memory/{journal,weekly,projects,people,decisions,archive/{journal,weekly,decisions}}
mkdir -p state/tasks/{triage,todo,in-progress,done,failed,cancelled}
```

Pro každý chybějící soubor vytvoř s minimálním obsahem:
- `memory/memory.md` → `# Memory` + sekce (Kdo jsem, Aktivní projekty, Klíčová rozhodnutí, Naučené lekce, Lidé)
- `memory/this-week.md` → `# Week YYYY-Www`
- `memory/learnings.md` → `# Learnings`
- `memory/errors.md` → `# Errors`
- `memory/people/_index.md` → `# People`
- `memory/decisions/_index.md` → `# Decisions`
- `state/heartbeat-state.json` → default schema (iteration_count: 0, všechny timestamps null, last_chat_ts: "0", cron_job_id: "", active_preset: "10m", last_interaction_ts: null)
- `state/current.md` → prázdný template (Active Focus, WIP, Blockers, Parked, Notes for Tomorrow)
- `state/planner-state.md` → prázdný planner state template

## Step 3: Planning Bootstrap

Pokud `memory/planner.md` neexistuje, vytvoř s ukázkovým obsahem:

```markdown
# Planner — osobní instrukce

Sem přidej osobní instrukce pro plannera.

## Příklady
- 11:00: Připomeň mi stretch break
- Pondělí: Zkontroluj stav všech MRů za minulý týden
- Pátek 15:00: Příprava na weekly standup
```

## Step 4: EOD Catch-up

Zkontroluj `memory/journal/` — pokud chybí journal pro dny kde existuje git aktivita:
- Dispatni librarian: "Extraction mode pro YYYY-MM-DD. Vytvoř catch-up journal z dostupných dat."

## Step 5: Rotace

### Weekly
Pokud `memory/this-week.md` obsahuje předchozí týden:
- Přesuň obsah do `memory/weekly/YYYY-Www.md`
- Resetuj na aktuální týden

### Archive
- Journals starší 14 dní → `memory/archive/journal/`
- Weekly starší 8 týdnů → `memory/archive/weekly/`
- Decisions starší 90 dní → `memory/archive/decisions/`

## Step 6: Health Check

### Env check
Ověř že `.env` obsahuje všechny požadované klíče (`SLACK_DM_CHANNEL_ID`, `SLACK_USER_ID`, `SLACK_USER_NAME`, `SLACK_BOT_TOKEN`) a že nejsou prázdné.
Chybějící nebo prázdné → log warning.

### Binary check
```bash
for cmd in jq glab acli gws; do
  command -v "$cmd" &>/dev/null || echo "WARNING: $cmd not found"
done
```

### Git connectivity
Pro každý repo v `.claude/kvido.local.md`:
```bash
test -d <path>/.git || echo "WARNING: repo <name> missing at <path>"
```

### Source health
Spusť health check z každého source skillu (dle SKILL.md → health capability).
Zapiš výsledky do `state/source-health.json`.

### Uncommitted assistant changes
```bash
git status --porcelain
```
Pokud neprázdné → warning.

## Output

Pokud vše OK → "Setup complete: vše v pořádku"
Pokud vytvořeny soubory → výpis co bylo vytvořeno
Pokud catch-up → výpis co bylo doplněno
