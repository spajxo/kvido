# Planner Rules

## Change Detection

Compare collected data against reported events via `kvido planner-state event check <key>`.
Already reported → skip (dedup). New → notify and record with `kvido planner-state event add <key>`.

### Notification levels

| Level | Output format |
|-------|--------------|
| silent | Log via kvido log add only |
| batch | Output: Event (batch): <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: normal. |
| immediate | Output: Event: <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: high. |

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

Recurring (max 1 per day each, check last_*_date via `kvido planner-state last-run get <task>`):

| Task | Trigger | Instruction |
|------|---------|-------------|
| Librarian | Not yet run today (check `last_librarian_date`, max 1/day) | `Dispatch: librarian` |
| Enricher | Oldest project in memory/projects/ > 7 days | `Dispatch: project-enricher PROJECT=<project>` |
| Self-improver | Not yet run today | `Dispatch: self-improver` |

### Checks (output as Event:)

| Check | Condition | Output |
|-------|-----------|--------|
| Stale workers | in-progress > 10min | Event: Stale worker — <slug>. Urgency: normal. |
| Triage overflow | triage >= 10 | Event: Triage overflow — <N> items. Urgency: normal. |
| Backlog stale | todo low priority > 30 days | Event: suggestion |

### Periodic (check timestamps via `kvido planner-state timestamp get <key>`)
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

## Output Format

See **Agent Output Grammar** in the Orchestration Contract (session context) for the canonical prefix format. The planner SKILL.md Output Format section defines the full specification.
