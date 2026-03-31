---
name: heartbeat-planner
description: This skill should be activated during heartbeat Step 4 when PLANNER_DUE=true. It runs the planner as a foreground subagent and parses DISPATCH/NOTIFY output lines for downstream dispatch.
---

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
