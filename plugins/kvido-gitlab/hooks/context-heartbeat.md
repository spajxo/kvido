# GitLab Heartbeat Rules

## Notification Templates
- MR CI failure → template: event, level: immediate
- MR approved/merged → template: event, level: normal
- New MR assigned for review → template: triage-item, level: immediate
- MR comment → template: event, level: batch
