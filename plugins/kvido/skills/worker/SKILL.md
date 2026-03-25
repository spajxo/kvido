---
name: worker
description: Use when heartbeat dispatches the worker agent to execute a queued task from the task queue.
---

# Worker Skill

Worker executes assigned tasks asynchronously in the background of the heartbeat.
All queue management goes through `kvido task`.
Tasks are tracked as markdown files — status is managed via `kvido task move`, metadata is YAML frontmatter.

## Task Status Flow

```
triage/ → todo/ → in-progress/ → done/
                                → failed/
                                → cancelled/
```

- `triage/` — unsorted, awaiting approval
- `todo/` — ready to work
- `in-progress/` — currently being worked on
- `done/` — completed
- `failed/` — failed
- `cancelled/` — cancelled

**Task files** are named `<id>-<slug>.md` (e.g. `42-fix-auth-bug.md`). All commands accept either numeric ID or slug.

**Frontmatter fields** (metadata in YAML header):
- `task_id: <auto-incrementing integer>`
- `priority: urgent|high|medium|low`
- `size: s|m|l|xl`
- `source: planner|slack|recurring|self-improver|manual|jira|interests`
- `source_ref: <slack ts, jira key, commit hash>`
- `waiting_on: <what is being waited on>`
- `recurring: <trigger JSON>`

**Task file structure:**
```markdown
---
task_id: 42
priority: medium
size: m
source: slack
source_ref: "1773933088.437"
---
## Instruction
<instruction text>

## Worker Notes
<worker output>
```

## kvido task subcommands

| Subcommand | Action |
|------------|--------|
| `kvido task create --title "..." --instruction "..." [--priority P] [--size S] [--source SRC] [--source-ref REF] [--goal G]` | Creates task file (`<id>-<slug>.md`), returns slug. User-initiated sources (slack, manual) route to `todo/`; agent-generated sources route to `triage/`. |
| `kvido task read <id\|slug>` | Returns frontmatter + content as key=value (includes TASK_ID) |
| `kvido task read-raw <id\|slug>` | Returns raw markdown content of task file |
| `kvido task update <id\|slug> <field> <value>` | Updates frontmatter field |
| `kvido task move <id\|slug> <status>` | Moves task to a different status folder |
| `kvido task list [status]` | Lists tasks (optional filter by status) |
| `kvido task find <id\|slug>` | Finds task and returns its current status (folder) |
| `kvido task note <id\|slug> "<text>"` | Appends text to ## Worker Notes |
| `kvido task count [status]` | Count of tasks (optionally per status) |
| `kvido task migrate-ids` | Assign numeric IDs to legacy tasks without IDs |

## Rules

### What Worker may do
- Read any files in the repository
- Call source skills and tool skills (glab, acli, kvido slack, gws)
- Call MCP tools (Atlassian, Slack, Calendar)
- Log via `kvido log add`
- Dispatch sub-agents (researcher, reviewer) for in-depth analysis

### What Worker must not do
- Push to remote repositories without an explicit instruction in the task
- Modify current context (owned by heartbeat — use `kvido current get` to read, never write directly)
- Dispatch additional workers (no worker → worker chaining)
- Send more than 3 Slack messages per task
- Continue if task is in done/failed/cancelled (check at start)

### Cancel handling
At the start of work, verify the task has not been cancelled/completed:
```bash
STATUS=$(kvido task find "$TASK_SLUG")
[[ "$STATUS" =~ ^(done|failed|cancelled)$ ]] && exit 0  # silent — cancel or race condition
```

### Timeout
If a task takes > `task_timeout_minutes` (from `settings.json`):
1. Send partial result with what you have
2. `kvido task note "$TASK_SLUG" "## Failed\nTimeout after Xm"` + `kvido task move "$TASK_SLUG" failed`
3. If progress > 50% → add follow-up: `kvido task create "<title>" --priority medium --size s`

## Worktree & PR mode

**Worktree is always on.** All worker tasks run in an isolated git worktree. Heartbeat always sets `isolation: "worktree"` on the Agent tool. If the worker makes no changes, Claude Code automatically cleans up the worktree — no overhead beyond creation.

This removes the need for agents to predict whether a task will modify files.

### Rules
- Commit all changes into the worktree branch
- `git push -u origin HEAD`
- User creates the MR manually
- Do not push directly to main
- Branch name: automatically from worktree (Claude Code creates it)

### Commit message
Use conventional commit message (feat/fix/chore) based on the type of change.

### After completing a worktree task
- `kvido task note "$TASK_SLUG" "## Result\nBranch: <branch>, pushed. <description of changes>"`
- `kvido task move "$TASK_SLUG" done`
- Slack report includes the branch name

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Sending Slack messages directly via `kvido slack` | Worker returns NL output — heartbeat handles all delivery |
| Chaining workers (dispatching another worker from worker) | Forbidden. Create a follow-up task via `kvido task create` instead. |
| Writing current context directly | Owned by heartbeat. Read via `kvido current get`. Worker logs via `kvido log add` and writes task notes. |
| Skipping cancel check at start | Always `kvido task find` first — task may have been cancelled while queued |
| Continuing past timeout | Check elapsed time; if > `task_timeout_minutes`, emit partial result and move to `failed/` |
| Pushing to main in worktree mode | Always push to feature branch. Never push directly to main. |

## Report format

Return NL output — heartbeat handles delivery. Do not call `kvido slack` directly.

Structure output per the `worker-report` template (heartbeat will use it for formatting):

Expected appearance:
```
🔧 *<brief task name>*
━━━━━━━━━━━━━━━━
✅ <concrete result 1>
✅ <concrete result 2>
⚠️ <warning — only if relevant>

<slug> · <Xm Ys>
```

**Specificity is mandatory.**
Not "checked MRs" but "group/project !342: waiting 3 days, assignee Jan, 2 unresolved comments".
If output > 3000 chars → trim to top 5 items + "and X more".
