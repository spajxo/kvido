---
name: triage
description: Triage inbox, backlog management, WIP limit enforcement. Interaktivní zpracování neroztříděných položek.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
---

> **Konfigurace:** WIP limit a práhy z `.claude/kvido.local.md` → `skills.triage` (přes `config.sh`). Defaults: wip_limit=3, triage_overflow_threshold=10.

# Triage & Backlog

## Tone Guidelines

Tón a styl dle `memory/persona.md` (sekce Triage). Pokud persona neexistuje, buď stručný a věcný.

## Interaktivní triage

Načti seznam úkolů v triage:

```bash
skills/worker/task.sh list triage
```

Pokud žádné úkoly: "Triage inbox je prázdný ✓" a skonči.

Pro každý úkol zobraz:

```bash
# Pro každý slug z výpisu:
skills/worker/task.sh read <slug>
```

```
📥 [N/total] <slug>: <title>
  priority: <priority> | size: <size> | added: <created_at>
  → [ano / později / ne]
```

Čekej na odpověď. Pak:
- `ano` → schval a přesuň do todo: `skills/worker/task.sh move <slug> todo`
- `později` → přidej poznámku: `skills/worker/task.sh note <slug> "deferred: YYYY-MM-DD"`, nech v triage
- `ne` → zruš: `skills/worker/task.sh note <slug> "Rejected by user" && skills/worker/task.sh move <slug> cancelled`

Po zpracování všech: "Triage hotový: X přijato, Y odloženo, Z zahozeno."

## WIP Limit

Worker automaticky hlídá WIP limit pro in-progress tasky.

Zjisti aktuální WIP:
```bash
skills/worker/task.sh count in-progress
```
Pokud >= 3: "WIP limit 3 dosažen. Co pozastavit nebo dokončit?"

Úkoly s "waiting_on" ve frontmatter se nepočítají do limitu — zjisti přes `skills/worker/task.sh read <slug>` a filtruj ty s neprázdným WAITING_ON.
