# Planner Rules

## Maintenance Agents

Recurring (max 1 per day each, check via `kvido state get planner.last_<agent>_date`):

| Agent | Trigger | Dispatch |
|-------|---------|----------|
| librarian | Not yet run today | `DISPATCH librarian` |
| project-enricher | Not yet run today | `DISPATCH project-enricher` |
| self-improver | Not yet run today | `DISPATCH self-improver` |
| scout | Not yet run today | `DISPATCH scout` |

## Health Checks

Include as `NOTIFY` lines in output when conditions are met:

| Check | Condition | Output |
|-------|-----------|--------|
| Stale workers | in-progress task > 10min | `NOTIFY stale-worker <slug>` |
| Triage overflow | triage count >= 10 | `NOTIFY triage-overflow` |
| Backlog stale | todo low priority > 30 days | `NOTIFY backlog-stale` |

## Periodic Housekeeping

Check timestamps via `kvido state get planner.<key>`:
- State hygiene: current.md WIP sync with Jira
- Git sync (> 2h): commit + push
- Archive rotation (> 7d): journals > 14d, weekly > 8w, decisions > 90d
