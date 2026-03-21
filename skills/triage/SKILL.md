---
name: triage
description: Triage inbox, backlog management, WIP limit enforcement. Interaktivní zpracování neroztříděných položek.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
---

> **Konfigurace:** WIP limit a práhy z root `kvido.local.md` → `skills.triage` (přes `config.sh`). Defaults: wip_limit=3, triage_overflow_threshold=10.

# Triage & Backlog

## Tone Guidelines

Tón a styl dle `memory/persona.md` (sekce Triage). Pokud persona neexistuje, buď stručný a věcný.

## Interaktivní triage

Načti GitLab Issues s labelem `status:triage`:

```bash
glab issue list --repo "$GITLAB_REPO" --label "status:triage" --output json | jq '[.[] | {iid, title, labels, created_at}]'
```

Pokud žádné issues: "Triage inbox je prázdný ✓" a skonči.

Pro každý issue zobraz:

```
📥 [N/total] #<number> <title>
  labels: <labels> | added: <createdAt>
  → [ano / později / ne]
```

Čekej na odpověď. Pak:
- `ano` → schval issue a přeřaď do todo: `glab issue update <N> --repo "$GITLAB_REPO" --unlabel "status:triage" --label "status:todo"`. Přidej `priority:medium` jako default label (uprav dle kontextu).
- `později` → přidej komentář s datem odložení: `glab issue note <N> --repo "$GITLAB_REPO" --message "deferred: YYYY-MM-DD"`, nech jako `status:triage`
- `ne` → zruš issue: `work-cancel.sh --issue <N>`

Po zpracování všech: "Triage hotový: X přijato, Y odloženo, Z zahozeno."

## WIP Limit

Worker automaticky hlídá WIP limit pro in-progress tasky.

Zjisti aktuální WIP:
```bash
glab issue list --repo "$GITLAB_REPO" --label "status:in-progress" --output json | jq length
```
Pokud >= 3: "WIP limit 3 dosažen. Co pozastavit nebo dokončit?"

Issues s "Waiting On" poznámkou v body se nepočítají do limitu — zjisti přes `glab issue list --repo "$GITLAB_REPO" --label "status:in-progress" --output json | jq '[.[] | {iid, description}]'` a filtruj ty s "Waiting On" textem.
