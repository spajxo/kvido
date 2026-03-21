---
name: heartbeat
description: Orchestrator -- TodoWrite-based dispatch tracking, chat/worker/planner/triage orchestration, adaptive interval.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronCreate, CronList, CronDelete, TodoWrite, TodoRead
---

# Heartbeat

Runs automatically via `/loop`. Be extremely brief -- no output if nothing to report.

## Tone Guidelines

Tone and style per `memory/persona.md` (section Heartbeat). If persona missing, be brief and factual.

---

## Step 1: Init

Run:

```bash
skills/heartbeat/heartbeat.sh
```

Output: `TIMESTAMP`, `ITERATION`, `NIGHT`, `ZONE`, `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `INTERACTION_AGO_MIN`, `PLANNER_DUE`, `NEXT_TASK`, `SLEEP_ACTIVE`, `SLEEP_UNTIL`, `CHAT_MESSAGES_START...CHAT_MESSAGES_END`.

Messages in `CHAT_MESSAGES` block are in `--heartbeat` format: one line per message, empty line between top-level messages: `ts=... user=... text="..." [reactions=emoji1,emoji2] [reply_count=N] [latest_reply=...]`. Thread replies are under their top-level message with prefix `  ┗` (max 5 replies). Empty block = no messages.

The script automatically: increments iteration_count, sets last_quick, reads Slack DM, checks worker queue.

Read `state/today.md` and `state/current.md` for context.

### Recovery check

Use `TodoRead` to list all existing tasks. If any `in_progress` tasks exist from a previous iteration (orphaned agents):
- `chat:*` in_progress -- mark `completed` (chat agent from previous session is gone, next new message will create fresh task)
- `worker:*` in_progress -- leave as-is (worker tracks state via local task files independently)
- `planner` in_progress -- mark `completed` (planner will be re-dispatched on next due interval)
- `triage:*` in_progress -- mark `completed` (will be re-created by planner)
- `notify:*` in_progress -- mark `completed` (delivery attempt was interrupted, log as potentially missed notification)
- other agent tasks (e.g. `morning`, `eod`) in_progress -- mark `completed` (dispatched agent from previous session is gone)

---

## Step 2: Chat Check

1. **Filter new messages:** Messages in `CHAT_MESSAGES` block, field `user` == `SLACK_USER_ID`, `ts` > `last_chat_ts`, ignore bot messages.

2. **Check for active chat agent:** Use `TodoRead` -- look for any `chat:*` task with status `in_progress`.

3. **Classify and handle new message:**

   Read the message and decide: **triviální** (answer inline) or **netriviální** (dispatch subagent).

   **THREAD_TS derivation:** If message has field `thread_ts` (is thread reply) -- `THREAD_TS = thread_ts value`. If no `thread_ts` (top-level message) -- `THREAD_TS = ""`. **Never pass `ts` as THREAD_TS.**

   **Triviální** — heartbeat handles inline, no agent dispatch:
   - Pozdravy, potvrzení, díky ("ahoj", "ok", "díky", "jasné", "super")
   - Sleep mode ("jdu spát", "dobrou noc", "pauza", "sleep"):
     ```bash
     SLEEP_UNTIL=$(date -d "tomorrow 06:00" -Iseconds)  # or parsed time
     skills/heartbeat/heartbeat-state.sh set sleep_until "$SLEEP_UNTIL"
     ```
   - Turbo mode ("turbo"):
     ```bash
     TURBO_UNTIL=$(date -d "+30 min" -Iseconds)  # or parsed duration
     skills/heartbeat/heartbeat-state.sh set turbo_until "$TURBO_UNTIL"
     ```
   - Cancel ("zruš <slug>", "cancel <slug>"):
     ```bash
     skills/worker/task.sh note <slug> "Cancelled via chat"
     skills/worker/task.sh move <slug> cancelled
     ```
   - Simple status questions answerable from loaded state/current.md and state/today.md

   For triviální: compose response, create `notify:chat:<ts>` TODO (in_progress), deliver via `slack.sh send|reply chat --var message="<response>"`, mark notify TODO completed. Log: `- **HH:MM** [chat] <summary>`

   **Netriviální** — requires MCP lookup, research, task creation, or pipeline response:
   - If no active `chat:*` task:
     - `TodoWrite` task `chat:<ts>` with status `in_progress`
     - Load last 10 messages; if thread reply, load whole thread
     - Dispatch `chat-agent` (`run_in_background: true`) with template vars: CHAT_HISTORY, NEW_MESSAGE, THREAD_TS, CURRENT_STATE, MEMORY
   - If active `chat:*` task exists:
     - Send ack: `skills/slack/slack.sh send chat --var message="Moment..."`
     - `TodoWrite` task `chat:<ts>` with status `pending`

   Update: `heartbeat-state.sh set last_chat_ts "<ts>"` + `heartbeat-state.sh set last_interaction_ts "$(date -Iseconds)"`

4. **Agent completion:** When a dispatched chat-agent completes (background task finishes), in the next heartbeat iteration:
   - `TodoRead` -- find `chat:*` tasks with status `in_progress`
   - Since the agent has already finished, proceed to **Step 2c** for output processing and inline delivery
   - After delivery is processed, mark chat task as `completed`
   - Check for `pending` chat tasks -- if any exist, dispatch next one (FIFO) -- but only AFTER delivery is processed for the completed task

---

## Step 2b: Triage Task Creation & Reactions Polling

### Creating triage tasks

Triage TODOs are created in Step 2c when heartbeat delivers a `triage-item` notification through `slack.sh`. The returned `ts` is written into `triage:<issue_id>` TODO description. No CHAT_MESSAGES scanning needed for triage creation.

### Polling reactions

Use `TodoRead` to find all `triage:*` tasks (not completed). Build JSON input and delegate to bash:

```bash
# Build input: [{"slug":"fix-auth-bug","ts":"1773..."},...]
echo "$TRIAGE_JSON" | skills/heartbeat/triage-poll.sh
```

Output: `[{"slug":"fix-auth-bug","result":"approved|rejected|pending"},...]`

For each result:
- `approved` → log `- **HH:MM** [triage] <slug> approved -> todo`, mark `triage:<slug>` TODO completed
- `rejected` → log `- **HH:MM** [triage] <slug> rejected -> cancelled`, mark TODO completed
- `pending` → skip

---

## Step 2c: Agent Output Processing & Delivery

When a background agent completes (detected via TodoRead — task status is `in_progress` but agent has returned result), process its output and deliver directly from heartbeat via `skills/slack/slack.sh`.

### Delivery rules

Heartbeat is responsible for parsing agent output into structured fields, deciding `immediate|batch|silent`, choosing template, and calling `slack.sh`.

Rules:
- `chat-reply` is always `immediate`
- `event`, `reminder`, `worker-report`, `triage-item`, `morning`, `eod`, `maintenance` use template mapping defined in `skills/slack/SKILL.md`
- `normal + focus_mode=on` → `batch`
- `low` → `silent`
- everything else → `immediate`
- `batch` -- keep notify TODO as `pending` and store serialized delivery metadata in description
- `silent` -- log summary and mark notify TODO completed
- `immediate` -- use returned `ts` for follow-up flows (triage polling, thread replies)
- shell failure -- log warning to `state/today.md`, mark notify TODO completed

### Chat-agent completion

1. When chat-agent completes (background task returns result):
   - Read chat-agent's NL output (returned natively by Agent tool)
   - Parse `total_tokens` and `duration_ms` from Agent tool `<usage>` tag
   - Log: `skills/heartbeat/heartbeat-state.sh log-activity chat execute --tokens <total_tokens> --duration_ms <duration_ms> --detail "<message summary[:60]>"`
   - Parse output for: `Odpověď`, `Thread`, `Type`
   - Create `notify:chat:<ts>` TODO (in_progress)
   - Decide `LEVEL=immediate`, template `chat`
   - Deliver inline:
     ```bash
     skills/slack/slack.sh <send|reply> <thread handling> chat \
       --var message="<parsed Odpověď>"
     ```
   - Mark `chat:*` task as completed
   - Check for `pending` chat tasks — if any, dispatch next chat-agent (FIFO)

### Planner completion

1. When planner agent completes:
   - Read planner's NL output, log activity via `heartbeat-state.sh log-activity planner execute`
   - Parse output line-by-line — planner uses prefixed lines: `Event:`, `Event (batch):`, `Triage:`, `Reminder:`, `Dispatch:`
   - If `No notifications.` → mark planner completed, skip delivery
   - For each notification item: choose matching template from `skills/slack/templates/`, apply delivery rules, deliver via `slack.sh`
   - For triage items delivered as `immediate`: create `triage:<slug>` TODO with returned `ts` for reaction polling
   - For each `Dispatch: <agent-name>` line: dispatch named agent in background
   - Mark `planner` task as completed

### Worker completion

1. When worker agent completes:
   - Read worker's NL output
   - Parse `total_tokens` and `duration_ms` from Agent tool `<usage>` tag
   - Log: `skills/heartbeat/heartbeat-state.sh log-activity worker execute --tokens <total_tokens> --duration_ms <duration_ms> --task_id <issue_id> --detail "#<id>: <result summary[:60]>"`
   - Parse output for: `Result`, `Task`, `Type`, `Source`
   - Create `notify:worker:<issue_id>` TODO (in_progress)
   - Choose template `worker-report`, level `high` for `worker-error` otherwise `normal`
   - Deliver inline:
     ```bash
     skills/slack/slack.sh <send|reply> <thread handling> worker-report \
       --var title="<first line or task summary>" \
       --var results="<parsed Result>" \
       --var task_id="<parsed Task>" \
       --var duration="<duration formatted from duration_ms>"
     ```
   - Mark `worker:*` task as completed

### Dispatched agent completion (e.g. morning, eod)

1. When a planner-dispatched agent completes:
   - Read agent's NL output, log activity via `heartbeat-state.sh log-activity`
   - Use agent name as template name (e.g. `morning` → `slack.sh send morning`), fall back to `event` for unknown agents
   - Parse output for template variables, deliver via `slack.sh`
   - Mark agent task as completed

### Batch flush

Check for any `notify:*` TODOs with status `pending` (serialized batch payload from current or previous iterations):
1. Flush only when:
   - planner/full iteration is running, or
   - focus mode switched from `on` to `off`
2. For each pending item, read stored template + vars payload
3. Re-run direct `slack.sh send <template> --var ...` with the stored vars
4. Mark each flushed notify TODO as completed after successful send
5. On failure, log warning and leave TODO `pending` for next flush

---

## Step 3: Planner Dispatch

1. Use `TodoRead` -- check if `planner` task exists with status `in_progress`. If yes -- skip (planner still running).
2. If `PLANNER_DUE == true` (from `heartbeat.sh`) and no active planner:
   - `TodoWrite` task `planner` with status `in_progress` and description `"Planner dispatch at <timestamp>"`
   - Dispatch `planner` agent (`run_in_background: true`)
   - Pass context: `CURRENT_STATE` (state/current.md), `MEMORY` (memory/memory.md)
   - Log activity: `skills/heartbeat/heartbeat-state.sh log-activity planner dispatch --detail "iteration <N>"`
   - Log: `- **HH:MM** [planner] Dispatched`
3. If planner agent completed since last check -- update `planner` task to `completed`.

---

## Step 4: Worker Dispatch

1. Use `TodoRead` -- check if any `worker:*` task exists with status `in_progress`. If yes -- skip (max 1 concurrent worker).
2. Find next task:
   ```bash
   NEXT_TASK=$(skills/worker/task.sh list todo --sort priority | head -1)
   ```
   Empty → skip. Also check WIP limit: `skills/worker/task.sh count in-progress` >= max_concurrent → skip.
3. Move to in-progress and load attributes:
   ```bash
   skills/worker/task.sh move "$NEXT_TASK" in-progress
   skills/worker/task.sh read "$NEXT_TASK"
   ```
   Output: `SLUG=..., SIZE=..., PRIORITY=..., SOURCE_REF=..., INSTRUCTION=..., PHASE=..., WORKTREE=...`
   If pipeline task without phase, set default: `skills/worker/task.sh update "$NEXT_TASK" phase brainstorm|implement`
4. `TodoWrite` task `worker:<NEXT_TASK>` with status `in_progress` and description `"Worker <slug>: <instruction[:60]>"`
5. Load model from `.claude/kvido.local.md`: `models.<SIZE>` (or `urgent_model` if PRIORITY==urgent)
6. Dispatch `worker` agent (`run_in_background: true`, model per size):
   ```
   TASK_SLUG=<NEXT_TASK>, INSTRUCTION, SIZE, SOURCE_REF, PHASE, CURRENT_STATE, MEMORY
   ```
   - If `WORKTREE=true`: add `isolation: "worktree"` to Agent tool call
   - If `WORKTREE=false`: dispatch without isolation
7. Log activity: `skills/heartbeat/heartbeat-state.sh log-activity worker dispatch --detail "<slug>: <instruction[:60]>" --task_id <NEXT_TASK>`
8. Log: `- **HH:MM** [worker] Dispatched <slug> (<size>/<priority>): <instruction[:60]>`
9. If SOURCE_REF not empty, send acknowledgement directly:
   - Create `notify:ack:<NEXT_TASK>` TODO (in_progress)
   - Decide `LEVEL=immediate`, template `chat`
   - Call:
     ```bash
     skills/slack/slack.sh reply "<SOURCE_REF>" chat \
       --var message="Přijat úkol <NEXT_TASK>: <instruction[:60]>"
     ```
   - Mark TODO completed on success, otherwise log warning and mark completed

Max 1 worker per iteration.

---

## Step 5: Adaptive Interval

`heartbeat.sh` returns `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `TURBO_ACTIVE`, `TURBO_UNTIL`, `SLEEP_ACTIVE` and `SLEEP_UNTIL`.

### Sleep mode

If `SLEEP_ACTIVE == true`, `heartbeat.sh` set `TARGET_PRESET="sleep"` and `ZONE="sleep"`.
Sleep is activated by keywords in Slack DM (handled inline by heartbeat in Step 2). Default until 06:00 tomorrow, custom time supported.

When activating sleep mode:
1. Log: `- **HH:MM** [heartbeat] Sleep mode until $(date -d "$SLEEP_UNTIL" +%H:%M)`
2. `CronDelete` old job
3. Calculate one-shot cron expression for `SLEEP_UNTIL`:
   - Parse hour and minute from `SLEEP_UNTIL` timestamp
   - `CronCreate` with `recurring: false` and matching cron expression
4. Save new job ID and preset:
   ```bash
   skills/heartbeat/heartbeat-state.sh set cron_job_id "<new_job_id>"
   skills/heartbeat/heartbeat-state.sh set active_preset "sleep"
   ```
5. No worker dispatch or planner dispatch during sleep mode.

After waking (heartbeat fired by one-shot cron):
- `heartbeat.sh` detects expired `sleep_until`, clears key, `SLEEP_ACTIVE=false`
- Continue normal adaptive flow

### Turbo mode

If `TURBO_ACTIVE == true`, `heartbeat.sh` set `TARGET_PRESET="1m"` and `ZONE="turbo"`.
Turbo is activated by "turbo" message in Slack DM (handled inline by heartbeat in Step 2). Default 30 min.
After `turbo_until` expires, heartbeat.sh clears key and returns normal adaptive flow.

1. If `TARGET_PRESET != ACTIVE_PRESET`:
   - Log: `- **HH:MM** [heartbeat] Adaptive: {ACTIVE_PRESET} -> {TARGET_PRESET}`
   - `CronDelete` old job
   - `CronCreate` new with matching cron expression
   - Save new job ID and preset:
     ```bash
     skills/heartbeat/heartbeat-state.sh set cron_job_id "<new_job_id>"
     skills/heartbeat/heartbeat-state.sh set active_preset "<TARGET_PRESET>"
     ```
2. If same -- no action.

---

## Critical Rules

- **NEVER output if nothing to report.** Silent exit is default.
- **Extremely brief.** One line per event.
- **State-first.** Read from files, write to files.
- **Time from system.** `date -Iseconds`.
- **Max 1 worker per iteration.** Planner + 1 worker + 1 chat-agent is maximum.
- **TodoWrite is the single source of truth** for dispatch tracking. No file-based locks.
- **Dependency rule:** Do not dispatch chat-agent if one is already `in_progress`. Do not dispatch worker if one is already `in_progress`. Planner can run alongside chat-agent but not alongside another planner.
- **No business agent calls slack.sh directly.** Heartbeat owns Slack delivery via `slack.sh`.
- **Notify TODOs are ephemeral.** Completed notify TODOs can be cleaned up after logging.
