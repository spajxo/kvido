---
name: source-jira
description: Jira source — fetch issues, watch changes, detect triage items. Používej přes gather skill.
allowed-tools: Read, Bash, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
user-invocable: false
---

> **Konfigurace:** Přečti `kvido.local.md` v této složce. Credentials (`ATLASSIAN_CLOUD_ID`, `ATLASSIAN_SITE`) čti z `.env`.

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
  glab issue list --repo "$GITLAB_REPO" --label "source:jira" --output json | jq '[.[] | {iid, title}]'
  ```
  Pokud odpovídající issue neexistuje → vytvoř triage issue:
  ```bash
  skills/worker/work-add.sh \
    --title "[KEY] summary" \
    --source jira \
    --source-ref KEY \
    --assignee user \
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
