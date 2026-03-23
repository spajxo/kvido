# Jira Heartbeat Rules

## Notification Templates
- New ticket assigned → template: triage-item, level: immediate
- Ticket status change (assignee=me) → template: event, level: immediate
- Comment on my ticket → template: event, level: batch
- Ticket closed → level: silent
