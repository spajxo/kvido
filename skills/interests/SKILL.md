---
name: interests
description: Use when checking configured interest topics for new findings via web search.
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
3. Pokud nové relevantní info → vytvoř triage úkol:
   ```bash
   skills/worker/task.sh create \
     --title "[INTERESTS] popis" \
     --instruction "popis nálezu" \
     --source interests \
     --source-ref topic-slug \
     --priority medium
   ```
4. Aktualizuj `last_checked` v `state/interests.md`
5. Vrať findings s `urgency` z config (heartbeat rozhodne o notification tieru)

## Dedup
Nenavrhuj triage item pokud podobný topic už existuje jako úkol:
```bash
# Projdi všechny statusy a hledej podle titulku
for d in state/tasks/*/; do
  for f in "$d"*.md; do
    [[ -f "$f" ]] || continue
    SLUG=$(basename "$f" .md)
    skills/worker/task.sh read "$SLUG" 2>/dev/null | grep '^TITLE=' | cut -d= -f2-
  done
done | grep -i "<hledaný výraz>"
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
