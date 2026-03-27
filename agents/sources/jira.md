### Jira

> Config: `sources.jira.*` keys. Requires: `acli` CLI or Atlassian MCP.

#### Capabilities

**fetch:**
```bash
kvido jira [--since YYYY-MM-DD] [--project KEY]
```
Output: plain text, one block per project.

**MCP fallback (exit 10):**
1. Read project config via `kvido config --keys 'sources.jira.projects'`
2. For each project, get its JQL filter: `kvido config 'sources.jira.projects.<KEY>.filter'`
3. Call `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql(jql="<filter>", maxResults=20)`
4. Format output: `=== Project (N issues) ===` then `  KEY [status] summary` per issue

**watch:** Run fetch with `--since YYYY-MM-DD` (today). If exit 10, MCP fallback with `AND updated >= "<today>"` added to each JQL filter.

**triage-detect:** After fetch — new ticket assignee=me → dedup check:
```bash
kvido task list --source jira --format slug-title
```
If no matching task → create triage task:
```bash
kvido task create --title "[KEY] summary" --instruction "Jira ticket: summary. Key: KEY" --source jira --source-ref KEY --priority medium
```

**health:**
```bash
acli jira info 2>/dev/null && echo "OK" || echo "FAIL: acli"
```
Fallback: Atlassian MCP searchJiraIssuesUsingJql with test JQL (limit 1).

#### Schedule
- morning: fetch
- heartbeat: watch (--since today)
- heartbeat-maintenance: health
- eod: skip (worklog check stays directly in EOD)

#### Setup
| Prerequisite | Check |
|---|---|
| acli or Atlassian MCP | `command -v acli` or MCP available |
| sources.jira.projects | `kvido config --keys 'sources.jira.projects'` returns non-empty |

#### Dedup Keys
- `jira:<key>:status_<status>` — ticket status change
- `jira:<key>:comment_<count>` — ticket comment count change

#### Triage Detection
New ticket assigned to me, not in backlog → triage item.
Dedup: check existing tasks with source=jira and source-ref=<KEY>.

#### Notification Rules
- New ticket assigned → template: triage-item, level: immediate
- Ticket status change (assignee=me) → template: event, level: immediate
- Comment on my ticket → template: event, level: batch
- Ticket closed → level: silent
