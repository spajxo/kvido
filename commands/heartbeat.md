---
description: Heartbeat — orchestrator, chat check, unified agent dispatch, log, adaptive interval
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronCreate, CronList, CronDelete, TaskCreate, TaskList, TaskUpdate, TaskGet, TaskOutput, mcp__claude_ai_Slack__slack_read_channel
---

# Heartbeat

Runs automatically via `/loop`. Be extremely brief -- no output if nothing to report.

## Tone Guidelines

Tone and style per `memory/persona.md` (section Heartbeat). If persona missing, be brief and factual.

---

## Step 0: Verify kvido CLI

If `command -v kvido` fails, tell the user to run `/kvido:setup` first and stop.

## Step 1: Verify loop is running (first tick only)

The recurring cron is created by `/loop` at session start (via `kvido` CLI wrapper). On the **first heartbeat tick** (detected: `CRON_JOB_ID` from heartbeat.sh output is empty or doesn't match any job in `CronList`):

1. Call `CronList` and find the job whose prompt contains `heartbeat`
2. If found: `kvido state set heartbeat.cron_job_id "<job_id>"` + `kvido state set heartbeat.active_preset "10m"`
3. If NOT found (user ran `/kvido:heartbeat` directly without `/loop`): create the cron manually:
   - `cron`: `*/10 * * * *`, `recurring`: `true`, `prompt`: `/kvido:heartbeat`
   - Save job ID and preset to state

On subsequent ticks (`CRON_JOB_ID` is set and non-empty), skip this step entirely.

---

## Step 2: Init

Run:

```bash
kvido heartbeat
```

Output: `TIMESTAMP`, `ITERATION`, `NIGHT`, `ZONE`, `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `PLANNER_DUE`, `INTERACTION_AGO_MIN`, `OWNER_USER_ID`, `SLEEP_ACTIVE`, `SLEEP_UNTIL`, `CHAT_MESSAGES_START...CHAT_MESSAGES_END`.

Messages in `CHAT_MESSAGES` block are in `--heartbeat` format: one line per message, empty line between top-level messages: `ts=... user:|bot: text="..." [reactions=emoji1,emoji2] [reply_count=N] [latest_reply=...]`. Thread replies are under their top-level message with prefix `  ┗` (max 5 replies). Empty block = no messages.

The `user:` prefix means the message is from the workspace owner (you). The `bot:` prefix means the message is from anyone else (bot or other user). `OWNER_USER_ID` contains the resolved Slack user ID (from config or cached state). If `OWNER_USER_ID` is empty, annotation is disabled and messages retain the raw `user=<ID>` format — use `SLACK_USER_ID` from `.env` or `OWNER_USER_ID` from heartbeat output to compare manually.

The script automatically: increments iteration_count, sets last_heartbeat, reads Slack DM.

Read current state via `kvido current get`. Review recent activity via `kvido log list --today --format human --limit 20` on planner ticks (`PLANNER_DUE=true`), or `--limit 5` on non-planner ticks.

### Recovery check

Use `TaskList` to list all existing tasks. Mark all `in_progress` tasks from a previous session as `completed` (agent process is gone from previous session). Pending tasks with unsatisfied `blockedBy` unblock automatically.

Exception: for `worker:*` in_progress tasks, also run `kvido task move <id> failed` to mark the **local** task file as failed (worker tracks state via local task files independently; the TaskList entry still goes to `completed` like all others). The numeric ID is in the subject after `worker:` (e.g. subject `worker:42` → ID `42`).

---

## Step 3: Chat Check

1. **Filter new messages:** Messages in `CHAT_MESSAGES` block with prefix `user:` (owner messages), `ts` > `last_chat_ts`. Skip messages with prefix `bot:` (not from owner). If messages are in raw `user=<ID>` format (annotation disabled), compare the ID against `OWNER_USER_ID` from heartbeat output to identify owner messages.

2. **Check for active chat agent:** Use `TaskList` -- look for any `chat:*` task with status `in_progress`.

3. **Classify and handle new message:**

   Read the message and decide: **trivial** (answer inline) or **non-trivial** (dispatch subagent).

   **THREAD_TS derivation:** If message has field `thread_ts` (is thread reply) -- `THREAD_TS = thread_ts value`. If no `thread_ts` (top-level message) -- `THREAD_TS = ""`. **Never pass `ts` as THREAD_TS.**

   **Trivial** — heartbeat handles inline, no agent dispatch:
   - Greetings, confirmations, thanks ("hi", "ok", "thanks", "got it", "great")
   - Sleep mode ("going to sleep", "good night", "pause", "sleep"):
     ```bash
     SLEEP_UNTIL=$(date -d "tomorrow 06:00" -Iseconds)  # or parsed time
     kvido state set heartbeat.sleep_until "$SLEEP_UNTIL"
     ```
   - Turbo mode ("turbo"):
     ```bash
     TURBO_UNTIL=$(date -d "+30 min" -Iseconds)  # or parsed duration
     kvido state set heartbeat.turbo_until "$TURBO_UNTIL"
     ```
   - Cancel ("cancel <id>" or "cancel <slug>"):
     ```bash
     kvido task note <id|slug> "Cancelled via chat"
     kvido task move <id|slug> cancelled
     ```
   - Simple status questions answerable from `kvido current get` and `kvido log list --today`

   For trivial: compose response, create `notify:chat:<ts>` task via `TaskCreate` (mark in_progress via `TaskUpdate`), deliver via `kvido slack reply dm <ts> chat --var message="<response>"` (use the message `ts` as the thread root — this threads the reply under the original message), mark task completed via `TaskUpdate`. Log: `kvido log add chat inline --message "<summary>"`

   **Non-trivial** — requires MCP lookup, research, or task creation:
   - If no active `chat:*` task:
     - `TaskCreate` subject `chat:<ts>` (stays `pending` — dispatched in Step 5)
   - If active `chat:*` task exists:
     - Send ack: `kvido slack reply dm <ts> chat --var message="One moment..."` (thread under the new message)
     - `TaskCreate` subject `chat:<ts>` with `addBlockedBy` pointing to the active chat task (stays `pending`)

   **Task creation from user DM:** When the chat-agent (or heartbeat inline) creates a task from a user's Slack DM request, always use `--source slack`. If the request references a GitHub issue or PR, pass it via `--source-ref "github#NN"` (not `--source`). This ensures user-initiated tasks go directly to `todo/` (bypassing triage).

   ```bash
   # Correct
   kvido task create --title "..." --instruction "..." --source slack --source-ref "github#93"
   # Wrong — would route to triage/
   kvido task create --title "..." --instruction "..." --source "github#93"
   ```

   Update: `kvido state set heartbeat.last_chat_ts "<ts>"` + `kvido state set heartbeat.last_interaction_ts "$(date -Iseconds)"`

4. **Agent completion:** When a dispatched chat-agent completes (background task finishes), in the next heartbeat iteration:
   - `TaskList` -- find `chat:*` tasks with status `in_progress`
   - Since the agent has already finished, proceed to **Step 6** for output processing and delivery
   - After delivery is processed, mark chat task as `completed` via `TaskUpdate`
   - Check for `pending` chat tasks -- if any exist, dispatch next one (FIFO) -- but only AFTER delivery is processed for the completed task

---

## Step 4: Run Planner

Run the planner as a **foreground subagent** (wait for completion). The planner evaluates state, schedules, and pending work, then returns natural language output describing what should happen this tick.

**Throttle:** `heartbeat.sh` outputs `PLANNER_DUE=true|false` based on `planning_interval` config (default 3 — every 3rd iteration). If `PLANNER_DUE=false`, skip Step 4 entirely and proceed to Step 5 (dispatch only previously queued agents like pending `chat:*` tasks).

If `PLANNER_DUE=true` and no `planner` task pending/in_progress:
1. `TaskCreate` subject `planner`
2. `TaskUpdate` → `in_progress`
3. Dispatch planner agent (foreground — wait for completion)
4. Read planner's NL output
5. Log: `kvido log add heartbeat dispatch --message "planner"` with token/duration from `<usage>` tag
6. Mark planner task as `completed` via `TaskUpdate`

The planner output uses structured lines:

```
DISPATCH gatherer
DISPATCH triager
DISPATCH worker 86 model=sonnet
DISPATCH librarian
DISPATCH_AFTER triager gatherer
NOTIFY stale-worker 42
```

- `DISPATCH <agent>` — dispatch agent (parallel by default)
- `DISPATCH worker <id> [model=<model>]` — dispatch worker for specific task (by numeric ID); optional `model=` token selects model (haiku/sonnet/opus, default sonnet)
- `DISPATCH_AFTER <agent> <after-agent>` — sequential ordering
- `NOTIFY <type> [detail]` — heartbeat handles notification directly
- `No dispatches needed.` — skip Steps 5 and 6

If the planner returns nothing or "No dispatches needed.", skip planner-originated dispatches in Step 5. Still proceed to Step 5 for pending `chat:*` tasks and to Step 6 for completed background agents.

---

## Step 5: Dispatch Agents

Parse planner output from Step 4 line by line. Handle each line type:

### `DISPATCH <agent>` — parallel by default

For each `DISPATCH` line, dispatch the agent with `run_in_background: true`:

1. `TaskCreate` subject `<agent>` (or `worker:<id>`, `maintenance:<agent>`)
2. `TaskUpdate` → `in_progress`
3. Dispatch agent (`run_in_background: true`)
4. Log: `kvido log add heartbeat dispatch --message "<agent>"`

**Worker specifics:** `DISPATCH worker <id> [model=<model>]` — parse the numeric task ID and optional `model=` token from the DISPATCH line (default: `sonnet` if absent). Read task first (`kvido task read "$id"`), if SOURCE_REF is set send ack via `kvido slack reply`, then `kvido task move "$id" in-progress`. Pass the resolved model name as the `model` parameter to the Agent tool when dispatching the worker. Pass `TASK_ID` (numeric), `TASK_SLUG`, and `TITLE` (from task read output) to the worker agent.

**Maintenance specifics:** If another `maintenance:*` task is pending/in_progress, set `addBlockedBy`.

### `DISPATCH_AFTER <agent> <after-agent>` — sequential

Use `addBlockedBy` on the `TaskCreate` for the dependent agent. Wait for the dependency to complete before dispatching.

### `NOTIFY <type> [detail]` — heartbeat handles directly

Deliver notification via `kvido slack` using appropriate template. No agent dispatch needed.

#### chat (from Step 3)
Non-trivial chat from Step 3 creates `chat:<ts>` tasks. These are dispatched here alongside planner-requested agents.

If `chat:*` task is `pending` with no blockers:
- `TaskUpdate` → `in_progress`
- Dispatch chat-agent (`run_in_background: true`)
- Log: `kvido log add heartbeat dispatch --message "chat:<ts>"`

---

## Step 6: Collect Outputs & Deliver

When background agents complete (detected via `TaskList` — task was `in_progress` but agent has returned result), collect their NL outputs and deliver via Slack.

### Delivery rules

Heartbeat is the single owner of Slack message delivery. No agent or worker may call `kvido slack send|reply|edit` directly. They return NL output; heartbeat parses and delivers.

#### Chat ack lifecycle
When heartbeat detects a new chat message:
1. `kvido slack react <ts> eyes` — immediate ack
2. Dispatch chat-agent
3. Deliver chat-agent reply
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
| planner | `:hourglass_flowing_sand: Planner scanning...` | `:white_check_mark: Planner done — <count> dispatches` | `:x: Planner failed — <error>` |

Chat-agent uses ack reactions only (see above), not status edits.

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
| chat-agent | `chat` | always immediate | Extract `ORIGINAL_TS` from task subject `chat:<ts>`. If agent returns `Thread` non-empty: `kvido slack reply dm <Thread> chat --var message="<Reply>"`. If `Thread` empty: `kvido slack reply dm <ORIGINAL_TS> chat --var message="<Reply>"`. After delivery, check for `pending` chat tasks → dispatch next (FIFO) |
| worker | `worker-report` | `high` for error, else `normal` | — |
| gatherer | `event` | per urgency rules | Parse findings, each as separate notification |
| triager | `triage-item` | `immediate` | For triage items needing user attention, save returned `ts` to task frontmatter: `kvido task update <id> triage_slack_ts <ts>` |
| maintenance | agent name as template, fallback `event` | per delivery rules | When falling back to `event`, set `--var severity_bar=:large_yellow_circle:` as default |
| scout | `event` | per scout's suggested urgency in each finding block | Split output by `SCOUT FINDING:` markers — deliver each finding as a separate notification |

### Digest threading

Low-urgency notifications are batched. Flush batched `notify:*` tasks with `pending` status (via `TaskList`) when: planner iteration runs, or focus mode switches off. Re-deliver stored template+vars via `kvido slack`. On failure, leave `pending` for next flush.

---

## Step 7: Adaptive Interval

`heartbeat.sh` returns `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `TURBO_ACTIVE/UNTIL`, `SLEEP_ACTIVE/UNTIL`.

| Mode | Trigger | TARGET_PRESET | Behavior |
|------|---------|---------------|----------|
| Sleep | "going to sleep" in DM | `sleep` | `CronDelete` old → `CronCreate` one-shot at `SLEEP_UNTIL` (default 06:00). No planner/worker dispatch. After wake: normal flow. |
| Turbo | "turbo" in DM | `1m` | 30min burst. After expiry: `heartbeat.sh` auto-clears, returns normal. |
| Normal | — | decay-based | Based on interaction age (config `skills.heartbeat.decay.*`). |

If `TARGET_PRESET != ACTIVE_PRESET`:
1. **Lazy cron reconciliation:** `CronList` → verify `CRON_JOB_ID` is valid in the current session
   - If `CRON_JOB_ID` not in list: find actual heartbeat cron job (prompt contains "heartbeat")
   - If found: use actual ID, update state via `kvido state set heartbeat.cron_job_id "<actual_id>"`
   - If no heartbeat cron exists: log orphaned run, skip interval change
2. `CronDelete` old job → `CronCreate` new with matching expression
3. `kvido state set heartbeat.cron_job_id` + `heartbeat.active_preset`
4. `kvido log add heartbeat adaptive --message "interval {ACTIVE} -> {TARGET}"`

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Passing message `ts` as `THREAD_TS` | `THREAD_TS` = `thread_ts` field (parent), never `ts` (message itself) |
| Dispatching chat-agent for trivial messages ("ok", "thanks") | Classify first — greetings, acks, sleep/turbo/cancel are always inline |
| Dispatching agent when same-group task is pending/in_progress | Use `blockedBy` dependencies, dispatch skips blocked tasks |
| Forgetting to mark orphaned tasks on recovery | All `in_progress` tasks from previous session must be cleaned up in Step 2 |
| Outputting verbose text when nothing happened | Silent exit is default. No output = nothing to report. |
| Not updating `last_chat_ts` after processing | Always `kvido state set heartbeat.last_chat_ts` after chat handling |
| Using `--source "github#NN"` when creating tasks from user DM | Use `--source slack --source-ref "github#NN"` — source=slack routes to `todo/`, source=github#NN routes to `triage/` |
| Using event bus commands (`kvido event emit/read/ack`) | Event bus is removed — planner returns NL, heartbeat interprets directly |
| Dispatching notifier agent separately | Heartbeat owns ALL Slack delivery — no separate notifier dispatch |

## Critical Rules

- **NEVER output if nothing to report.** Silent exit is default.
- **Extremely brief.** One line per event.
- **State-first.** Read from files, write to files.
- **Time from system.** `date -Iseconds`.
- **Task tools (`TaskCreate`/`TaskList`/`TaskUpdate`) are the single source of truth** for dispatch tracking. No file-based locks.
- **Concurrency via dependencies.** Same-group tasks use `blockedBy`. Max 1 concurrent per group (maintenance, worker, chat). Planner runs foreground. Other agents run in background.
- **Notify TODOs are ephemeral.** Completed notify TODOs can be cleaned up after logging.
- **Heartbeat owns ALL delivery.** No agent sends Slack messages directly. Chat-agent delivery in Step 3/6, all other agent outputs in Step 6.
- **No event bus.** No `kvido event emit/read/ack`.
- **Planner is the sole scheduler.** Heartbeat never decides which agents to dispatch — it only parses `DISPATCH` / `NOTIFY` lines from planner output.
