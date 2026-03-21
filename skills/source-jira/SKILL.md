---
name: source-jira
description: Jira source — fetch issues, watch changes, detect triage items. Používej přes gather skill.
allowed-tools: Read, Bash, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
user-invocable: false
---

> **Konfigurace:** Přečti `.claude/kvido.local.md`. Credentials (`ATLASSIAN_CLOUD_ID`, `ATLASSIAN_SITE`) čti z `.env`.

# Source: Jira

## Capabilities

### fetch
```bash
skills/source-jira/fetch.sh [--since YYYY-MM-DD] [--project KEY]
```
Výstup: plain text, jeden blok per projekt.

### watch
Spusť fetch s `--since YYYY-MM-DD` (dnešní datum).
Nové/změněné tickety oproti předchozímu planner-state = events.

### triage-detect
Po fetch zkontroluj:
- Nový ticket assignee=me → dedup check:
  ```bash
  # Projdi existující úkoly se source jira
  for d in state/tasks/*/; do
    for f in "$d"*.md; do
      [[ -f "$f" ]] || continue
      SLUG=$(basename "$f" .md)
      TASK_DATA=$(skills/worker/task.sh read "$SLUG" 2>/dev/null) || continue
      src=$(echo "$TASK_DATA" | grep '^SOURCE=' | cut -d= -f2-)
      [[ "$src" == "jira" ]] || continue
      echo "$TASK_DATA" | grep '^TITLE=' | cut -d= -f2-
    done
  done
  ```
  Pokud odpovídající úkol neexistuje → vytvoř triage úkol:
  ```bash
  skills/worker/task.sh create \
    --title "[KEY] summary" \
    --instruction "Jira ticket: summary. Key: KEY" \
    --source jira \
    --source-ref KEY \
    --priority medium
  ```

### health
```bash
acli jira info 2>/dev/null && echo "OK" || echo "FAIL: acli"
```
Fallback: Atlassian MCP searchJiraIssuesUsingJql s testovým JQL `project = PROJ ORDER BY updated DESC` (limit 1 přes maxResults parametr MCP, ne v JQL).

## Schedule
- morning: fetch
- heartbeat-quick: skip
- heartbeat-full: watch (--since today)
- heartbeat-maintenance: health
- eod: skip (worklog check zůstává přímo v EOD)
