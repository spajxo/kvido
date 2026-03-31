---
name: heartbeat-deliver
description: Heartbeat Step 6 — collect agent outputs and deliver via Slack. Load when background agent tasks have completed this iteration.
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

#### Planner summary composition

After planner completes successfully, compose a structured summary and **edit** the status message (replacing `:hourglass_flowing_sand: Planner scanning...`) using the `planner-summary` template.

Gather data:

```bash
# Queue counts by priority
kvido task count todo       # total todo
kvido task list todo        # to find next-up task
kvido task count triage     # triage backlog
kvido task list in-progress # currently running workers
```

Build template vars:

| Var | Source | Example |
|-----|--------|---------|
| `iteration` | `ITERATION` from heartbeat.sh output | `245` |
| `dispatches` | Parsed `DISPATCH` lines from planner output — one per line, format `:arrow_forward: <agent/task-title> (<priority>, <size>)`. For `DISPATCH worker <id>`, use task title from `kvido task read <id>`. If no dispatches: `_nothing dispatched_` | `:arrow_forward: code-review-pr-161 (high, s)` |
| `queue_stats` | From `kvido task list todo --sort priority` — count total and breakdown by priority field. Format: `N todo (H high, M medium, L low)`. Omit zero-count priorities. | `6 todo (1 high, 3 medium, 2 low)` |
| `next_up` | Top task from `kvido task list todo --sort priority` — the first non-blocked, non-dispatched task. Format: `#<id> <title> (<priority>)`. If queue empty or all dispatched: `_queue empty_` | `#56 planner-full-task-snapshot (high)` |
| `triage_count` | `kvido task count triage` | `4` |
| `skipped` | Tasks planner explicitly noted as blocked/skipped — parsed from planner NL output (look for "blocked", "waiting", "skipped" phrasing). Format: `:no_entry_sign: #<id> <title> (<reason>)`. If none: pass empty string `""` | `:no_entry_sign: #33 config-unify (blocked by PR merge)` |
| `timestamp` | `date +%H:%M` | `09:34` |

Edit the status message with `planner-summary` template:

```bash
kvido slack edit dm <status_ts> planner-summary \
  --var iteration="<ITERATION>" \
  --var dispatches="<dispatches>" \
  --var queue_stats="<queue_stats>" \
  --var next_up="<next_up>" \
  --var triage_count="<triage_count>" \
  --var skipped="<skipped>" \
  --var timestamp="<HH:MM>"
```

Omit the `skipped` line from the template output by passing `skipped=""` when there are no skipped tasks — the template renders an empty line which is visually clean.

### Digest threading

Low-urgency notifications are batched. Flush batched `notify:*` tasks with `pending` status (via `TaskList`) when: planner iteration runs, or focus mode switches off. Re-deliver stored template+vars via `kvido slack`. On failure, leave `pending` for next flush.
