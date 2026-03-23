# Jira Planning Rules

## Event Dedup Keys
- jira:<key>:status_<status> — ticket status change
- jira:<key>:comment_<count> — ticket comment count change

## Triage Detection
New ticket assigned to me, not in backlog → triage item.
Dedup: check existing tasks with source=jira and source-ref=<KEY>.
