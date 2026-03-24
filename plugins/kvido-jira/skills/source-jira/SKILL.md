---
name: source-jira
description: Use when fetching Jira issues, watching for changes, or detecting new assigned tickets.
allowed-tools: Read, Bash, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
user-invocable: false
---

> **Configuration:** Via `kvido config` (`sources.jira.*` keys). Credentials (e.g. `ATLASSIAN_CLOUD_ID`) can be referenced as `"$ENV_VAR"` in `settings.json` and resolved via `kvido config` from `.env`.

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: Jira

> **Note:** This source plugin is always invoked by the core kvido planner agent. All `skills/worker/` paths refer to scripts in the core kvido plugin (resolved from the agent's working context).

## Capabilities

### fetch
```bash
skills/source-jira/fetch.sh [--since YYYY-MM-DD] [--project KEY]
```
Output: plain text, one block per project.

**MCP fallback:** If fetch.sh exits with code 10 (`acli` not available), use Atlassian MCP directly:

1. Read project config via `kvido config --keys 'sources.jira.projects'`
2. For each project, get its JQL filter: `kvido config 'sources.jira.projects.<KEY>.filter'`
3. Call `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql(jql="<filter>", maxResults=20)`
4. Format output the same way: `=== Project (N issues) ===` then `  KEY [status] summary` per issue

### watch
Run fetch with `--since YYYY-MM-DD` (today's date).
If fetch.sh returns exit code 10, follow the MCP fallback from the fetch section above, adding `AND updated >= "<today>"` to each JQL filter.
New/changed tickets compared to previous planner-state = events.

### triage-detect
After fetch check:
- New ticket assignee=me → dedup check:
  ```bash
  # List existing tasks with source jira
  kvido task list --source jira --format slug-title
  ```
  If no matching task exists → create triage task:
  ```bash
  kvido task create \
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
Fallback: Atlassian MCP searchJiraIssuesUsingJql with test JQL `project = PROJ ORDER BY updated DESC` (limit 1 via maxResults MCP parameter, not in JQL).

## Schedule
- morning: fetch
- heartbeat: watch (--since today)
- heartbeat-maintenance: health
- eod: skip (worklog check stays directly in EOD)
