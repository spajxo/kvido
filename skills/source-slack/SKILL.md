---
name: source-slack
description: Slack source — channel monitoring, DM inbox, mention detection. Primárně přes slack.sh (Slack Web API), MCP jako fallback pro search.
allowed-tools: Read, Bash, mcp__claude_ai_Slack__slack_search_public_and_private
user-invocable: false
---

> **Konfigurace:** Přečti `.claude/kvido.local.md` pro channel list. DM credentials čti z `.env`.

# Source: Slack

Čtení přes `slack.sh read` (Slack Web API). Search přes Slack MCP (vyžaduje user context).

## Capabilities

### watch-dm

```bash
skills/slack/slack.sh read --limit 5
```

Výstup: JSON array. Filtruj přes `jq`:
- `.[] | select(.user == "$SLACK_USER_ID")` — zprávy od uživatele
- `.[] | select(.ts > "$last_dm_ts")` — novější než poslední scan

Navíc přečti `dm_channels` z `.claude/kvido.local.md`. Pro každý kde je `channel_id` definováno (přeskoč záznamy bez `channel_id`):
```bash
skills/slack/slack.sh read "<channel_id>" --limit 5 --oldest "$last_dm_ts"
```

Pro nové zprávy od ostatních uživatelů (ne od `SLACK_USER_ID`) vyhodnoť úroveň notifikace:

| Úroveň | Kdy | Akce |
|---------|-----|------|
| `silent` | FYI, informační zprávy | Log: `- **HH:MM** [dm/<jméno>] <zkrácený text>` do `state/today.md` |
| `batch` | Méně urgentní, může počkat | Vrať v NL výstupu s `Event (batch):` prefixem — heartbeat doručí při dalším full heartbeatu |
| `immediate` | Vyžaduje reakci — otázka, request, blokuje někoho | `slack.sh send event --var emoji="💬" --var title="DM od <jméno>" --var description="<text max 100 zn>" --var source="Slack DM" --var reference="otevři DM" --var timestamp="<HH:MM>"` |

Rozhodni podle kontextu — kdo píše, co potřebuje, jak urgentní to je.

Vždy aktualizuj timestamp po zpracování:
```bash
skills/heartbeat/heartbeat-state.sh set last_dm_ts "<nejnovější ts>"
```

### watch-channels

Přečti `.claude/kvido.local.md`. Pro kanály s `priority: high` a `priority: normal` kde je `channel_id`:

**Výběr transportu:**
- Kanál bez `use_mcp` (nebo `use_mcp: false`) → použij `slack.sh read` (Bot token, standardní):
  ```bash
  skills/slack/slack.sh read "<channel_id>" --limit 5
  ```
- Kanál s `use_mcp: true` → použij Slack MCP `slack_read_channel` (čte jako uživatel — pro kanály kde bot nemá přístup nebo je vyžadován user context):
  ```
  mcp__claude_ai_Slack__slack_read_channel(channel_id="<channel_id>", limit=5)
  ```

Pro kanály bez `channel_id` → přeskoč (nebo doplň ID do `.claude/kvido.local.md`).

Pro kanály s `watch_for: marvin_qa`: analyzuj zprávy z pohledu kvality AI bota Marvin.
Signály k reportování (desktop level):
- Uživatel si stěžuje na odpověď bota
- Bot neodpověděl nebo odpověděl prázdně
- Uživatel opakuje dotaz
Report format: `[ds-parking/marvin] <popis problému nebo příležitosti>`

Po analýze zapiš nálezy do `state/today.md` jako samostatnou sekci `## Marvin QA`.
Pokud sekce v today.md ještě neexistuje, přidej ji na konec souboru.
Pokud existuje, appenduj nové nálezy pod existující obsah sekce.
Formát každého nálezu: `- **HH:MM** <popis problému nebo příležitosti>`
Pokud nebyly nalezeny žádné nové nálezy, do today.md nepište nic (tichý výstup).

### triage-detect

Slack zprávy s akčním obsahem: "mohl bys", "potřebujeme", "review", "podívej se", "deadline", "prosím"
→ triage item: `- [ ] popis (od @author v #channel) #source:slack #added:YYYY-MM-DD`

### health

```bash
skills/slack/slack.sh read --limit 1
```
OK pokud vrátí neprázdný výsledek.

## Schedule

- morning: watch-channels (mentions od včerejška)
- heartbeat-quick: watch-dm
- heartbeat-full: watch-dm + watch-channels (high+normal)
- heartbeat-maintenance: health
- eod: skip
