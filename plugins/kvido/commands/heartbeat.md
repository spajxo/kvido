---
description: Heartbeat — orchestrator, chat check, worker dispatch, log, adaptive interval
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronCreate, CronList, CronDelete, TodoWrite, TodoRead, mcp__claude_ai_Slack__slack_read_channel
---

**Language:** Communicate in the language set in memory/persona.md. Default: English.

> **File paths:** All `state/` and `memory/` paths below resolve to `$KVIDO_HOME/state/` and `$KVIDO_HOME/memory/` (default: `~/.config/kvido`). Config via `kvido config 'key'`.

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

After creating the cron, save the job ID to `state/heartbeat-state.json` via `kvido heartbeat-state set cron_job_id "<job_id>"` and `kvido heartbeat-state set active_preset "10m"`.

Create the cron silently — print nothing unless an error occurs.

---

## Step 2: Init

Run:

```bash
kvido heartbeat
```

Output: `TIMESTAMP`, `ITERATION`, `NIGHT`, `ZONE`, `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `INTERACTION_AGO_MIN`, `PLANNER_DUE`, `NEXT_TASK`, `OWNER_USER_ID`, `SLEEP_ACTIVE`, `SLEEP_UNTIL`, `CHAT_MESSAGES_START...CHAT_MESSAGES_END`.

Messages in `CHAT_MESSAGES` block are in `--heartbeat` format: one line per message, empty line between top-level messages: `ts=... user:|bot: text="..." [reactions=emoji1,emoji2] [reply_count=N] [latest_reply=...]`. Thread replies are under their top-level message with prefix `  ┗` (max 5 replies). Empty block = no messages.

The `user:` prefix means the message is from the workspace owner (you). The `bot:` prefix means the message is from anyone else (bot or other user). `OWNER_USER_ID` contains the resolved Slack user ID (from config, cached state, or auto-detected via `auth.test`).

The script automatically: increments iteration_count, sets last_quick, reads Slack DM, checks worker queue.

Read `state/current.md` for context. Review recent activity via `kvido log list --today --format human --limit 20`.

### Cron reconciliation

`CRON_JOB_ID` from heartbeat-state.json may be stale (from a previous session — cron jobs are session-only). Call `CronList` and compare:
- If `CRON_JOB_ID` is not in the current cron list, find the actual heartbeat cron job (prompt contains "heartbeat")
- If found: update state with the actual job ID via `kvido heartbeat-state set cron_job_id "<actual_id>"`
- If no heartbeat cron exists: this is an orphaned run — log and skip adaptive interval logic

### Recovery check

Use `TodoRead` to list all existing tasks. If any `in_progress` tasks exist from a previous iteration (orphaned agents):
- `chat:*` in_progress -- mark `completed` (chat agent from previous session is gone, next new message will create fresh task)
- `worker:*` in_progress -- leave as-is (worker tracks state via local task files independently)
- `planner` in_progress -- mark `completed` (planner will be re-dispatched on next due interval)
- `triage:*` in_progress -- mark `completed` (will be re-created by planner)
- `notify:*` in_progress -- mark `completed` (delivery attempt was interrupted, log as potentially missed notification)
- other agent tasks (e.g. `morning`, `eod`) in_progress -- mark `completed` (dispatched agent from previous session is gone)

---

## Step 3: Chat Check

1. **Filter new messages:** Messages in `CHAT_MESSAGES` block with prefix `user:` (owner messages), `ts` > `last_chat_ts`. Skip messages with prefix `bot:` (not from owner).

2. **Check for active chat agent:** Use `TodoRead` -- look for any `chat:*` task with status `in_progress`.

3. **Classify and handle new message:**

   Read the message and decide: **trivial** (answer inline) or **non-trivial** (dispatch subagent).

   **THREAD_TS derivation:** If message has field `thread_ts` (is thread reply) -- `THREAD_TS = thread_ts value`. If no `thread_ts` (top-level message) -- `THREAD_TS = ""`. **Never pass `ts` as THREAD_TS.**

   **Trivial** — heartbeat handles inline, no agent dispatch:
   - Greetings, confirmations, thanks ("hi", "ok", "thanks", "got it", "great")
   - Sleep mode ("going to sleep", "good night", "pause", "sleep"):
     ```bash
     SLEEP_UNTIL=$(date -d "tomorrow 06:00" -Iseconds)  # or parsed time
     kvido heartbeat-state set sleep_until "$SLEEP_UNTIL"
     ```
   - Turbo mode ("turbo"):
     ```bash
     TURBO_UNTIL=$(date -d "+30 min" -Iseconds)  # or parsed duration
     kvido heartbeat-state set turbo_until "$TURBO_UNTIL"
     ```
   - Cancel ("cancel <slug>"):
     ```bash
     kvido task note <slug> "Cancelled via chat"
     kvido task move <slug> cancelled
     ```
   - Simple status questions answerable from loaded state/current.md and `kvido log list --today`

   For trivial: compose response, create `notify:chat:<ts>` TODO (in_progress), deliver via `kvido slack send|reply chat --var message="<response>"`, mark notify TODO completed. Log: `kvido log add chat inline --message "<summary>"`

   **Non-trivial** — requires MCP lookup, research, task creation, or pipeline response:
   - If no active `chat:*` task:
     - `TodoWrite` task `chat:<ts>` with status `in_progress`
     - Load last 10 messages; if thread reply, load whole thread
     - Dispatch `chat-agent` (`run_in_background: true`) with template vars: CHAT_HISTORY, NEW_MESSAGE, THREAD_TS, CURRENT_STATE, MEMORY
   - If active `chat:*` task exists:
     - Send ack: `kvido slack send chat --var message="One moment..."`
     - `TodoWrite` task `chat:<ts>` with status `pending`

   Update: `kvido heartbeat-state set last_chat_ts "<ts>"` + `kvido heartbeat-state set last_interaction_ts "$(date -Iseconds)"`

4. **Agent completion:** When a dispatched chat-agent completes (background task finishes), in the next heartbeat iteration:
   - `TodoRead` -- find `chat:*` tasks with status `in_progress`
   - Since the agent has already finished, proceed to **Step 3c** for output processing and inline delivery
   - After delivery is processed, mark chat task as `completed`
   - Check for `pending` chat tasks -- if any exist, dispatch next one (FIFO) -- but only AFTER delivery is processed for the completed task

---

## Step 3b: Triage Task Creation & Reactions Polling

### Creating triage tasks

Triage TODOs are created in Step 3c when heartbeat delivers a `triage-item` notification through `kvido slack`. The returned `ts` is written into `triage:<slug>` TODO description. No CHAT_MESSAGES scanning needed for triage creation.

### Polling reactions

Use `TodoRead` to find all `triage:*` tasks (not completed). Build JSON input and delegate to bash:

```bash
# Build input: [{"slug":"fix-auth-bug","ts":"1773..."},...]
echo "$TRIAGE_JSON" | kvido triage-poll
```

Output: `[{"slug":"fix-auth-bug","result":"approved|rejected|pending"},...]`

For each result:
- `approved` → `kvido log add triage approved --message "<slug> approved -> todo"`, mark `triage:<slug>` TODO completed
- `rejected` → `kvido log add triage rejected --message "<slug> rejected -> cancelled"`, mark TODO completed
- `pending` → skip

---

## Step 3c: Agent Output Processing & Delivery

When a background agent completes (detected via TodoRead — task status is `in_progress` but agent has returned result), process its output and deliver directly from heartbeat via `kvido slack`.

### Delivery rules

Load delivery rules from installed plugins:

```bash
kvido context heartbeat
```

Heartbeat is responsible for parsing agent output into structured fields, deciding notification level, choosing template, and calling `kvido slack`. Apply the rules from the assembled context. Plugin-contributed rules extend or override defaults.

### Common pattern (all agent completions)

1. Read agent's NL output (returned by Agent tool)
2. Parse `total_tokens` + `duration_ms` from `<usage>` tag → `kvido log add <type> execute --tokens ... --duration_ms ... --message "<summary>"`
3. Create `notify:<type>:<id>` TODO (in_progress)
4. Apply delivery rules → deliver via `kvido slack` → mark TODO completed
5. Mark agent task as completed

### Per-agent specifics

| Agent | Parse fields | Template | Level | Extra |
|-------|-------------|----------|-------|-------|
| chat-agent | `Reply`, `Thread`, `Type` | `chat` | always `immediate` | After delivery, check for `pending` chat tasks → dispatch next (FIFO) |
| planner | Prefixed lines: `Event:`, `Event (batch):`, `Triage:`, `Reminder:`, `Dispatch:` | per-line mapping from slack templates | per delivery rules | `Triage:` → create `triage:<slug>` TODO with `ts`. `Dispatch:` → dispatch named agent. `No notifications.` → skip. |
| worker | `Result`, `Task`, `Type`, `Source` | `worker-report` | `high` for error, else `normal` | — |
| other | template variables per agent | agent name as template, fallback `event` | per delivery rules | — |

### Batch flush

Flush `notify:*` TODOs with `pending` status when: planner/full iteration runs, or focus mode switches off. Re-deliver stored template+vars via `kvido slack`. On failure, leave `pending` for next flush.

---

## Step 4: Planner Dispatch

1. Use `TodoRead` -- check if `planner` task exists with status `in_progress`. If yes -- skip (planner still running).
2. If `PLANNER_DUE == true` (from `heartbeat.sh`) and no active planner:
   - `TodoWrite` task `planner` with status `in_progress` and description `"Planner dispatch at <timestamp>"`
   - Dispatch `planner` agent (`run_in_background: true`)
   - Pass context: `CURRENT_STATE` (state/current.md), `MEMORY` (memory/memory.md)
   - Log: `kvido log add planner dispatch --message "iteration <N>"`
3. If planner agent completed since last check -- update `planner` task to `completed`.

---

## Step 5: Worker Dispatch

1. `TodoRead` — if any `worker:*` in_progress → skip (max 1 concurrent).
2. `NEXT_TASK=$(kvido task list todo --sort priority | head -1)` — empty → skip.
3. `kvido task move "$NEXT_TASK" in-progress` + `kvido task read "$NEXT_TASK"` → get SIZE, PRIORITY, SOURCE_REF, INSTRUCTION, PHASE, WORKTREE.
   - Pipeline task without phase → set default: `kvido task update "$NEXT_TASK" phase brainstorm|implement`
4. `TodoWrite` task `worker:<NEXT_TASK>` (in_progress).
5. Model from config: `models.<SIZE>` (or `urgent_model` if PRIORITY==urgent).
6. Dispatch `worker` agent (`run_in_background: true`, model per size). If `WORKTREE=true` → add `isolation: "worktree"`.
7. Log: `kvido log add worker dispatch --message "<NEXT_TASK>" --task_id "<NEXT_TASK>"`.
8. If SOURCE_REF not empty → send ack via `kvido slack reply "<SOURCE_REF>" chat --var message="Task accepted..."`.

Max 1 worker per iteration.

---

## Step 6: Adaptive Interval

`heartbeat.sh` returns `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `TURBO_ACTIVE/UNTIL`, `SLEEP_ACTIVE/UNTIL`.

| Mode | Trigger | TARGET_PRESET | Behavior |
|------|---------|---------------|----------|
| Sleep | "going to sleep" in DM | `sleep` | `CronDelete` old → `CronCreate` one-shot at `SLEEP_UNTIL` (default 06:00). No planner/worker dispatch. After wake: normal flow. |
| Turbo | "turbo" in DM | `1m` | 30min burst. After expiry: `heartbeat.sh` auto-clears, returns normal. |
| Normal | — | decay-based | Based on interaction age (config `skills.heartbeat.decay.*`). |

If `TARGET_PRESET != ACTIVE_PRESET`:
1. `CronDelete` old job → `CronCreate` new with matching expression
2. `kvido heartbeat-state set cron_job_id` + `active_preset`
3. `kvido log add heartbeat adaptive --message "interval {ACTIVE} -> {TARGET}"`

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Passing message `ts` as `THREAD_TS` | `THREAD_TS` = `thread_ts` field (parent), never `ts` (message itself) |
| Dispatching chat-agent for trivial messages ("ok", "thanks") | Classify first — greetings, acks, sleep/turbo/cancel are always inline |
| Sending Slack directly from agents | Only heartbeat calls `kvido slack`. Agents return NL output. |
| Dispatching worker when one is already `in_progress` | Check TodoRead for `worker:*` in_progress first |
| Forgetting to mark orphaned tasks on recovery | All `in_progress` tasks from previous session must be cleaned up in Step 2 |
| Outputting verbose text when nothing happened | Silent exit is default. No output = nothing to report. |
| Not updating `last_chat_ts` after processing | Always `kvido heartbeat-state set last_chat_ts` after chat handling |

## Critical Rules

- **NEVER output if nothing to report.** Silent exit is default.
- **Extremely brief.** One line per event.
- **State-first.** Read from files, write to files.
- **Time from system.** `date -Iseconds`.
- **Max 1 worker per iteration.** Planner + 1 worker + 1 chat-agent is maximum.
- **TodoWrite is the single source of truth** for dispatch tracking. No file-based locks.
- **Dependency rule:** Do not dispatch chat-agent if one is already `in_progress`. Do not dispatch worker if one is already `in_progress`. Planner can run alongside chat-agent but not alongside another planner.
- **No business agent calls `kvido slack` directly.** Heartbeat owns Slack delivery.
- **Notify TODOs are ephemeral.** Completed notify TODOs can be cleaned up after logging.
