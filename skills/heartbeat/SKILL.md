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

## Orchestration Model

All dispatch tracking uses **TodoWrite/TodoRead** (Claude Code native task primitives). Each dispatched agent or pending action = one todo item. TodoWrite replaces file-based locks (`chat-lock.sh`, `pending-chat-messages.json`, `triage-messages.json`).

### Task ID conventions

| Type | ID format | Example |
|------|-----------|---------|
| Chat dispatch | `chat:<slack_ts>` | `chat:1773933088.437799` |
| Worker dispatch | `worker:<issue_id>` | `worker:20` |
| Planner dispatch | `planner` | `planner` |
| Triage poll | `triage:<issue_id>` | `triage:7` |
| Notify chat | `notify:chat:<ts>` | `notify:chat:1773933088.437` |
| Notify planner | `notify:planner:<iteration>` | `notify:planner:42` |
| Notify worker | `notify:worker:<issue_id>` | `notify:worker:20` |
| Notify triage | `notify:triage:<issue_id>` | `notify:triage:15` |
| Notify ack | `notify:ack:<issue_id>` | `notify:ack:20` |
| Notify queue | `notify:queue:<ts>` | `notify:queue:1773933088.437` |
| Agent dispatch | `<agent-name>` | `morning` |
| Notify agent | `notify:<agent-name>` | `notify:morning` |

### Status mapping

| TodoWrite status | Meaning |
|------------------|---------|
| `in_progress` | Agent dispatched, running |
| `pending` | Queued, waiting for processing |
| `completed` | Done successfully |

### Recovery (session start)

At iteration 0 (or after session restart), TodoRead all items. Any `in_progress` tasks from a previous session are orphaned -- the agent that was running them no longer exists. Mark them `completed` (or re-queue if appropriate). `notify:*` tasks are heartbeat-owned delivery tasks, not a separate agent lifecycle.

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
- `worker:*` in_progress -- leave as-is (worker tracks state via GitLab Issues independently)
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
   - Cancel ("zruš #NNN", "cancel #NNN"):
     ```bash
     skills/worker/work-cancel.sh --issue <NNN> --reason "Cancelled via chat"
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
# Build input: [{"issue":"7","ts":"1773..."},...]
echo "$TRIAGE_JSON" | skills/heartbeat/triage-poll.sh
```

Output: `[{"issue":"7","result":"approved|rejected|pending"},...]`

For each result:
- `approved` → log `- **HH:MM** [triage] #<N> approved -> status:todo`, mark `triage:<issue_id>` TODO completed
- `rejected` → log `- **HH:MM** [triage] #<N> rejected -> cancelled`, mark TODO completed
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
   - Read planner's NL output
   - Parse `total_tokens` and `duration_ms` from Agent tool `<usage>` tag
   - Log: `skills/heartbeat/heartbeat-state.sh log-activity planner execute --tokens <total_tokens> --duration_ms <duration_ms> --detail "<N notifications|No notifications>"`
   - Parse output — extract individual items:
     - Lines starting with `Event:` or `Event (batch):` → type event
     - Lines starting with `Triage:` → type triage-item
     - Lines starting with `Reminder:` → type reminder
     - Lines starting with `Dispatch:` → agent dispatch request (see below)
   - If output is `No notifications.` → mark planner completed, skip delivery
   - For each notification item (Event/Triage/Reminder):
     - Create `notify:<type>:<id>` TODO (in_progress)
     - Parse to structured fields and choose level:
       - Events: template `event`, vars `emoji`, `title`, `description`, `source`, `reference`, `timestamp`; `URGENCY=high` if line starts with `Event:`, otherwise `normal`
       - Triage: template `triage-item`, vars `issue`, `title`, `description`, `issue_url`, `priority`, `size`, `assignee`; `URGENCY=normal`
       - Reminders: template `event`, vars `emoji="⏰"`, `title="Připomínka"`, `description`, `source="planner"`, `reference`, `timestamp`; `URGENCY=normal`
     - After each decision:
       - `immediate` → send via `slack.sh send <template> --var ...`, mark notify TODO completed
       - `silent` → log summary, mark notify TODO completed
       - `batch` → set notify TODO status to `pending` and store serialized template + vars in description
       - triage-item + `immediate` → create `triage:<issue_id>` with `ts=<returned ts>` in description
   - For each `Dispatch:` line — parse agent name and parameters:
     - Format: `Dispatch: <agent-name> KEY1=value1 KEY2="value2" ...`
     - Create `<agent-name>` TODO (in_progress) with description containing parameters
     - Dispatch named agent (background) with parsed parameters as template variables
     - Example: `Dispatch: morning`
       → dispatch `morning` agent with no additional parameters
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

1. When a planner-dispatched agent completes (TODO task like `morning` with status `in_progress`):
   - Read agent's NL output
   - Parse `total_tokens` and `duration_ms` from Agent tool `<usage>` tag
   - Log: `skills/heartbeat/heartbeat-state.sh log-activity <agent-name> execute --tokens <total_tokens> --duration_ms <duration_ms> --detail "<result summary[:60]>"`
   - Parse output for: Type (e.g. `morning` or `eod`)
   - Create `notify:<agent-name>` TODO (in_progress)
   - Determine template from agent name:
     - `morning` → `morning`
     - `eod` → `eod`
     - all others → `event`
   - Deliver inline:
     - `morning` → parse/output variables expected by `morning` template and call `slack.sh send morning`
     - `eod` → parse/output variables expected by `eod` template and call `slack.sh send eod`
     - others → parse/output variables expected by `event` template and call `slack.sh send event`
   - Mark agent task as completed

### Notify result handling

After each delivery decision:
1. Parse level, template, summary, optional returned `ts`
2. Log: `- **HH:MM** [notify] <SUMMARY>` (or warning on error)
3. `batch` → keep notify TODO as `pending` and persist compact template + vars payload
4. `immediate` or `silent` → mark notify TODO completed
5. `immediate` + triage-item → create `triage:<issue_id>` TODO with `ts=<returned ts>`
6. On command failure → log warning and mark notify TODO completed

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
2. `NEXT_TASK` from heartbeat.sh output -- issue number (or empty -- skip)
3. `skills/worker/work-start.sh --issue <NEXT_TASK>` -- if exit 1 -- skip
4. Load task attributes:
   ```bash
   skills/worker/work-task-info.sh <NEXT_TASK>
   ```
   Output: `TASK_ID=..., SIZE=..., PRIORITY=..., SOURCE_REF=..., INSTRUCTION=..., PHASE=..., WORKTREE=...`
5. `TodoWrite` task `worker:<NEXT_TASK>` with status `in_progress` and description `"Worker #<id>: <instruction[:60]>"`
6. Load model from `.claude/kvido.local.md`: `models.<SIZE>` (or `urgent_model` if PRIORITY==urgent)
7. Dispatch `worker` agent (`run_in_background: true`, model per size):
   ```
   TASK_ISSUE=<NEXT_TASK>, TASK_ID, INSTRUCTION, SIZE, SOURCE_REF, PHASE, CURRENT_STATE, MEMORY
   ```
   - If `WORKTREE=true`: add `isolation: "worktree"` to Agent tool call
   - If `WORKTREE=false`: dispatch without isolation
8. Log activity: `skills/heartbeat/heartbeat-state.sh log-activity worker dispatch --detail "#<id>: <instruction[:60]>" --task_id <NEXT_TASK>`
9. Log: `- **HH:MM** [worker] Dispatched #<id> (<size>/<priority>): <instruction[:60]>`
10. If SOURCE_REF not empty, send acknowledgement directly:
   - Create `notify:ack:<NEXT_TASK>` TODO (in_progress)
   - Decide `LEVEL=immediate`, template `chat`
   - Call:
     ```bash
     skills/slack/slack.sh reply "<SOURCE_REF>" chat \
       --var message="Přijat úkol #<NEXT_TASK>: <instruction[:60]>"
     ```
   - Mark TODO completed on success, otherwise log warning and mark completed

Max 1 worker per iteration.

---

## Step 5: Log

State update (iteration_count, last_quick) is done in heartbeat.sh (Step 1).

If nothing to report -- no output.

---

## Step 6: Adaptive Interval

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
- **batched_events deprecated.** Batch notifications use notify TODOs with pending status, not heartbeat-state.json array.
