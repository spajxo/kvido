---
name: heartbeat-dispatch
description: Heartbeat Step 5 — dispatch agents per planner DISPATCH lines and pending chat tasks. Load when DISPATCH lines exist or chat:* tasks are pending.
---

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
- Dispatch chat (`run_in_background: true`)
- Log: `kvido log add heartbeat dispatch --message "chat:<ts>"`
