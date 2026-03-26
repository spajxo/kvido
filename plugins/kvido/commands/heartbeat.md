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

## Step 1: Set up cron (once per session only)

Call `CronList`. If no job contains the word `heartbeat`, call `CronCreate`:
- `cron`: `*/10 * * * *` (default 10m — adaptive interval will switch based on context)
- `recurring`: `true`
- `prompt`: `/kvido:heartbeat`

After creating the cron, save the job ID via `kvido state set heartbeat.cron_job_id "<job_id>"` and `kvido state set heartbeat.active_preset "10m"`.

Create the cron silently — print nothing unless an error occurs.

---

## Step 2: Init

Run:

```bash
kvido heartbeat
```

Output: `TIMESTAMP`, `ITERATION`, `NIGHT`, `ZONE`, `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `INTERACTION_AGO_MIN`, `OWNER_USER_ID`, `SLEEP_ACTIVE`, `SLEEP_UNTIL`, `CHAT_MESSAGES_START...CHAT_MESSAGES_END`, `DISPATCH_EVENTS_START...DISPATCH_EVENTS_END`.

Messages in `CHAT_MESSAGES` block are in `--heartbeat` format: one line per message, empty line between top-level messages: `ts=... user:|bot: text="..." [reactions=emoji1,emoji2] [reply_count=N] [latest_reply=...]`. Thread replies are under their top-level message with prefix `  ┗` (max 5 replies). Empty block = no messages.

The `user:` prefix means the message is from the workspace owner (you). The `bot:` prefix means the message is from anyone else (bot or other user). `OWNER_USER_ID` contains the resolved Slack user ID (from config or cached state). If `OWNER_USER_ID` is empty, annotation is disabled and messages retain the raw `user=<ID>` format — use `SLACK_USER_ID` from `.env` or `OWNER_USER_ID` from heartbeat output to compare manually.

The script automatically: increments iteration_count, sets last_heartbeat, reads Slack DM, reads dispatch events from event bus.

Read current state via `kvido current get`. Review recent activity via `kvido log list --today --format human --limit 20`.

### Recovery check

Use `TaskList` to list all existing tasks. Mark all `in_progress` tasks from a previous session as `completed` (agent process is gone from previous session). Pending tasks with unsatisfied `blockedBy` unblock automatically.

Exception: for `worker:*` in_progress tasks, also run `kvido task move <slug> failed` to mark the **local** task file as failed (worker tracks state via local task files independently; the TaskList entry still goes to `completed` like all others).

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
   - Cancel ("cancel <slug>"):
     ```bash
     kvido task note <slug> "Cancelled via chat"
     kvido task move <slug> cancelled
     ```
   - Simple status questions answerable from `kvido current get` and `kvido log list --today`

   For trivial: compose response, create `notify:chat:<ts>` task via `TaskCreate` (mark in_progress via `TaskUpdate`), deliver via `kvido slack reply dm <ts> chat --var message="<response>"` (use the message `ts` as the thread root — this threads the reply under the original message), mark task completed via `TaskUpdate`. Log: `kvido log add chat inline --message "<summary>"`

   **Non-trivial** — requires MCP lookup, research, or task creation:
   - If no active `chat:*` task:
     - `TaskCreate` subject `chat:<ts>` (stays `pending` — actual dispatch happens in Step 4 unified loop)
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
   - Since the agent has already finished, proceed to **Step 3c** for output processing and inline delivery
   - After delivery is processed, mark chat task as `completed` via `TaskUpdate`
   - Check for `pending` chat tasks -- if any exist, dispatch next one (FIFO) -- but only AFTER delivery is processed for the completed task

---

## Step 3b: Triage Task Creation & Reactions Polling

### Creating triage tasks

Triage TODOs are created in Step 3c when heartbeat delivers a `triage-item` notification through `kvido slack`. The returned `ts` is written into `triage:<slug>` TODO description. No CHAT_MESSAGES scanning needed for triage creation.

### Polling reactions

Use `TaskList` to find all `triage:*` tasks (not completed). Build JSON input and delegate to bash:

```bash
# Build input: [{"slug":"fix-auth-bug","ts":"1773..."},...]
echo "$TRIAGE_JSON" | kvido triage-poll
```

Output: `[{"slug":"fix-auth-bug","result":"approved|rejected|pending"},...]`

For each result:
- `approved` → `kvido log add triage approved --message "<slug> approved -> todo"`, mark `triage:<slug>` task completed via `TaskUpdate`
- `rejected` → `kvido log add triage rejected --message "<slug> rejected -> cancelled"`, mark task completed via `TaskUpdate`
- `pending` → skip

---

## Step 3c: Agent Output Processing & Delivery

When a background agent completes (detected via `TaskList` — task status is `in_progress` but agent has returned result), process its output and deliver directly from heartbeat via `kvido slack`.

### Delivery rules

Load delivery rules from installed plugins:

```bash
kvido context heartbeat
```

Heartbeat is responsible for parsing agent output into structured fields, deciding notification level, choosing template, and calling `kvido slack`. Apply the rules from the assembled context. Plugin-contributed rules extend or override defaults.

### Common pattern (all agent completions)

1. Read agent's NL output (returned by Agent tool)
2. Parse `total_tokens` + `duration_ms` from `<usage>` tag → `kvido log add <type> execute --tokens ... --duration_ms ... --message "<summary>"`
3. `TaskCreate` subject `notify:<type>:<id>`, then `TaskUpdate` status `in_progress`
4. Apply delivery rules → deliver via `kvido slack` → mark task completed via `TaskUpdate`
5. Mark agent task as completed via `TaskUpdate`

### Per-agent specifics

| Agent | Parse fields | Template | Level | Extra |
|-------|-------------|----------|-------|-------|
| chat-agent | `Reply`, `Thread`, `Type` | `chat` | always `immediate` | Extract `ORIGINAL_TS` from task subject `chat:<ts>`. If `Thread` non-empty: `kvido slack reply dm <Thread> chat --var message="<Reply>"`. If `Thread` empty (top-level): `kvido slack reply dm <ORIGINAL_TS> chat --var message="<Reply>"`. After delivery, check for `pending` chat tasks → dispatch next (FIFO) |
| worker | `Result`, `Task`, `Type`, `Source` | `worker-report` | `high` for error, else `normal` | — |
| other | template variables per agent | agent name as template, fallback `event` | per delivery rules | Most agents now communicate via event bus. When falling back to `event`, set `--var severity_bar=:large_yellow_circle:` as default |

### Batch flush

Flush `notify:*` tasks with `pending` status (via `TaskList`) when: planner iteration runs, or focus mode switches off. Re-deliver stored template+vars via `kvido slack`. On failure, leave `pending` for next flush.

---

## Step 4: Dispatch Loop

Parse `DISPATCH_EVENTS` block from heartbeat.sh output. Each line is a JSON event with `type` and `data` fields.

For each dispatch event (single pass — new events emitted during this tick are picked up on the NEXT tick):

### dispatch.planner
If no `planner` task pending/in_progress:
- `TaskCreate` subject `planner`
- Dispatch planner agent (foreground — wait for completion)
- Log: `kvido log add heartbeat dispatch --message "planner"`

### dispatch.gather
If no `gatherer` task pending/in_progress:
- `TaskCreate` subject `gatherer`
- Dispatch gatherer agent (`run_in_background: true`)
- Log: `kvido log add heartbeat dispatch --message "gatherer"`

### dispatch.notify, dispatch.triage, dispatch.briefing
If no `notifier` task pending/in_progress:
- `TaskCreate` subject `notifier`
- Dispatch notifier agent (`run_in_background: true`)
- Pass dispatch event types as context (so notifier knows whether to process triage, briefing, etc.)
- Log: `kvido log add heartbeat dispatch --message "notifier"`

### dispatch.worker
Parse slug from event data. If no `worker:*` task pending/in_progress:
- `kvido task read "$slug"` → get SIZE, PRIORITY, SOURCE_REF, INSTRUCTION
- If SOURCE_REF is set: `kvido slack reply "<SOURCE_REF>" chat --var message="Task accepted: <slug>. Working on it..."`
- `TaskCreate` subject `worker:<slug>`
- `kvido task move "$slug" in-progress`
- Dispatch worker agent (`run_in_background: true`)
- Log: `kvido log add heartbeat dispatch --message "worker:<slug>"`

### dispatch.agent
Parse agent name and params from event data. If no `maintenance:<agent>` task pending/in_progress:
- Verify `agents/<agent>.md` exists
- `TaskCreate` subject `maintenance:<agent>`
- If another `maintenance:*` task is pending/in_progress, set `addBlockedBy`
- Dispatch named agent (`run_in_background: true`)
- Log: `kvido log add heartbeat dispatch --message "maintenance:<agent>"`

### Chat dispatch (from Step 3)
Non-trivial chat from Step 3 still creates `chat:<ts>` tasks. These are dispatched here alongside event bus dispatches.

If `chat:*` task is `pending` with no blockers:
- `TaskUpdate` → `in_progress`
- Dispatch chat-agent
- Log: `kvido log add heartbeat dispatch --message "chat:<ts>"`

After processing all dispatch events:
```bash
kvido event ack --consumer heartbeat
```

**Single pass:** Dispatch events emitted by agents during this tick are picked up on the NEXT heartbeat tick. No loop, no chaining within a tick.

---

## Step 5: Adaptive Interval

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
| Dispatching agent when same-group task is pending/in_progress | Use `blockedBy` dependencies, dispatch loop skips blocked tasks |
| Creating maintenance tasks directly | Maintenance dispatch via event bus — planner emits `dispatch.agent` events |
| Forgetting to mark orphaned tasks on recovery | All `in_progress` tasks from previous session must be cleaned up in Step 2 |
| Outputting verbose text when nothing happened | Silent exit is default. No output = nothing to report. |
| Not updating `last_chat_ts` after processing | Always `kvido state set heartbeat.last_chat_ts` after chat handling |
| Using `--source "github#NN"` when creating tasks from user DM | Use `--source slack --source-ref "github#NN"` — source=slack routes to `todo/`, source=github#NN routes to `triage/` |

## Critical Rules

- **NEVER output if nothing to report.** Silent exit is default.
- **Extremely brief.** One line per event.
- **State-first.** Read from files, write to files.
- **Time from system.** `date -Iseconds`.
- **Task tools (`TaskCreate`/`TaskList`/`TaskUpdate`) are the single source of truth** for dispatch tracking. No file-based locks.
- **Concurrency via dependencies.** Same-group tasks use `blockedBy`. Max 1 concurrent per group (maintenance, worker, chat). Planner runs in parallel with all groups. Dispatch loop skips tasks with unresolved blockers.
- **Notify TODOs are ephemeral.** Completed notify TODOs can be cleaned up after logging.
