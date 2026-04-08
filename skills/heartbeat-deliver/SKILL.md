---
name: heartbeat-deliver
description: This skill should be activated during heartbeat Step 6 when background agent tasks have completed during the current iteration. It collects agent NL outputs, classifies urgency, and delivers notifications via Slack using appropriate templates and threading rules.
---

When background agents complete (detected via `TaskList` — task was `in_progress` but agent has returned result), collect their NL outputs and deliver via Slack.

### Delivery rules

Heartbeat is the single owner of Slack message delivery. No agent or worker may call `kvido slack send|reply|edit` directly. They return NL output; heartbeat parses and delivers.

#### Chat ack lifecycle
When heartbeat detects a new chat message:
1. `kvido slack react <ts> eyes` — immediate ack
2. Dispatch chat
3. Deliver chat reply
4. `kvido slack unreact <ts> eyes` — remove ack

#### Digest threading
When agents return multiple findings in a single cycle:
- 1 finding → deliver as standalone
- 2+ findings → send digest parent via `kvido slack send ... digest`, then each finding as `kvido slack reply ... <digest_ts> event`

#### Batch flush threading
When flushing batched notifications:
- Send `batch-header` parent via `kvido slack send ... batch-header` → capture `ts`
- Each batched notification as `kvido slack reply ... <batch_ts> <template>`

#### Processing status edits
| Dispatch | Status message | On success | On failure |
|----------|---------------|------------|------------|
| worker | `:hourglass_flowing_sand: Working on <title>...` | `:white_check_mark: Done: <title> — <duration>` | `:x: Failed: <title> — <summary>` |
| planner | `:hourglass_flowing_sand: Planner scanning...` | `planner-summary` template (see Per-agent delivery) | `:x: Planner failed — <error>` |

Chat uses ack reactions only (see above), not status edits.

### Urgency classification

| Factor | Effect |
|--------|--------|
| Gatherer recommends "immediate" | high |
| calendar_event < 15min | high |
| Focus mode active | Suppress high → batch |
| Night hours | Suppress high → batch |
| Gatherer recommends "normal" | normal |
| Everything else | low |

### Notification levels

- **immediate** — deliver right now via `kvido slack`
- **high** — deliver now unless focus mode or night hours (then batch)
- **normal** — deliver now
- **low** — batch for next digest

### Common pattern (all agent completions)

1. Read agent's NL output (returned by Agent tool or `TaskOutput`)
2. Parse `total_tokens` + `duration_ms` from `<usage>` tag → `kvido log add <type> execute --tokens ... --duration_ms ... --message "<summary>"`
3. `TaskCreate` subject `notify:<type>:<id>`, then `TaskUpdate` status `in_progress`
4. Classify urgency → choose template → deliver via `kvido slack` → mark notify task completed via `TaskUpdate`
5. Mark agent task as completed via `TaskUpdate`

### Per-agent delivery

| Agent | Template | Level | Notes |
|-------|----------|-------|-------|
| chat | `chat` | always immediate | Extract `ORIGINAL_TS` from task subject `chat:<ts>`. If agent returns `Thread` non-empty: `kvido slack reply dm <Thread> chat --var message="<Reply>"`. If `Thread` empty: `kvido slack reply dm <ORIGINAL_TS> chat --var message="<Reply>"`. After delivery, check for `pending` chat tasks → dispatch next (FIFO) |
| planner | `planner-summary` | `normal` | See **Planner summary composition** below. Edit status message to `planner-summary` template result (replacing the `:hourglass_flowing_sand:` message). |
| worker | `worker-report` | `high` for error, else `normal` | Pass worker output (up to routing fields) as `--var message="..."`. If `Source:` is a Slack `ts`, reply in that thread. |
| gatherer | `event` | per urgency rules | Parse findings, each as separate notification |
| triager | `triage-item` | `immediate` | For triage items needing user attention, save returned `ts` to task frontmatter: `kvido task update <id> triage_slack_ts <ts>` |
| maintenance | agent name as template, fallback `event` | per delivery rules | When falling back to `event`, set `--var severity_bar=:large_yellow_circle:` as default |
| researcher | `event` | per researcher's suggested urgency in each finding block | Split output by `RESEARCHER FINDING:` markers — deliver each finding as a separate notification |
| ingest | `event` | `normal` | Parse `INGESTED:` line from output. Use `--var message="<INGESTED line>"`. |

#### Reviewer SCHEDULE_REVIEW handling

When a reviewer agent completes with `RESULT=FAIL`, scan the output for a `SCHEDULE_REVIEW:` line:

```
SCHEDULE_REVIEW: PR_NUMBER=<N> PR_URL=<url> after_task=<slug>
```

If found:

1. Parse `PR_NUMBER`, `PR_URL`, and `after_task` from the line.
2. Create a new code review task: `kvido task create --title "Code review: PR #<PR_NUMBER>" --instruction "Review PR #<PR_NUMBER> at <PR_URL> after fix by <after_task>. PR_NUMBER=<N> PR_URL=<url>" --source reviewer --priority medium --size s`
3. Move the task directly to `todo` (skip triage): `kvido task move <new-slug> todo`
4. Log: `kvido log add heartbeat schedule-review --message "PR #<N>: re-review task <new-slug> created, waiting for fix <after_task>"`

**Timing:** The new review task is created immediately when the FAIL result is delivered — the planner will schedule it naturally when the referenced fix worker task completes (it will see the todo task and the merged/closed PR). No blocking dependency is set in the task system; the planner observes PR state and task state as usual.

**Only on FAIL:** If reviewer output has `RESULT=PASS`, ignore any `SCHEDULE_REVIEW` line (should not be present, but guard defensively).

#### Chat query-save handling

When chat agent output contains `Save-offer: true`, after delivering the normal chat reply:

1. Extract `Save-title` and `Save-tags` from output.
2. Ask user via Slack reply in the same thread: `"Uložit tuhle analýzu do wiki jako '<Save-title>'?"`.
3. On next heartbeat, check for user reaction (✅ = yes, ❌ = no) or text reply.
4. If yes: `DISPATCH ingest` with the chat reply text as inline source, type `analysis`, title from `Save-title`, tags from `Save-tags`.
5. If no or no response after 2 heartbeat cycles: discard.

#### Planner summary composition

For detailed planner summary template vars and delivery, read `references/planner-summary-composition.md`.

### Digest threading

Low-urgency notifications are batched. Flush batched `notify:*` tasks with `pending` status (via `TaskList`) when: planner iteration runs, or focus mode switches off. Re-deliver stored template+vars via `kvido slack`. On failure, leave `pending` for next flush.
