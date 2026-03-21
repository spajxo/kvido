---
name: worker
description: Async task execution — pravidla, queue management, report format. Spouštěj work scripty z této složky.
---

# Worker Skill

Worker provádí zadané úkoly asynchronně na pozadí heartbeatu.
Veškerý queue management jde přes shell scripty v této složce.
Tasky jsou GitLab Issues na repu `$GITLAB_REPO` s labels pro status a metadata.

## Issues-only Pipeline

```
status:triage → status:todo → status:in-progress → status:review → (closed)
```

- `status:triage` — neroztříděné, čekají na schválení
- `status:todo` — připravené k práci
- `status:in-progress` — právě se pracuje
- `status:review` — čeká na review/kontrolu
- **closed** + `result:done` / `result:failed` / `result:cancelled`

**Labels** (metadata na issues):
- `priority:urgent|high|medium|low`
- `size:s|m|l|xl`
- `source:planner|slack|recurring|self-improver|manual|jira|interests`
- `assignee:user` — legacy; nepřidávej na nové tasky
- `pipeline` — multi-phase task flag
- `phase:brainstorm|spec|implement|review`
- `result:done|failed|cancelled`

**Issue body struktura:**
```markdown
## Task
<instruction text>

## Metadata
- Source Ref: <slack ts, jira key, commit hash>
- Waiting On: <na co se čeká>
- Recurring: <trigger JSON>

## Worker Notes
<worker output>
```

## Work scripty

| Skript | Akce |
|--------|------|
| `work-add.sh` | Vytvoří GitLab Issue s labels, vrátí issue number |
| `work-next.sh` | Vrátí issue number nejvýše prioritního tasku (status:todo) |
| `work-start.sh` | Swap label status:todo → status:in-progress, WIP limit check |
| `work-done.sh` | Close issue + label result:done, handle recurring |
| `work-fail.sh` | Close issue + label result:failed |
| `work-cancel.sh` | Close issue + label result:cancelled |
| `work-task-info.sh` | Issue labels + body → key=value output |

## Pravidla

### Co Worker smí
- Číst libovolné soubory v repozitáři
- Volat source skills a tool skills (glab, acli, slack.sh, gws)
- Volat MCP tools (Atlassian, Slack, Calendar)
- Zapisovat do `state/today.md`
- Dispatovat sub-agenty (researcher, reviewer) pro hloubkovou analýzu

### Co Worker nesmí
- Pushovat do vzdálených repozitářů bez explicitního zadání v instrukci
- Měnit `state/current.md` (patří heartbeatu)
- Dispatovat další workery (žádné worker → worker chaining)
- Posílat více než 3 Slack zprávy na jeden task
- Pokračovat pokud issue je closed (kontrola na začátku)

### Zpracování cancel
Na začátku práce ověř že issue je stále open:
```bash
STATE=$(glab issue view "$TASK_ISSUE" --repo "$GITLAB_REPO" --output json | jq -r '.state')
[ "$STATE" != "opened" ] && exit 0  # tiše — cancel nebo race condition
```

### Timeout
Pokud task trvá > `task_timeout_minutes` (z `.claude/kvido.local.md`):
1. Pošli partial výsledek co máš
2. `work-fail.sh --issue "$TASK_ISSUE" --reason "Timeout po Xm"`
3. Pokud byl progress > 50% → přidej follow-up item s `work-add.sh`

## Pipeline fáze (opt-in pro l/xl tasky)

Worker podporuje strukturovaný pipeline pro velké tasky. Pipeline je opt-in — aktivuje se labelem `pipeline` (automaticky pro size l/xl).

### Kdy použít pipeline

- `size:l` nebo `size:xl` → automaticky labels `pipeline` + `phase:brainstorm`
- `size:s` a `size:m` → pipeline se nepoužívá (standardní execution)

### Chování per fáze

#### brainstorm
1. Přečti task instrukci a veškerý dostupný kontext
2. Přidej komentář na issue s otázkami a nejednoznačnostmi
3. Pošli Slack zprávu s otázkami (max 5 otázek, stručně)
4. Swap labels: `phase:brainstorm` → remove, `status:in-progress` → `status:todo`, set Waiting On v body
5. Chat-responder zapíše odpovědi jako komentář, swap phase label
6. Při příštím spuštění: vyhodnoť jestli máš dost kontextu
   - Ne → další kolo otázek (max 3 kola)
   - Ano → swap `phase:brainstorm` → `phase:spec`, status zpět na todo

#### spec
1. Navrhni 2–3 přístupy (minimal, clean, pragmatic)
2. Komentář na issue + Slack zpráva
3. Swap labels, set Waiting On
4. Chat-responder zapíše volbu, swap `phase:spec` → `phase:implement`

#### implement
Standardní worker execution dle zvolené spec.
Po dokončení: swap `phase:implement` → `phase:review`, status → todo.

#### review
1. Projdi implementaci — bugs, konvence, zjednodušení
2. Komentář + Slack zpráva
3. Pokud blokery → Waiting On
4. Pokud OK → `work-done.sh`

### Pipeline pravidla
- Worker vždy zkontroluje phase label z `work-task-info.sh` na začátku
- Každá fáze je separátní worker run (task se vrací do todo mezi fázemi)
- Max 3 Slack zprávy celkem na celý pipeline
- Uživatel může přerušit cancel (#NNN přes chat)

## Worktree & PR mode

Pokud issue má label `worktree`, worker běží v izolovaném git worktree (heartbeat nastaví `isolation: "worktree"` na Agent tool).

**Auto-worktree pro assistant repo:** Pokud task modifikuje soubory v repozitáři asistenta, vždy použij worktree mode a vytvoř MR — i bez explicitního labelu `worktree`. Nepushuj přímo do main.

### Pravidla
- Všechny změny commitni do worktree branch
- Po dokončení vytvoř MR: `glab mr create --title "<title>" --description "Closes #<issue>" --target-branch main --assignee @me --remove-source-branch --yes`
- PR title = issue title (nebo zkrácená verze)
- PR body obsahuje `Closes #<N>` pro auto-close issue při merge
- Nepushuj přímo do main
- Branch name: automaticky z worktree (Claude Code ji vytvoří)

### Commit message
Použij konvenční commit message (feat/fix/chore) dle typu změny.

### Po vytvoření PR
- `work-done.sh --issue <N> --summary "PR #<X>: <title>"`
- Slack report obsahuje link na PR

---

## Report format

Vrať NL výstup — heartbeat zajistí doručení. Neposílej přes `slack.sh` přímo.

Strukturuj výstup dle `worker-report` šablony (heartbeat ji použije pro formátování):

Výsledný vzhled:
```
🔧 *<stručný název úkolu>*
━━━━━━━━━━━━━━━━
✅ <konkrétní výsledek 1>
✅ <konkrétní výsledek 2>
⚠️ <upozornění — jen pokud relevantní>

#<id> · <Xm Ys>
```

**Konkrétnost je povinná.**
Ne "zkontroloval jsem MRy" ale "group/project !342: čeká 3 dny, assignee Jan, 2 nevyřešené komentáře".
Pokud output > 3000 znaků → zkrať na top 5 položek + "a X dalších".
