---
name: worker
description: Use when heartbeat dispatches the worker agent to execute a queued task from state/tasks/.
---

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Worker Skill

Worker executes assigned tasks asynchronously in the background of the heartbeat.
All queue management goes through `kvido task`.
Tasks are local markdown files in `state/tasks/` — status is the folder name, metadata is YAML frontmatter.

## Pipeline

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

**Frontmatter fields** (metadata in YAML header):
- `priority: urgent|high|medium|low`
- `size: s|m|l|xl`
- `source: planner|slack|recurring|self-improver|manual|jira|interests`
- `source_ref: <slack ts, jira key, commit hash>`
- `pipeline: true` — multi-phase task flag
- `phase: brainstorm|spec|implement|review`
- `waiting_on: <what is being waited on>`
- `recurring: <trigger JSON>`

**Task file structure:**
```markdown
---
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
| `kvido task create --title "..." --instruction "..." [--priority P] [--size S] [--source SRC] [--source-ref REF] [--worktree] [--goal G]` | Creates task file, returns slug. Pipeline auto for l/xl. |
| `kvido task read <slug>` | Returns frontmatter + content as key=value |
| `kvido task read-raw <slug>` | Returns raw markdown content of task file |
| `kvido task update <slug> <field> <value>` | Updates frontmatter field |
| `kvido task move <slug> <status>` | Moves task to a different status folder |
| `kvido task list [status]` | Lists tasks (optional filter by status) |
| `kvido task find <slug>` | Finds task and returns its current status (folder) |
| `kvido task note <slug> "<text>"` | Appends text to ## Worker Notes |
| `kvido task count [status]` | Count of tasks (optionally per status) |

## Rules

### What Worker may do
- Read any files in the repository
- Call source skills and tool skills (glab, acli, kvido slack, gws)
- Call MCP tools (Atlassian, Slack, Calendar)
- Log via `kvido log add`
- Dispatch sub-agents (researcher, reviewer) for in-depth analysis

### What Worker must not do
- Push to remote repositories without an explicit instruction in the task
- Modify `state/current.md` (owned by heartbeat)
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

## Pipeline phases (opt-in for l/xl tasks)

Worker supports a structured pipeline for large tasks. Pipeline is opt-in — activated by frontmatter `pipeline: true` (automatic for size l/xl).

### When to use pipeline

- `size: l` or `size: xl` → automatically `pipeline: true` + `phase: brainstorm`
- `size: s` and `size: m` → pipeline not used (standard execution)

### Behavior per phase

#### brainstorm
1. Read the task instruction and all available context
2. Add worker note with questions and ambiguities
3. Send Slack message with questions (max 5 questions, brief)
4. `kvido task move "$TASK_SLUG" todo` + `kvido task update "$TASK_SLUG" waiting_on "<description>"`
5. Chat-responder writes answers as worker note, updates phase
6. On next run: evaluate if enough context
   - No → another round of questions (max 3 rounds)
   - Yes → `kvido task update "$TASK_SLUG" phase spec` + `kvido task move "$TASK_SLUG" todo`

#### spec
1. Propose 2–3 approaches (minimal, clean, pragmatic)
2. Worker note + Slack message
3. `kvido task update "$TASK_SLUG" waiting_on "<waiting for choice>"`
4. Chat-responder writes choice, `kvido task update "$TASK_SLUG" phase implement`

#### implement
Standard worker execution per the chosen spec.
When done: `kvido task update "$TASK_SLUG" phase review` + `kvido task move "$TASK_SLUG" todo`.

#### review
1. Go through the implementation — bugs, conventions, simplifications
2. Worker note + Slack message
3. If blockers → `kvido task update "$TASK_SLUG" waiting_on "<blocker>"`
4. If OK → `kvido task move "$TASK_SLUG" done`

### Pipeline rules
- Worker always checks phase from `kvido task read` at start
- Each phase is a separate worker run (task returns to todo between phases)
- Max 3 Slack messages total for the entire pipeline
- User can interrupt via cancel (slug via chat)

## Worktree & PR mode

If a task has frontmatter `worktree: true`, worker runs in an isolated git worktree (heartbeat sets `isolation: "worktree"` on the Agent tool).

**Auto-worktree for assistant repo:** If a task modifies files in the assistant repository, always use worktree mode — even without an explicit `worktree: true`. Do not push directly to main.

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
| Modifying `state/current.md` | Owned by heartbeat. Worker logs via `kvido log add` and writes task notes. |
| Skipping cancel check at start | Always `kvido task find` first — task may have been cancelled while queued |
| Continuing past timeout | Check elapsed time; if > `task_timeout_minutes`, emit partial result and move to `failed/` |
| Ignoring pipeline phase | Always read `phase` from `kvido task read` — execute only the current phase, not the whole task |
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
