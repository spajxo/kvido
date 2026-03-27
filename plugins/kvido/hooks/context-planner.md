# Planner Rules

## Source Dispatch

If source plugins are installed (check via `kvido discover-sources`), include gatherer in your dispatch output.
Gatherer fetches all configured sources and returns findings as NL stdout output. Heartbeat delivers each finding as a separate notification.

## Triage

Include triager in your dispatch output. Triager agent manages the full triage lifecycle — reading tasks, evaluating relevance, and preparing items for user approval. Planner does not manage triage counts or detail; triager handles that independently.

## Notification Levels

Gatherer suggests urgency for each finding in its output. Heartbeat makes the final delivery decision:
- `silent`: Log only, no Slack delivery
- `batch`: Queue for digest, flush when focus mode ends or on next planner iteration
- `immediate`: Deliver promptly

Decide based on: current focus (`kvido current get`), time, sender, event type, whether action is required.

### Focus mode
Read `skills.planner.focus_mode.enabled` via `kvido config`. Check calendar — focus event running → suppress immediate to batch.

## Maintenance Tasks

Recurring (max 1 per day each, check last run timestamp via `kvido state get planner.maintenance.last_<agent>`):

| Task | Trigger | Action |
|------|---------|--------|
| Librarian | Not yet run today | Include in dispatch output |
| Enricher | Oldest project in memory/projects/ > 7 days | Include in dispatch output with project param |
| Self-improver | Not yet run today | Include in dispatch output |
| Scout | Not yet run today + interest topics configured | Include in dispatch output |

### Checks (include as notifications in output)

| Check | Condition | Action |
|-------|-----------|--------|
| Stale workers | in-progress > 10min | Tell heartbeat to notify about stale worker |
| Triage overflow | triage >= 10 | Tell heartbeat to notify about triage overflow |
| Backlog stale | todo low priority > 30 days | Suggest cleanup (low urgency) |

### Periodic (check timestamps via `kvido state get planner.<key>`)
- State hygiene: current.md WIP sync with Jira
- Git sync (> 2h): commit + push
- Archive rotation (> 7d): journals > 14d, weekly > 8w, decisions > 90d

## Journal Format

When creating a journal (triggered by scheduled rules):

```
# Journal — YYYY-MM-DD

## Summary
## Work Done
## Goals Progress
## MRs
## Blockers & Issues
## Token Usage
## Unfinished Work
## Tomorrow
```

Write to memory/journal/YYYY-MM-DD.md.

## Weekly Summary Format

When creating weekly summary (triggered by scheduled rules):

```
# Weekly Summary — YYYY-Www

## Highlights
## Per Project
## MRs
## Blockers & Carry-forward
## Backlog Stats
## Next Week
```

Write to memory/weekly/YYYY-Www.md.
