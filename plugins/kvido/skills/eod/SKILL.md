---
name: eod
description: Use when the user ends their day or invokes /eod for journal entry and worklog check.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronList, CronDelete, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian__addWorklogToJiraIssue
---

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# End-of-Day

Proceed step by step.

## Tone Guidelines

Tone and style per `memory/persona.md` (EOD section). If persona does not exist, be concise and factual.

---

## Step 1: Gather Today's Data

Read `state/today.md` (heartbeat log) and `state/current.md` (focus, WIP).

Determine today's date (YYYY-MM-DD).

### Activity log summarization

If `state/activity-log.jsonl` exists, calculate today's stats:
```bash
TODAY=$(date +%Y-%m-%d)
jq -s --arg today "${TODAY}T00:00:00" '[.[] | select(.ts >= $today)]' state/activity-log.jsonl
```

From the filtered records extract:
- **Total tokens for the day:** `map(.tokens // 0) | add`
- **Top agent by tokens:** `group_by(.agent) | map({agent: .[0].agent, tokens: (map(.tokens // 0) | add)}) | sort_by(-.tokens)`
- **Task count:** `map(.task_id // empty) | unique | length`
- **Dispatch/execute cycle count:** `map(select(.action == "execute")) | length`

Include summary in the journal entry (Step 2) as section `## Token Usage`.

Run `skills/discover-sources.sh` to find installed source plugins. For each discovered source relevant to EOD (sessions, gitlab), read its `skills/source-*/SKILL.md` from the install path and call the EOD fetch command.

**Uncommitted work detection** — read `.claude/kvido.local.md`, for each repo:

```bash
git -C <repo_path> status --porcelain
git -C <repo_path> stash list
```

Collect repos with uncommitted changes or stashes.

---

## Step 2: Create Journal Entry

Create journal by combining:
- Session parser (what was worked on, how long)
- Git activity (commits today)
- Heartbeat log from `state/today.md`
- WIP and blocker status from `state/current.md`
- Uncommitted work (repo: N modified, M untracked, K stashes)

Format:

```
# Journal — YYYY-MM-DD

## Summary
<!-- 2-3 sentences: main focus, what was accomplished -->

## Work Done
<!-- Per project, bullet points -->

## Goals Progress
<!-- Completed tasks today: check state/tasks/done/*.md, filter by updated_at today -->
<!-- skills/worker/task.sh list done → for each task.sh read <slug> → filter updated_at == today -->
<!-- Group by goal field in frontmatter. Tasks without goal shown under "Other". -->
<!-- Format: ### Goal Name\n- <slug>: title -->

## MRs
<!-- MR status: created, updated, merged, reviewed -->

## Blockers & Issues
<!-- Unresolved, carry forward -->

## Token Usage
<!-- Total tokens, top agent, run count — from activity-log.jsonl. Skip if JSONL does not exist. -->

## Unfinished Work
<!-- Repos with uncommitted changes -->

## Tomorrow
<!-- What to continue, deadlines -->
```

Write to `memory/journal/YYYY-MM-DD.md`.

---

## Step 3: Worklog Check

Build time summary from session-parser + git-activity + calendar:
- Group by Jira ticket/project
- Estimate time (round to 15 min; git-only = 15 min/commit, max 2h)
- Meetings from `state/today.md` as separate lines
- No ticket = `(internal)`

Fetch existing worklogs via Atlassian MCP:
```
searchJiraIssuesUsingJql:
  cloudId: $ATLASSIAN_CLOUD_ID  # from .env
  jql: worklogAuthor = currentUser() AND worklogDate = "YYYY-MM-DD"
  fields: ["summary", "worklog", "timespent"]
```

Compare. Tolerance: +-30 min. Output table:

```
## Worklog — YYYY-MM-DD

| Ticket | Project | Time | Description | Status |
|--------|---------|------|-------------|--------|
| PROJ-123 | my-project | 3h | Feature implementation | not logged |
```

If all logged: "All logged." Otherwise show table + "Do you want to log?"

On confirmation, log via `addWorklogToJiraIssue`.

---

## Step 4: Dispatch Librarian

Dispatch librarian subagent for extraction:

```
Agent tool:
  prompt: "Extraction mode. Parse memory/journal/YYYY-MM-DD.md, extract facts into memory/projects/, memory/people/, memory/decisions/. Update memory/this-week.md. Update memory/memory.md if project state or decisions have changed."
```

---

## Step 5: Work Sync

Determine personal work status from `state/current.md`, today's changes and live sources. Check GitLab work queue only for assistant tasks.

- Jira / GitLab / mail / calendar:
  - record what actually moved forward today
  - highlight what remains incomplete or awaiting a response
  - if work happened outside previous current context, add it to the journal and `state/current.md`; do not create a user issue for this
- Assistant work queue:
  - you may check `status:todo|status:in-progress` for worker tasks and mention relevant status in the journal if important

---

## Step 6: Update Working Memory

Update `state/current.md`:
- **Active Focus** — clear
- **Pinned Today** — clear or move to `Notes for Tomorrow`
- **Work in Progress** — update statuses, mark completed, add new
- **Blockers** — current state
- **Parked** — no change
- **Notes for Tomorrow** — uncommitted work, follow-ups, deadlines

Reset `state/heartbeat-state.json`: `iteration_count` to 0, clear `reported`.

---

## Step 7: Friday — Weekly Summary

Determine day of week. If Friday:

Read all journals from this week in `memory/journal/`.

Create weekly summary:

```
# Weekly Summary — YYYY-Www

## Highlights
<!-- 3-5 key accomplishments -->

## Per Project
<!-- Project — what was done — current status -->

## MRs
<!-- Created, merged, reviewed this week -->

## Blockers & Carry-forward
<!-- What was not finished and why -->

## Backlog Stats
<!-- Done items this week, open items count -->

## Next Week
<!-- Priorities, deadlines -->
```

Write to `memory/weekly/YYYY-Www.md`.

**Archive rotation:**
```bash
mkdir -p memory/archive/journal memory/archive/weekly memory/archive/decisions
```

Move journals older than 14 days to `memory/archive/journal/`.
Move weeklies older than 8 weeks to `memory/archive/weekly/`.

---

## Step 7b: Daily Questions

Read `skills/daily-questions/SKILL.md` and follow the instructions.
If the skill is disabled or it is not a work day, skip.

---

## Step 8: Cleanup & Confirm

Heartbeat loop continues in night mode (chat check + silent git watch only). Do not remove cron.

Return NL output with day summary — heartbeat will deliver it to Slack via `slack.sh`. Do not call `slack.sh` directly. Structure output per `eod` template (date, summary, session_time, done_count, open_count).

Output:
> "Journal written to `memory/journal/YYYY-MM-DD.md`. Heartbeat switching to night mode. Have a good evening!"

If weekly: add info about the weekly summary.

Be concise.
