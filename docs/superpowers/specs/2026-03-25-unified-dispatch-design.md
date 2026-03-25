# Unified Agent Dispatch Model

**Issue:** [#105](https://github.com/spajxo/kvido/issues/105)
**Date:** 2026-03-25

## Problem

Maintenance agents (librarian, enricher, self-improver) are dispatched via the worker task queue. Planner creates a worker task with an instruction like "Consolidation mode. Read agents/librarian.md", heartbeat dispatches the worker agent, and the worker reads the instruction and acts as the maintenance agent. This means the agent runs with the worker's model and tools — the agent definition's `model` and `tools` frontmatter is ignored.

Additionally, heartbeat has separate dispatch logic for each agent type (planner, worker, chat) spread across Steps 3-5, each with its own concurrency checks.

## Design

### Unified dispatch loop

Replace heartbeat's separate dispatch Steps (4: Planner, 5: Worker) with a single unified dispatch loop. Chat classification (trivial/non-trivial) stays in Step 3, but non-trivial chat dispatch goes through the unified loop.

### Planner emits `Dispatch:` for maintenance

Planner Step 7 stops creating worker tasks via `kvido task create` for maintenance. Instead it emits `Dispatch:` lines in its output:

```
Dispatch: librarian
Dispatch: self-improver
Dispatch: project-enricher PROJECT=my-project
```

No `MODE=` parameter — agents determine their own mode based on current state. The only parameter is enricher's `PROJECT=` (planner selects the project based on staleness).

User-defined scheduled tasks from `memory/planner.md` still use `kvido task create` (those are arbitrary instructions, not agent dispatches).

### Task creation and concurrency via dependencies

Heartbeat creates TaskCreate entries for all dispatches. Concurrency is controlled via `blockedBy` dependencies instead of per-step manual checks.

| Source | Who creates task | Task prefix |
|--------|-----------------|-------------|
| Planner output `Dispatch: <agent>` | Heartbeat (parses output) | `maintenance:<agent>` |
| Worker queue (`kvido task list todo`) | Heartbeat | `worker:<slug>` |
| Slack DM (non-trivial) | Heartbeat | `chat:<ts>` |
| Planner due | Heartbeat | `planner` |

Concurrency rules:

| Group | Max concurrent | Implementation |
|-------|---------------|----------------|
| maintenance | 1 | Second `maintenance:*` task has `blockedBy` on first |
| worker | 1 | Second `worker:*` task has `blockedBy` on first |
| chat | 1 | Second `chat:*` task has `blockedBy` on first |
| planner | 1 | No cross-group dependency — runs in parallel with others |

No dependencies between groups — worker, maintenance, chat, and planner can run concurrently.

### Unified dispatch phase

After task creation, one loop dispatches all ready agents:

```
For each pending task from TaskList:
  1. Check blockedBy — if any blocker is in_progress/pending -> skip
  2. TaskUpdate -> in_progress
  3. Resolve model:
     - maintenance/chat/planner: read from agent frontmatter
     - worker: kvido config 'skills.worker.models.<size>'
  4. Resolve isolation:
     - worker: worktree
     - all others: none
  5. Agent tool dispatch (run_in_background: true)
```

### Agent model resolution

```bash
# Maintenance agents — read frontmatter from agent definition
grep '^model:' "agents/<agent-name>.md" | awk '{print $2}'

# Workers — existing config logic
kvido config 'skills.worker.models.<size>'
```

### Recovery check simplification

All `in_progress` tasks from previous session -> `completed` (agent process is gone). Pending tasks with unsatisfied `blockedBy` unblock automatically when the blocking task is completed.

Exception: `worker:*` tasks also run `kvido task move <slug> failed` for orphaned in-progress workers (worker tracks state via local task files).

### Edge cases

| Situation | Resolution |
|-----------|-----------|
| Planner emits 3 Dispatch: lines | TaskCreate all 3, chain blockedBy: 2nd blocked by 1st, 3rd blocked by 2nd |
| Maintenance agent fails | Task -> completed. Heartbeat logs error. Next blocked task unblocks. |
| Worker and maintenance run concurrently | OK — no cross-group dependency |
| Dispatch: for nonexistent agent | Heartbeat checks `agents/<name>.md` exists before TaskCreate. Missing -> log warning, skip. |
| Two planner runs emit same Dispatch: | Planner checks `last_*_date` — won't emit duplicates. Safety: heartbeat skips if `maintenance:<agent>` pending/in_progress exists. |

## Files to change

| File | Change |
|------|--------|
| `plugins/kvido/commands/heartbeat.md` | Merge Step 4+5 into unified dispatch loop, update recovery check |
| `plugins/kvido/hooks/context-planner.md` | Maintenance table: instruction -> `Dispatch: <agent>` |
| `plugins/kvido/skills/planner/SKILL.md` | Step 7: emit `Dispatch:` instead of `kvido task create` for maintenance |

### Unchanged

- Agent definitions (librarian, self-improver, project-enricher) — model/tools already defined in frontmatter
- `heartbeat.sh` — pure data gathering, no dispatch logic
- `kvido task create` — still used for user-defined scheduled tasks from `memory/planner.md`
- Worker agent — still processes tasks from the queue

### No new files

No new scripts or agent definitions needed.
