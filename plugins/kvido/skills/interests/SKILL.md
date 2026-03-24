---
name: interests
description: Use when checking configured interest topics for new findings via web search.
allowed-tools: Read, Write, Bash, WebSearch, WebFetch
user-invocable: true
---

# Interests

## Manual usage
User says "research X" or "check status of X" → search the web and write up results.

## Automatic usage (maintenance heartbeat)
Read topics via `kvido config --keys 'skills.interests.topics'`. For each topic where it is time to check (based on `check_interval` and `last_checked` from `kvido planner-state interests get <topic>`):

1. Search the web (WebSearch tool) with query from config
2. Compare with previous state via `kvido planner-state interests get <topic>`
3. If new relevant info → create a triage task:
   ```bash
   kvido task create \
     --title "[INTERESTS] description" \
     --instruction "description of finding" \
     --source interests \
     --source-ref topic-slug \
     --priority medium
   ```
4. Update `last_checked`: `kvido planner-state interests set <topic>`
5. Return findings with `urgency` from config (heartbeat decides on notification tier)

## Dedup
Do not suggest a triage item if a similar topic already exists as a task:
```bash
# Iterate all statuses and search by title
for d in $(kvido task list | awk '{print $1}'); do
  kvido task read "$d" 2>/dev/null | grep '^TITLE=' | cut -d= -f2-
done | grep -i "<search term>"
```

## State access
Check when a topic was last checked:
```bash
kvido planner-state interests get <topic>   # exit 1 = not checked recently
```
List all tracked topics:
```bash
kvido planner-state interests list
```
Update after checking a topic:
```bash
kvido planner-state interests set <topic>   # sets last_checked to now
```
