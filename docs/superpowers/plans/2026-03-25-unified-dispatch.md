# Unified Agent Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-agent dispatch logic in heartbeat with a unified dispatch loop, and switch maintenance agents from worker-task-queue indirection to direct dispatch via planner `Dispatch:` output.

**Architecture:** Planner emits `Dispatch: <agent-name>` lines for maintenance instead of creating worker tasks. Heartbeat creates TaskCreate entries for all agent types (planner, worker, chat, maintenance) and dispatches them through one unified loop. Concurrency is controlled via `blockedBy` dependencies between same-group tasks.

**Tech Stack:** Markdown skill/command/hook files (no compiled code, no tests, no build)

**Spec:** `docs/superpowers/specs/2026-03-25-unified-dispatch-design.md`
**Issue:** [#105](https://github.com/spajxo/kvido/issues/105)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `plugins/kvido/hooks/context-planner.md` | Modify | Maintenance table: change instruction column to `Dispatch: <agent>` |
| `plugins/kvido/skills/planner/SKILL.md` | Modify | Step 7: emit `Dispatch:` lines instead of `kvido task create` for maintenance |
| `plugins/kvido/commands/heartbeat.md` | Modify | Merge Step 4+5 into unified dispatch loop, simplify recovery, handle `Dispatch:` in 3c |

---

### Task 1: Update context-planner.md maintenance table

**Files:**
- Modify: `plugins/kvido/hooks/context-planner.md:36-42`

- [ ] **Step 1: Edit the Maintenance Tasks table**

Change the "Instruction" column from worker task instructions to `Dispatch:` directives:

| Task | Trigger | Instruction | Size/Priority |
|------|---------|-------------|---------------|
| Librarian | Not yet run today (check `last_librarian_date`, max 1/day) | `Dispatch: librarian` | — |
| Enricher | Oldest project in memory/projects/ > 7 days | `Dispatch: project-enricher PROJECT=<project>` | — |
| Self-improver | Not yet run today | `Dispatch: self-improver` | — |

Remove Size/Priority values — maintenance agents are dispatched directly, not queued as worker tasks, so size/priority don't apply.

- [ ] **Step 2: Verify no other references to old worker-task instructions for maintenance**

Grep for `"Consolidation mode"`, `"Enrichment:"`, `"Analyze today"` in the codebase to ensure no stale references remain.

- [ ] **Step 3: Commit**

```bash
git add plugins/kvido/hooks/context-planner.md
git commit -m "refactor: change maintenance instructions to Dispatch: directives (#105)"
```

---

### Task 2: Update planner SKILL.md Step 7

**Files:**
- Modify: `plugins/kvido/skills/planner/SKILL.md:191-197`

- [ ] **Step 1: Rewrite Step 7 to emit Dispatch: lines**

Replace the current Step 7 content. Key changes:
- Instead of `kvido task create --instruction "..." --source planner --goal maintenance`, the planner emits `Dispatch: <agent-name>` lines in its NL output
- Keep the trigger logic (check `last_*_date` via `kvido planner-state timestamp get <key>`)
- Keep the state update (`kvido planner-state timestamp set <key> <value>`) after emitting each Dispatch:
- For enricher, include `PROJECT=<slug>` parameter
- Remove references to `--source planner --goal maintenance` for maintenance tasks

New Step 7 content:

```markdown
## Step 7: Maintenance Dispatch

Evaluate maintenance needs and emit `Dispatch:` lines. Heartbeat will create tasks and dispatch agents directly (not via worker queue). Each agent determines its own mode based on current state.

Load maintenance rules from assembled context (already loaded in Step 4 via `kvido context planner`). The context defines recurring tasks with their triggers. Check `last_*_date` timestamps via `kvido planner-state timestamp get <key>` to avoid duplicates.

For each triggered maintenance task, emit a `Dispatch:` line and record execution:

```
Dispatch: librarian
```

```bash
kvido planner-state timestamp set last_librarian_date "$(date -Iseconds)"
```

For enricher, include the target project:

```
Dispatch: project-enricher PROJECT=<project-slug>
```

Safety: if `maintenance:<agent>` is already pending/in_progress (check via `kvido task list` or note in planner-state), skip the dispatch to avoid duplicates.
```

- [ ] **Step 2: Update the Common Mistakes table**

Add entry: "Creating worker tasks for maintenance agents" -> "Emit `Dispatch: <agent>` lines — heartbeat dispatches directly with agent's own model/tools"

- [ ] **Step 3: Verify consistency with Output Format section**

The Output Format section (line ~225) already documents `Dispatch:` prefix. Confirm it matches — no changes needed if it already says `Dispatch: <agent-name> KEY1=value1 KEY2=value2 ...`.

- [ ] **Step 4: Commit**

```bash
git add plugins/kvido/skills/planner/SKILL.md
git commit -m "refactor: planner emits Dispatch: for maintenance instead of worker tasks (#105)"
```

---

### Task 3: Rewrite heartbeat.md dispatch logic

This is the largest task. Read the full current `plugins/kvido/commands/heartbeat.md` before editing.

**Files:**
- Modify: `plugins/kvido/commands/heartbeat.md`

- [ ] **Step 1: Simplify the recovery check in Step 2**

Replace the per-type recovery logic with unified logic:

```markdown
### Recovery check

Use `TaskList` to list all existing tasks. Mark all `in_progress` tasks from a previous session as `completed` (agent process is gone from previous session). Pending tasks with unsatisfied `blockedBy` unblock automatically.

Exception: for `worker:*` in_progress tasks, also run `kvido task move <slug> failed` to mark the local task file as failed (worker tracks state via local task files independently).
```

- [ ] **Step 2: Update Step 3c to handle Dispatch: lines from planner output**

In the "Per-agent specifics" table, update the `planner` row. Currently it says `Dispatch:` -> `dispatch named agent`. Expand this to be explicit:

For each `Dispatch: <agent-name> [KEY=value ...]` line in planner output:
1. Check if `agents/<agent-name>.md` exists (resolve path relative to plugin root). Missing -> log warning, skip.
2. Check if `maintenance:<agent-name>` task already exists (pending/in_progress) via `TaskList`. Exists -> skip (dedup).
3. `TaskCreate` subject `maintenance:<agent-name>`, description with any KEY=value parameters.
4. If another `maintenance:*` task is pending/in_progress, set `addBlockedBy` on the new task pointing to it (max 1 concurrent maintenance).

- [ ] **Step 3: Replace Step 4 (Planner Dispatch) and Step 5 (Worker Dispatch) with unified dispatch loop**

Remove the current Step 4 and Step 5. Replace with a single new step:

```markdown
## Step 4: Unified Dispatch Loop

### Task creation phase

Create tasks for all pending dispatches. Use `TaskList` to check existing tasks before creating duplicates.

**a. Planner:**
If `PLANNER_DUE == true` and no `planner` task pending/in_progress:
- `TaskCreate` subject `planner`, description `"Planner dispatch at <timestamp>"`

**b. Worker:**
If `NEXT_TASK` is not empty and no `worker:*` task pending/in_progress:
- `kvido task move "$NEXT_TASK" in-progress`
- `kvido task read "$NEXT_TASK"` -> get SIZE, PRIORITY, SOURCE_REF, INSTRUCTION
- `TaskCreate` subject `worker:<NEXT_TASK>`, description with task details
- If another `worker:*` task is pending/in_progress, set `addBlockedBy`

**c. Maintenance:**
Handled in Step 3c when planner output contains `Dispatch:` lines (already created there).

**d. Chat:**
Non-trivial chat from Step 3 creates `chat:<ts>` task. If another `chat:*` task is pending/in_progress, set `addBlockedBy`.

### Dispatch phase

For each `pending` task from `TaskList` (excluding `triage:*` and `notify:*`):
1. Check `blockedBy` — if any blocker has status `pending` or `in_progress` -> skip
2. `TaskUpdate` -> `in_progress`
3. Resolve agent config:
   - `maintenance:*` -> read `model` from `agents/<name>.md` frontmatter via: `grep '^model:' agents/<name>.md | awk '{print $2}'`. No isolation (no worktree).
   - `worker:*` -> model from `kvido config 'skills.worker.models.<SIZE>'` (or `kvido config 'skills.worker.urgent_model'` if PRIORITY==urgent). Isolation: `worktree`.
   - `planner` -> model from agent frontmatter. No isolation.
   - `chat:*` -> model from agent frontmatter. No isolation.
4. Dispatch via `Agent` tool (`run_in_background: true`, model and isolation per above)
5. Log: `kvido log add <type> dispatch --message "<summary>"`
```

- [ ] **Step 4: Renumber subsequent steps**

Old Step 6 (Adaptive Interval) becomes Step 5. Update any internal references.

- [ ] **Step 5: Update the Common Mistakes table**

Remove entries that reference old per-step dispatch checks. Add:
- "Dispatching agent when same-group task is pending/in_progress" -> "Use `blockedBy` dependencies, dispatch loop skips blocked tasks"
- "Creating maintenance tasks via kvido task create" -> "Maintenance uses `Dispatch:` from planner, heartbeat creates TaskCreate entries"

- [ ] **Step 6: Update the Dependency rule in Critical Rules**

Replace current dependency rule with:
```
- **Concurrency via dependencies.** Same-group tasks use `blockedBy`. Max 1 concurrent per group (maintenance, worker, chat). Planner runs in parallel with all groups. Dispatch loop skips tasks with unresolved blockers.
```

- [ ] **Step 7: Verify the full document reads coherently**

Read the complete modified heartbeat.md top to bottom. Check:
- No references to old Step 4 (Planner Dispatch) or Step 5 (Worker Dispatch)
- Step numbers are sequential
- Cross-references between steps are correct
- Chat dispatch in Step 3 correctly defers to unified loop for actual Agent dispatch

- [ ] **Step 8: Commit**

```bash
git add plugins/kvido/commands/heartbeat.md
git commit -m "refactor: unified dispatch loop replacing per-agent dispatch steps (#105)"
```

---

### Task 4: Final verification

- [ ] **Step 1: Cross-file consistency check**

Grep for stale references across all three modified files:
- `"Step 4"` / `"Step 5"` in heartbeat.md (should reference new numbering)
- `"worker task"` in context-planner.md maintenance section (should be gone)
- `"--goal maintenance"` anywhere (should be gone)

- [ ] **Step 2: Verify agent definitions have model in frontmatter**

Confirm these agents have `model:` in their YAML frontmatter:
- `agents/librarian.md` (expect: sonnet)
- `agents/self-improver.md` (expect: sonnet)
- `agents/project-enricher.md` (expect: haiku)
- `agents/planner.md` (expect: sonnet)
- `agents/chat-agent.md` (check what model is set)

No changes needed — just verify the dispatch loop will find what it expects.

- [ ] **Step 3: Verify Dispatch: grammar in planner output format**

Read `plugins/kvido/skills/planner/SKILL.md` Output Format section and `plugins/kvido/hooks/context-session.md` Agent Output Grammar. Confirm `Dispatch:` format is consistent across all three locations.
