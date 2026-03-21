---
name: worker
description: Async task execution — pravidla, queue management, report format. Veškeré operace přes task.sh.
---

# Worker Skill

Worker provádí zadané úkoly asynchronně na pozadí heartbeatu.
Veškerý queue management jde přes `skills/worker/task.sh`.
Tasky jsou lokální markdown soubory v `state/tasks/` — status je název složky, metadata jsou YAML frontmatter.

## Pipeline

```
triage/ → todo/ → in-progress/ → done/
                                → failed/
                                → cancelled/
```

- `triage/` — neroztříděné, čekají na schválení
- `todo/` — připravené k práci
- `in-progress/` — právě se pracuje
- `done/` — dokončené
- `failed/` — selhané
- `cancelled/` — zrušené

**Frontmatter fields** (metadata v YAML hlavičce):
- `priority: urgent|high|medium|low`
- `size: s|m|l|xl`
- `source: planner|slack|recurring|self-improver|manual|jira|interests`
- `source_ref: <slack ts, jira key, commit hash>`
- `pipeline: true` — multi-phase task flag
- `phase: brainstorm|spec|implement|review`
- `waiting_on: <na co se čeká>`
- `recurring: <trigger JSON>`

**Task file struktura:**
```markdown
---
priority: medium
size: m
source: slack
source_ref: "1773933088.437"
---
## Instruction
<instruction text>

## Worker Notes
<worker output>
```

## task.sh subcommands

| Subcommand | Akce |
|------------|------|
| `task.sh create --title "..." --instruction "..." [--priority P] [--size S] [--source SRC] [--source-ref REF] [--worktree] [--goal G]` | Vytvoří task soubor, vrátí slug. Pipeline auto pro l/xl. |
| `task.sh read <slug>` | Vrátí frontmatter + obsah jako key=value |
| `task.sh read-raw <slug>` | Vrátí raw markdown obsah task souboru |
| `task.sh update <slug> <field> <value>` | Aktualizuje frontmatter field |
| `task.sh move <slug> <status>` | Přesune task do jiné status složky |
| `task.sh list [status]` | Vypíše tasky (volitelně filtr na status) |
| `task.sh find <slug>` | Najde task a vrátí jeho aktuální status (složku) |
| `task.sh note <slug> "<text>"` | Přidá text do ## Worker Notes |
| `task.sh count [status]` | Počet tasků (volitelně per status) |

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
- Pokračovat pokud task je v done/failed/cancelled (kontrola na začátku)

### Zpracování cancel
Na začátku práce ověř že task nebyl zrušen/dokončen:
```bash
STATUS=$(skills/worker/task.sh find "$TASK_SLUG")
[[ "$STATUS" =~ ^(done|failed|cancelled)$ ]] && exit 0  # tiše — cancel nebo race condition
```

### Timeout
Pokud task trvá > `task_timeout_minutes` (z `.claude/kvido.local.md`):
1. Pošli partial výsledek co máš
2. `task.sh note "$TASK_SLUG" "## Failed\nTimeout po Xm"` + `task.sh move "$TASK_SLUG" failed`
3. Pokud byl progress > 50% → přidej follow-up: `task.sh create "<title>" --priority medium --size s`

## Pipeline fáze (opt-in pro l/xl tasky)

Worker podporuje strukturovaný pipeline pro velké tasky. Pipeline je opt-in — aktivuje se frontmatter `pipeline: true` (automaticky pro size l/xl).

### Kdy použít pipeline

- `size: l` nebo `size: xl` → automaticky `pipeline: true` + `phase: brainstorm`
- `size: s` a `size: m` → pipeline se nepoužívá (standardní execution)

### Chování per fáze

#### brainstorm
1. Přečti task instrukci a veškerý dostupný kontext
2. Přidej worker note s otázkami a nejednoznačnostmi
3. Pošli Slack zprávu s otázkami (max 5 otázek, stručně)
4. `task.sh move "$TASK_SLUG" todo` + `task.sh update "$TASK_SLUG" waiting_on "<popis>"`
5. Chat-responder zapíše odpovědi jako worker note, aktualizuje phase
6. Při příštím spuštění: vyhodnoť jestli máš dost kontextu
   - Ne → další kolo otázek (max 3 kola)
   - Ano → `task.sh update "$TASK_SLUG" phase spec` + `task.sh move "$TASK_SLUG" todo`

#### spec
1. Navrhni 2–3 přístupy (minimal, clean, pragmatic)
2. Worker note + Slack zpráva
3. `task.sh update "$TASK_SLUG" waiting_on "<čeká na volbu>"`
4. Chat-responder zapíše volbu, `task.sh update "$TASK_SLUG" phase implement`

#### implement
Standardní worker execution dle zvolené spec.
Po dokončení: `task.sh update "$TASK_SLUG" phase review` + `task.sh move "$TASK_SLUG" todo`.

#### review
1. Projdi implementaci — bugs, konvence, zjednodušení
2. Worker note + Slack zpráva
3. Pokud blokery → `task.sh update "$TASK_SLUG" waiting_on "<blocker>"`
4. Pokud OK → `task.sh move "$TASK_SLUG" done`

### Pipeline pravidla
- Worker vždy zkontroluje phase z `task.sh read` na začátku
- Každá fáze je separátní worker run (task se vrací do todo mezi fázemi)
- Max 3 Slack zprávy celkem na celý pipeline
- Uživatel může přerušit cancel (slug přes chat)

## Worktree & PR mode

Pokud task má frontmatter `worktree: true`, worker běží v izolovaném git worktree (heartbeat nastaví `isolation: "worktree"` na Agent tool).

**Auto-worktree pro assistant repo:** Pokud task modifikuje soubory v repozitáři asistenta, vždy použij worktree mode — i bez explicitního `worktree: true`. Nepushuj přímo do main.

### Pravidla
- Všechny změny commitni do worktree branch
- `git push -u origin HEAD`
- Uživatel vytvoří MR manuálně
- Nepushuj přímo do main
- Branch name: automaticky z worktree (Claude Code ji vytvoří)

### Commit message
Použij konvenční commit message (feat/fix/chore) dle typu změny.

### Po dokončení worktree tasku
- `task.sh note "$TASK_SLUG" "## Result\nBranch: <branch>, pushed. <popis změn>"`
- `task.sh move "$TASK_SLUG" done`
- Slack report obsahuje název branch

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

<slug> · <Xm Ys>
```

**Konkrétnost je povinná.**
Ne "zkontroloval jsem MRy" ale "group/project !342: čeká 3 dny, assignee Jan, 2 nevyřešené komentáře".
Pokud output > 3000 znaků → zkrať na top 5 položek + "a X dalších".
