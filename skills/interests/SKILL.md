---
name: interests
description: Monitoring zájmových témat — security advisories, dependency releases, AI tooling updates.
allowed-tools: Read, Write, Bash, WebSearch, WebFetch
user-invocable: true
---

> **Konfigurace:** Přečti `.claude/kvido.local.md` pro témata a intervaly.

# Interests

## Manuální použití
Uživatel řekne "research X" nebo "zjisti stav X" → prohledej web a zapiš výsledky.

## Automatické použití (maintenance heartbeat)
Přečti `.claude/kvido.local.md`. Pro každé téma kde je čas na check (podle `check_interval` a `last_checked` v `state/interests.md`):

1. Prohledej web (WebSearch tool) s query z config
2. Porovnej s předchozím stavem v `state/interests.md`
3. Pokud nové relevantní info → vytvoř triage issue:
   ```bash
   skills/worker/work-add.sh \
     --title "[INTERESTS] popis" \
     --source interests \
     --source-ref topic-slug \
     --assignee user \
     --priority medium
   ```
4. Aktualizuj `last_checked` v `state/interests.md`
5. Vrať findings s `urgency` z config (heartbeat rozhodne o notification tieru)

## Dedup
Nenavrhuj triage item pokud podobný topic už existuje jako issue:
```bash
glab issue list --repo "$GITLAB_REPO" --state all --search "<title>" --output json | jq '[.[] | {iid, title}]'
```

## State format
`state/interests.md`:
```markdown
# Interests State

| topic | last_checked | last_summary |
|-------|-------------|--------------|
| nelmio-sf8 | 2026-03-13 | ... |
| zitadel-login-v2 | 2026-03-10 | ... |
```
