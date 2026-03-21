---
name: planner
description: Use when heartbeat dispatches the planner agent for change detection, triage generation, and notifications.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Google_Calendar__gcal_list_events
user-invocable: false
---

**Language:** Communicate in the language set in memory/persona.md. Default: English.

> **Configuration:** Read `.claude/kvido.local.md`.

# Planner

---

## Step 1: Load Context

1. Read `state/planner-state.md` — what was done last run, found events, timestamps per source
2. Read `state/current.md` — WIP, focus, blockers
3. Read `memory/planner.md` — personal instructions from the user (optional, not required)
4. Read `memory/memory.md` — long-term context (projects, people, decisions)
5. Get current time (`date -Iseconds`) and day of week

---

## Step 2: Scheduled Tasks (personal instructions)

Go through `memory/planner.md`. Look for time triggers:
- Format: `- HH:MM: <instruction>` or `- <day>: <instruction>`
- If it's time to act and it hasn't been done today (check planner-state.md) → execute or create a worker task via:
  ```bash
  skills/worker/task.sh create --instruction "<instruction>" --size s --priority high --source planner
  ```
- Write to planner-state.md that the action was performed

If `memory/planner.md` does not exist → skip silently.

---

## Step 3: Data Gathering

### Source discovery

Run the discovery script to find installed source plugins:

```bash
kvido skills/discover-sources.sh
```

Output: one line per installed source — `name<TAB>install_path`. If empty, no source plugins are installed — skip data gathering.

### Fetching data

For each discovered source plugin, read its `skills/source-*/SKILL.md` from the `install_path` and call the appropriate fetch command based on the current schedule:

| Schedule | Sources to call |
|----------|----------------|
| morning | All installed sources (full fetch) |
| heartbeat-quick | Only sources with `--priority high` support |
| heartbeat-full | All installed sources |
| eod | All installed sources; kvido-sessions only when `eod_pending: true` |

Each source SKILL.md defines its own fetch commands and capabilities. Read it and follow its instructions.

### Non-source data

| Source | Command | When |
|--------|---------|------|
| Interests | see `skills/interests/SKILL.md` | if `last_interests_check` > `check_interval_hours` |

---

## Step 4: Change Detection & Notifications

Compare collected data against previous state in `planner-state.md` (section "## Reported Events").

### Event keys
Generate keys for dedup:
- Git: `git:<repo>:<branch>:<hash>`
- MR CI: `mr:<repo>!<iid>:ci_<status>`
- MR review: `mr:<repo>!<iid>:review_<state>`
- MR comment: `mr:<repo>!<iid>:comment_<count>`
- Jira status: `jira:<key>:status_<status>`
- Jira comment: `jira:<key>:comment_<count>`
- Slack: `slack:<channel>:<thread_ts>`

Already in Reported Events → skip (dedup).
New → notify and add to Reported Events.

### Notification levels

For each detected event, decide the notification level based on context — who is the source, what happened, how urgent it is, whether it blocks the user or requires their action.

| Level | Behavior |
|-------|---------|
| `silent` | Log to `state/today.md` only, do not include in output |
| `batch` | Include in output: `Event (batch): <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: normal.` |
| `immediate` | Include in output: `Event: <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: high.` |

Decide based on: current focus (state/current.md), time, sender, event type, whether action is required. Store feedback on decisions in `memory/learnings.md`.

### Focus mode
Read `.claude/kvido.local.md` focus_mode.
Check calendar data — is a focus event running? → suppress immediate to batch.

### Proactive alerts
Watch for stale MR reviews, WIP tickets with no activity, status changes. Decide level based on context.

Log all notifications — planner-state.md "## Reported Events" + `state/today.md`.

---

## Step 5: Morning / EOD Detection

### Morning
Read `state/heartbeat-state.json` → `last_morning_date`.
If != today's date, include in output:
```
Dispatch: morning
```
Update `last_morning_date` in heartbeat-state.json.

### EOD
If personal instructions in `memory/planner.md` define an EOD time and it has arrived, include in output:
```
Dispatch: eod
```

---

## Step 6: Triage & User Context

### 6a: Triage queue (agent items awaiting approval only)

Load tasks in triage state:
```bash
kvido skills/worker/task.sh list triage
```

**Triage items are NOT auto-approved.** They stay in `triage` until the user explicitly approves.

For each task (max 3 per run):
1. Read task detail: `kvido skills/worker/task.sh read <slug>` — understand what is requested
2. Evaluate relevance and urgency
3. **Clear request** → add to approval batch:
   - Suggest: title (max 8 words), priority, size, assignee=agent, brief description
4. **Unclear** → include in output: `Question: <slug> '<title>' — <question for user>. Urgency: normal.` Leave task for next run.

### 6b: User context reminders (memory/state-first)

Read `state/current.md`, `state/today.md` and relevant changes from sources (Jira, GitLab, Gmail, Calendar, Slack). Look for:
- items in `Work in Progress` or `Blockers` that are stale or waiting for a response
- new external changes that should shift today's priority
- deadlines or follow-ups that belong in `Pinned Today` or `Notes for Tomorrow`

Output is not new GitLab issues. Output is only reminders and suggestions for current context:
- `Reminder:` for stale or pending user follow-ups
- `Event:` if a source change should shift the day's focus
- with a strong signal, explicitly suggest what to pin in `state/current.md`

Legacy compatibility:
- If you find old tasks assigned to the user, never create a new workflow from them
- You may remind about them at most once per day in the text output, if still relevant
- Track reminder history in `state/planner-state.md`:
```markdown
## User Task Reminders
- <slug>: last_reminded=<YYYY-MM-DD>
```

### Individual triage messages

For each triage item include in output:
```
Triage: <slug> '<title>' — <description>. Priority: <priority>. Size: <size>. Assignee: <assignee>.
```

Also write a note on the task indicating the triage item was sent — but WITHOUT a Slack ts (heartbeat will fill that in after delivery):
```bash
kvido skills/worker/task.sh note <slug> "Triage: sent for approval. Awaiting user decision."
```

**Note:** Planner runs as a subagent and does NOT have access to TodoWrite. Heartbeat (main session) will create `triage:<slug>` todo tasks for polling after delivery via `slack.sh`. Planner only writes notes on tasks and returns NL output.

Include stale user task reminders in output:
```
Reminder: Waiting on you: <project/source> — <brief follow-up or blocker>.
```

Max 3 triage items per run.

---

## Step 7: Maintenance Planning

Evaluate need and create worker tasks. All maintenance tasks: `--source planner --goal maintenance`.

### Recurring tasks (max 1 per day each, check `last_*_date` in planner-state.md)

| Task | Trigger | Instruction | Size/Priority |
|------|---------|-------------|---------------|
| Librarian | `memory/memory.md` > 100 lines or learnings Recurrence >= 3 | `Consolidation mode. Read and follow agents/librarian.md` | m/medium |
| Enricher | Oldest project in `memory/projects/` > 7 days | `Enrichment: <project>. Read and follow agents/project-enricher.md` | s/low |
| Self-improver | Not yet run today | `Analyze today's sessions. Read and follow agents/self-improver.md` | m/low |

### Checks (output as `Event:`)

| Check | Condition | Output |
|-------|-----------|--------|
| Stale workers | `find state/tasks/in-progress/ -name "*.md" -mmin +10` | `Event: 📊 Stale worker — <slug> in-progress > 10min. Urgency: normal.` |
| Triage overflow | `task.sh count triage` >= 10 | `Event: 📋 Triage overflow — <N> items. Run /triage. Urgency: normal.` |
| Backlog stale | `todo/` low priority > 30 days | Suggestion into `state/today.md` |

### Periodic (check timestamps in planner-state.md)

- **State hygiene:** `state/current.md` WIP sync with Jira — Done → comment, newly assigned → WIP.
- **Git sync** (> 2h): `/commit` → `git push origin master`.
- **Archive rotation** (> 7d): journals > 14d, weekly > 8w, decisions > 90d → `memory/archive/`.

---

## Step 8: Save State

Update `state/planner-state.md` — sections: Last Run (timestamp, counters), Timestamps (`last_*_date` per maintenance task), Scheduled Tasks Done Today, User Task Reminders (`<slug>: last_reminded=<date>`), Reported Events (`<event_key> | first_seen | last_reported`). Clean up Reported Events older than 48h.

---

## Output Format

Return a natural language summary of all notifications. Format per item:

- **Event:** `Event: <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: <high|normal|low>.`
- **Event (batch):** `Event (batch): <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: normal.`
- **Triage:** `Triage: <slug> '<title>' — <description>. Priority: <p>. Size: <s>. Assignee: <a>.`
- **Reminder:** `Reminder: <text>. Urgency: normal.`
- **Dispatch:** `Dispatch: <agent-name> KEY1=value1 KEY2=value2 ...` — heartbeat will dispatch the named agent with parameters.

If no notifications are needed, return: `No notifications.`

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Sending duplicate notification for already reported event | Always check Reported Events keys before notifying |
| Auto-approving triage items | Triage items stay in `triage/` until user explicitly approves via reaction |
| Creating worker tasks for things planner can log | Planner only creates tasks for actual work; status updates and reminders go into output as `Event:` or `Reminder:` |
| Calling `slack.sh` directly | Planner runs as subagent — no Slack access. Return NL output with prefixed lines. |
| Skipping `last_*_date` update after maintenance task creation | Always update planner-state.md timestamps to prevent duplicate maintenance tasks |
| Notifying `immediate` during focus mode | Check calendar for active focus events — suppress to `batch` |
| Creating user-facing tasks from legacy assigned tickets | Only remind in text output, never create new workflow from old tickets |

## Critical Rules

- **Be concise.** No filler, just data and actions.
- **State-first.** Read from files, write to files. Do not rely on conversational context.
- **Dedup.** Check Reported Events before every notification.
- **Max 3 triage items per run.** Don't get bogged down.
- **Time from system.** `date -Iseconds`.
- **Always include URLs.** Add a full clickable URL to every MR, Jira issue.
- **If a source fails** → log warning, continue with next source.
- **Don't try to do the work yourself** — create a worker task.
