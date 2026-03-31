---
description: Heartbeat — orchestrator, chat check, unified agent dispatch, log, adaptive interval
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, Skill, CronCreate, CronList, CronDelete, TaskCreate, TaskList, TaskUpdate, TaskGet, TaskOutput, mcp__claude_ai_Slack__slack_read_channel
---

# Heartbeat

Runs automatically via `/loop`. Be extremely brief -- no output if nothing to report.

## Tone Guidelines

Tone and style per `instructions/persona.md` (section Heartbeat). If persona missing, be brief and factual.

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

> **First-response rule:** Run the `kvido heartbeat` bash command immediately in your **first response**, in parallel with any `ToolSearch` calls. Do NOT wait for deferred tool resolution before issuing the bash call — bash tools are always available and need no prerequisite. Delaying makes the heartbeat appear frozen to the user.

Run:

```bash
kvido heartbeat
```

Output: `TIMESTAMP`, `ITERATION`, `NIGHT`, `ZONE`, `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `PLANNER_DUE`, `INTERACTION_AGO_MIN`, `OWNER_USER_ID`, `SLEEP_ACTIVE`, `SLEEP_UNTIL`, `CHAT_MESSAGES_START...CHAT_MESSAGES_END`.

Messages in `CHAT_MESSAGES` block are in `--heartbeat` format: one line per message, empty line between top-level messages: `ts=... user:|bot: text="..." [reactions=emoji1,emoji2] [reply_count=N] [latest_reply=...]`. Thread replies are under their top-level message with prefix `  ┗` (max 5 replies). Empty block = no messages.

The `user:` prefix means the message is from the workspace owner (you). The `bot:` prefix means the message is from anyone else (bot or other user). `OWNER_USER_ID` contains the resolved Slack user ID (from config or cached state). If `OWNER_USER_ID` is empty, annotation is disabled and messages retain the raw `user=<ID>` format — use `SLACK_USER_ID` from `.env` or `OWNER_USER_ID` from heartbeat output to compare manually.

The script automatically: increments iteration_count, sets last_heartbeat, reads Slack DM.

Read current state from `$KVIDO_HOME/memory/current.md` (Read tool). Review recent activity via `kvido log list --today --format human --limit 20` on planner ticks (`PLANNER_DUE=true`), or `--limit 5` on non-planner ticks.

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
   - Simple status questions answerable from `$KVIDO_HOME/memory/current.md` (Read tool) and `kvido log list --today`

   For trivial: compose response, create `notify:chat:<ts>` task via `TaskCreate` (mark in_progress via `TaskUpdate`), deliver via `kvido slack reply dm <ts> chat --var message="<response>"` (use the message `ts` as the thread root — this threads the reply under the original message), mark task completed via `TaskUpdate`. Log: `kvido log add chat inline --message "<summary>"`

   **Non-trivial** — requires MCP lookup, research, or task creation:
   - If no active `chat:*` task:
     - `TaskCreate` subject `chat:<ts>` (stays `pending` — dispatched in Step 5)
   - If active `chat:*` task exists:
     - Send ack: `kvido slack reply dm <ts> chat --var message="One moment..."` (thread under the new message)
     - `TaskCreate` subject `chat:<ts>` with `addBlockedBy` pointing to the active chat task (stays `pending`)

   **Task creation from user DM:** When the chat agent (or heartbeat inline) creates a task from a user's Slack DM request, always use `--source slack`. If the request references a GitHub issue or PR, pass it via `--source-ref "github#NN"` (not `--source`). This ensures user-initiated tasks go directly to `todo/` (bypassing triage).

   ```bash
   # Correct
   kvido task create --title "..." --instruction "..." --source slack --source-ref "github#93"
   # Wrong — would route to triage/
   kvido task create --title "..." --instruction "..." --source "github#93"
   ```

   Update: `kvido state set heartbeat.last_chat_ts "<ts>"` + `kvido state set heartbeat.last_interaction_ts "$(date -Iseconds)"`

4. **Agent completion:** When a dispatched chat agent completes (background task finishes), in the next heartbeat iteration:
   - `TaskList` -- find `chat:*` tasks with status `in_progress`
   - Since the agent has already finished, proceed to **Step 6** for output processing and delivery
   - After delivery is processed, mark chat task as `completed` via `TaskUpdate`
   - Check for `pending` chat tasks -- if any exist, dispatch next one (FIFO) -- but only AFTER delivery is processed for the completed task

---

## Step 4: Run Planner

**Throttle:** `heartbeat.sh` outputs `PLANNER_DUE=true|false` based on `planning_interval` config (default 3 — every 3rd iteration).

If `PLANNER_DUE=true`: invoke skill `kvido:heartbeat-planner` and follow its instructions.
Otherwise: skip to Step 5.

---

## Step 5: Dispatch Agents

If planner returned DISPATCH or NOTIFY lines, or pending `chat:*` tasks exist (from Step 3): invoke skill `kvido:heartbeat-dispatch` and follow its instructions.
Otherwise: skip to Step 6.

---

## Step 6: Collect Outputs & Deliver

Invoke skill `kvido:heartbeat-deliver` if ANY of these are true:
- Background agent tasks completed this iteration (`TaskList` shows `in_progress` tasks whose agents returned)
- Planner completed this iteration (planner summary needs to be delivered)
- Batched `notify:*` tasks are pending flush (planner tick triggers flush)

Otherwise: silent exit — proceed to Step 7.

---

## Step 7: Adaptive Interval

`heartbeat.sh` returns `TARGET_PRESET`, `ACTIVE_PRESET`, `CRON_JOB_ID`, `TURBO_ACTIVE/UNTIL`, `SLEEP_ACTIVE/UNTIL`.

| Mode | Trigger | TARGET_PRESET | Behavior |
|------|---------|---------------|----------|
| Sleep | "going to sleep" in DM | `sleep` | `CronDelete` old → `CronCreate` one-shot at `SLEEP_UNTIL` (default 06:00). No planner/worker dispatch. After wake: normal flow. |
| Turbo | "turbo" in DM | `1m` | 30min burst. After expiry: `heartbeat.sh` auto-clears, returns normal. |
| Normal | — | decay-based | Based on interaction age (config `heartbeat.decay.*`). |

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
| Waiting for ToolSearch before running `kvido heartbeat` | Run bash in parallel with ToolSearch on first response — no prerequisite needed |
| Passing message `ts` as `THREAD_TS` | `THREAD_TS` = `thread_ts` field (parent), never `ts` (message itself) |
| Dispatching chat for trivial messages ("ok", "thanks") | Classify first — greetings, acks, sleep/turbo/cancel are always inline |
| Dispatching agent when same-group task is pending/in_progress | Use `blockedBy` dependencies, dispatch skips blocked tasks |
| Forgetting to mark orphaned tasks on recovery | All `in_progress` tasks from previous session must be cleaned up in Step 2 |
| Outputting verbose text when nothing happened | Silent exit is default. No output = nothing to report. |
| Not updating `last_chat_ts` after processing | Always `kvido state set heartbeat.last_chat_ts` after chat handling |
| Using `--source "github#NN"` when creating tasks from user DM | Use `--source slack --source-ref "github#NN"` — source=slack routes to `todo/`, source=github#NN routes to `triage/` |
| Using event bus commands (`kvido event emit/read/ack`) | Event bus is removed — planner returns NL, heartbeat interprets directly |
| Dispatching notifier agent separately | Heartbeat owns ALL Slack delivery — no separate notifier dispatch |
| Referencing GitHub issues/PRs or GitLab MRs without a URL | Always include the full clickable URL — plain "#123" or "\!42" alone is not enough |

## Critical Rules

- **NEVER output if nothing to report.** Silent exit is default.
- **Extremely brief.** One line per event.
- **State-first.** Read from files, write to files.
- **Time from system.** `date -Iseconds`.
- **Task tools (`TaskCreate`/`TaskList`/`TaskUpdate`) are the single source of truth** for dispatch tracking. No file-based locks.
- **Concurrency via dependencies.** Same-group tasks use `blockedBy`. Max 1 concurrent per group (maintenance, worker, chat). Planner runs foreground. Other agents run in background.
- **Notify TODOs are ephemeral.** Completed notify TODOs can be cleaned up after logging.
- **Heartbeat owns ALL delivery.** No agent sends Slack messages directly. Chat delivery in Step 3/6, all other agent outputs in Step 6.
- **No event bus.** No `kvido event emit/read/ack`.
- **Planner is the sole scheduler.** Heartbeat never decides which agents to dispatch — it only parses `DISPATCH` / `NOTIFY` lines from planner output.
- **Always include clickable URLs.** When delivering Slack messages that reference GitHub issues/PRs (https://github.com/owner/repo/issues/N or /pull/N) or GitLab MRs (https://git.digital.cz/<group>/<project>/-/merge_requests/<iid>), always embed the full URL — not just the bare number.
