# Planner Rules

## Change Detection

Gatherers detect changes and emit events via the event bus using deduplication:
```
kvido event emit change.detected --dedup-key "source:key" --dedup-window 1h --data '{"title":"...","desc":"...","source":"...","reference":"..."}'
```

The dedup mechanism prevents redundant notifications for the same source within the window. Consumers (notifiers) subscribe to change.detected events and decide notification level.

### Notification levels

Urgency is now the notifier's responsibility when consuming events:
- `silent`: Log only (consumed but not notified)
- `batch`: Consume and queue, send in digests
- `immediate`: Consume and notify promptly

Decide based on: current focus (`kvido current get`), time, sender, event type, whether action is required.

### Focus mode
Read settings.json focus_mode. Check calendar — focus event running → suppress immediate to batch.

### Proactive alerts
Watch for stale MR reviews, WIP tickets with no activity, status changes. Decide level based on context.

## Triage

For triage items (max 3 per run):
1. Read task detail: kvido task read <slug>
2. Evaluate relevance and urgency
3. Clear request → output: Triage: <slug> '<title>' — <description>. Priority: <p>. Size: <s>. Assignee: <a>.
4. Unclear → output: Question: <slug> '<title>' — <question>. Urgency: normal.

Write note on task: kvido task note <slug> "Triage: sent for approval."

## Maintenance Tasks

Recurring (max 1 per day each, check last run timestamp via `kvido state get planner.maintenance.last_librarian`):

| Task | Trigger | Action |
|------|---------|--------|
| Librarian | Not yet run today | `kvido event emit dispatch.agent --data '{"agent":"librarian"}'` |
| Enricher | Oldest project in memory/projects/ > 7 days | `kvido event emit dispatch.agent --data '{"agent":"project-enricher","params":{"PROJECT":"<project>"}}'` |
| Self-improver | Not yet run today | `kvido event emit dispatch.agent --data '{"agent":"self-improver"}'` |

### Checks (output as Event:)

| Check | Condition | Output |
|-------|-----------|--------|
| Stale workers | in-progress > 10min | Event: Stale worker — <slug>. Urgency: normal. |
| Triage overflow | triage >= 10 | Event: Triage overflow — <N> items. Urgency: normal. |
| Backlog stale | todo low priority > 30 days | Event: suggestion |

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

## Event Emission

The planner communicates via the event bus. All significant outputs (change detection, triage decisions, maintenance tasks, checks) are emitted as events:

```
kvido event emit <type> --data '{}' [--producer planner] [--dedup-key <key> --dedup-window <duration>]
```

Standard event types:
- `change.detected` — Source change notification
- `dispatch.agent` — Dispatch instruction for an agent
- `triage.decision` — Triage classification result
- `planner.check.stale-worker` — Maintenance check output
- `planner.check.overflow` — Maintenance check output

Consumers subscribe to specific event types and handle delivery/notification as needed.
