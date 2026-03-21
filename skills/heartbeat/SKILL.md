---
name: heartbeat
description: Use when the cron heartbeat fires to orchestrate chat, worker, planner, and triage dispatch.
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

### Common pattern (all agent completions)

1. Read agent's NL output (returned by Agent tool)
2. Parse `total_tokens` + `duration_ms` from `<usage>` tag → `heartbeat-state.sh log-activity <type> execute --tokens ... --duration_ms ...`
3. Create `notify:<type>:<id>` TODO (in_progress)
4. Apply delivery rules → deliver via `slack.sh` → mark TODO completed
5. Mark agent task as completed

### Per-agent specifics

| Agent | Parse fields | Template | Level | Extra |
|-------|-------------|----------|-------|-------|
| chat-agent | `Odpověď`, `Thread`, `Type` | `chat` | always `immediate` | After delivery, check for `pending` chat tasks → dispatch next (FIFO) |
| planner | Prefixed lines: `Event:`, `Event (batch):`, `Triage:`, `Reminder:`, `Dispatch:` | per-line mapping from `skills/slack/templates/` | per delivery rules | `Triage:` → create `triage:<slug>` TODO with `ts`. `Dispatch:` → dispatch named agent. `No notifications.` → skip. |
| worker | `Result`, `Task`, `Type`, `Source` | `worker-report` | `high` for error, else `normal` | — |
| other (morning, eod) | template variables per agent | agent name as template, fallback `event` | per delivery rules | — |

### Batch flush

Flush `notify:*` TODOs with `pending` status when: planner/full iteration runs, or focus mode switches off. Re-deliver stored template+vars via `slack.sh`. On failure, leave `pending` for next flush.

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

1. `TodoRead` — if any `worker:*` in_progress → skip (max 1 concurrent).
2. `NEXT_TASK=$(skills/worker/task.sh list todo --sort priority | head -1)` — empty → skip.
3. `task.sh move "$NEXT_TASK" in-progress` + `task.sh read "$NEXT_TASK"` → get SIZE, PRIORITY, SOURCE_REF, INSTRUCTION, PHASE, WORKTREE.
   - Pipeline task without phase → set default: `task.sh update "$NEXT_TASK" phase brainstorm|implement`
4. `TodoWrite` task `worker:<NEXT_TASK>` (in_progress).
5. Model from config: `models.<SIZE>` (or `urgent_model` if PRIORITY==urgent).
6. Dispatch `worker` agent (`run_in_background: true`, model per size). If `WORKTREE=true` → add `isolation: "worktree"`.
7. Log activity via `heartbeat-state.sh log-activity worker dispatch`.
8. If SOURCE_REF not empty → send ack via `slack.sh reply "<SOURCE_REF>" chat --var message="Přijat úkol..."`.

Max 1 worker per iteration.

---

## Step 5: Adaptive Interval

`heartbeat.sh` returns `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `TURBO_ACTIVE/UNTIL`, `SLEEP_ACTIVE/UNTIL`.

| Mode | Trigger | TARGET_PRESET | Behavior |
|------|---------|---------------|----------|
| Sleep | "jdu spát" in DM | `sleep` | `CronDelete` old → `CronCreate` one-shot at `SLEEP_UNTIL` (default 06:00). No planner/worker dispatch. After wake: normal flow. |
| Turbo | "turbo" in DM | `1m` | 30min burst. After expiry: `heartbeat.sh` auto-clears, returns normal. |
| Normal | — | decay-based | Based on interaction age (config `skills.heartbeat.decay.*`). |

If `TARGET_PRESET != ACTIVE_PRESET`:
1. `CronDelete` old job → `CronCreate` new with matching expression
2. `heartbeat-state.sh set cron_job_id` + `active_preset`
3. Log: `- **HH:MM** [heartbeat] Adaptive: {ACTIVE} -> {TARGET}`

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Passing message `ts` as `THREAD_TS` | `THREAD_TS` = `thread_ts` field (parent), never `ts` (message itself) |
| Dispatching chat-agent for trivial messages ("ok", "díky") | Classify first — greetings, acks, sleep/turbo/cancel are always inline |
| Sending Slack directly from agents | Only heartbeat calls `slack.sh`. Agents return NL output. |
| Dispatching worker when one is already `in_progress` | Check TodoRead for `worker:*` in_progress first |
| Forgetting to mark orphaned tasks on recovery | All `in_progress` tasks from previous session must be cleaned up in Step 1 |
| Outputting verbose text when nothing happened | Silent exit is default. No output = nothing to report. |
| Not updating `last_chat_ts` after processing | Always `heartbeat-state.sh set last_chat_ts` after chat handling |

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
