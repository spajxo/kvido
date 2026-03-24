---
name: interests
description: Use when checking configured interest topics for new findings via web search.
allowed-tools: Read, Write, Bash, WebSearch, WebFetch
user-invocable: true
---

> **Configuration:** Use `kvido config 'key'` for topics and intervals.

# Interests

## Manual usage
User says "research X" or "check status of X" → search the web and write up results.

## Automatic usage (maintenance heartbeat)
Read topics via `kvido config --keys 'skills.interests.topics'`. For each topic where it is time to check (based on `check_interval` and `last_checked` in `state/interests.md`):

1. Search the web (WebSearch tool) with query from config
2. Compare with previous state in `state/interests.md`
3. If new relevant info → create a triage task:
   ```bash
   kvido task create \
     --title "[INTERESTS] description" \
     --instruction "description of finding" \
     --source interests \
     --source-ref topic-slug \
     --priority medium
   ```
4. Update `last_checked` in `state/interests.md`
5. Return findings with `urgency` from config (heartbeat decides on notification tier)

## Dedup
Do not suggest a triage item if a similar topic already exists as a task:
```bash
# Iterate all statuses and search by title
for d in state/tasks/*/; do
  for f in "$d"*.md; do
    [[ -f "$f" ]] || continue
    SLUG=$(basename "$f" .md)
    kvido task read "$SLUG" 2>/dev/null | grep '^TITLE=' | cut -d= -f2-
  done
done | grep -i "<search term>"
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
