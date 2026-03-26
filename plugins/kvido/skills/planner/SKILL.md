---
name: planner
description: Use when heartbeat dispatches the planner agent for change detection, triage generation, and notifications.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel, mcp__claude_ai_Google_Calendar__gcal_list_events
user-invocable: false
---

# Planner

---

## Step 1: Load Context

1. Load planner state — what was done last run, found events, timestamps per source:
   - `kvido planner-state last-run get` — last run timestamp and counters
   - `kvido planner-state event list` — previously reported events
2. Load current focus: `kvido current get` — WIP, focus, blockers
3. Read `memory/planner.md` — personal instructions from the user (optional, not required)
4. Read `memory/memory.md` — long-term context (projects, people, decisions)
5. Get current time (`date -Iseconds`) and day of week

---

## Step 2: Scheduled Tasks (personal instructions)

Go through `memory/planner.md`. Look for time triggers:
- Format: `- HH:MM: <instruction>` or `- <day>: <instruction>`
- If it's time to act and it hasn't been done today (check via `kvido planner-state timestamp get <key>` — exit 1 means not done today) → execute or create a worker task via:
  ```bash
  kvido task create --instruction "<instruction>" --size s --priority high --source planner
  ```
- Record that the action was performed: `kvido planner-state timestamp set <key> <value>`

If `memory/planner.md` does not exist → skip silently.

---

## Step 3: Data Gathering

### Source discovery

Run the discovery script to find installed source plugins:

```bash
kvido discover-sources
```

Output: one line per installed source — `name<TAB>install_path`. If empty, no source plugins are installed — skip data gathering.

### Fetching data

For each discovered source plugin, read its `skills/source-*/SKILL.md` from the `install_path` and call the appropriate fetch command based on the current schedule:

| Schedule | Sources to call |
|----------|----------------|
| morning | All installed sources |
| heartbeat | All installed sources |
| eod | All installed sources; kvido-sessions only when `eod_pending: true` |

Each source SKILL.md defines its own fetch commands and capabilities. Read it and follow its instructions.

### Fetch error handling

When running a fetch script, capture both stdout and stderr, and check the exit code:

- **Exit code 0** — success, use output normally.
- **Exit code 10** — CLI tool not available, follow MCP fallback instructions in the source SKILL.md. This is NOT an error.
- **Any other non-zero exit code** — fetch failure. Emit an `Event:` line for heartbeat delivery:

```
Event: :warning: <source-name> fetch failed — <error message from stderr>. Source: <source-name>. Reference: none. Urgency: normal. Severity: :large_yellow_circle:.
```

Use dedup key `fetch-error:<source-name>` and check/record via `kvido planner-state event check/report` to avoid repeated alerts.

Log the failure: `kvido log add planner error --message "fetch failed: <source-name>: <stderr>"`.

Continue processing remaining sources — a single source failure must not abort the planner run.

### Non-source data

| Source | Command | When |
|--------|---------|------|
| Interests | see `skills/interests/SKILL.md` | if `last_interests_check` > `check_interval_hours` |

---

## Step 4: Change Detection & Notifications

Load planning rules:

```bash
kvido context planner
```

Follow the assembled rules for event dedup keys, notification levels, triage detection, and maintenance scheduling.

Compare collected data against previously reported events (loaded in Step 1 via `kvido planner-state event list`). Before notifying, check dedup: `kvido planner-state event check <key>` (exit 0 = already reported, skip). After notifying: `kvido planner-state event report <key>`.

Log all notifications — `kvido log add planner notify --message "<event summary>"`.

### Focus mode
Read focus_mode via `kvido config 'focus_mode'`.
Check calendar data — is a focus event running? → suppress immediate to batch.

### Proactive alerts
Watch for stale MR reviews, WIP tickets with no activity, status changes. Decide level based on context.

---

## Step 5: Scheduled Rules

Read `memory/planner.md` section "## Scheduled Rules". For each rule:

1. Evaluate trigger condition (time, day, "not yet today" via `kvido planner-state timestamp get <key>` — exit 1 means not done yet)
2. If triggered:
   - Execute actions inline (gather data, create journal, dispatch librarian, etc.)
   - Compose output following the rule's delivery template
   - Track execution: `kvido planner-state timestamp set <key> <value>` (e.g. key=last_morning_date, key=last_eod_date)
3. If not triggered: skip

Rules are user-defined natural language with structured triggers and actions. Interpret them flexibly. Default scheduled rules are provided by setup.

---

## Step 6: Triage & User Context

### 6a: Triage queue (agent items awaiting approval only)

Load tasks in triage state:
```bash
kvido task list triage
```

**Triage items are NOT auto-approved.** They stay in `triage` until the user explicitly approves.

Get current time for staleness check:
```bash
date -u +%s
```

For each task, read its detail: `kvido task read <slug>`. Parse `UPDATED_AT` (or `CREATED_AT` if `UPDATED_AT` is empty) and compute age in seconds: `current_epoch - updated_at_epoch`. A task is **stale** if age > 43200 (12 hours).

Separate tasks into two buckets:
- **New** — not yet stale (age ≤ 12h)
- **Stale** — stale (age > 12h), still in triage

Fill the batch of max 3 from new items first, then stale items to fill remaining slots. Stale items are re-surfaced so the user gets another chance to approve or reject them.

For each task selected (max 3 total across new + stale):
1. Evaluate relevance and urgency
2. **Clear request** → add to approval batch:
   - Suggest: title (max 8 words), priority, size, assignee=agent, brief description
   - For stale items append `(re-surface, stale >12h)` to the description
3. **Unclear** → include in output: `Question: <slug> '<title>' — <question for user>. Urgency: normal.` Leave task for next run.

### 6b: User context reminders (memory/state-first)

Load current focus via `kvido current get` and relevant changes from sources (Jira, GitLab, Gmail, Calendar, Slack). Review recent activity via `kvido log list --today --format human`. Look for:
- items in `Work in Progress` or `Blockers` that are stale or waiting for a response
- new external changes that should shift today's priority
- deadlines or follow-ups that belong in `Pinned Today` or `Notes for Tomorrow`

Output is not new GitLab issues. Output is only reminders and suggestions for current context:
- `Reminder:` for stale or pending user follow-ups
- `Event:` if a source change should shift the day's focus
- with a strong signal, explicitly suggest what to pin via `kvido current set`

Legacy compatibility:
- If you find old tasks assigned to the user, never create a new workflow from them
- You may remind about them at most once per day in the text output, if still relevant
- Track reminder history via CLI:
  - Check: `kvido planner-state reminder get <slug>` (exit 1 = not yet reminded today)
  - Record: `kvido planner-state reminder set <slug> <YYYY-MM-DD>`

### Individual triage messages

For each triage item include in output:
```
Triage: <slug> '<title>' — <description>. Priority: <priority>. Size: <size>. Assignee: <assignee>.
```

For stale re-surfaced items use:
```
Triage: <slug> '<title>' — <description> (re-surface, stale >12h). Priority: <priority>. Size: <size>. Assignee: <assignee>.
```

Also write a note on the task indicating the triage item was sent — but WITHOUT a Slack ts (heartbeat will fill that in after delivery):
```bash
kvido task note <slug> "Triage: sent for approval. Awaiting user decision."
```

For stale re-surfaced items use:
```bash
kvido task note <slug> "Triage: re-surfaced (stale >12h). Awaiting user decision."
```

**Note:** Planner runs as a subagent and does NOT have access to task tools (`TaskCreate`/`TaskUpdate`). Heartbeat (main session) will create `triage:<slug>` tasks for polling after delivery via `kvido slack`. Planner only writes notes on tasks and returns NL output.

Include stale user task reminders in output:
```
Reminder: Waiting on you: <project/source> — <brief follow-up or blocker>.
```

Max 3 triage items per run (new items take priority over stale re-surfaces).

---

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

Safety: if maintenance was already dispatched today (check via `kvido planner-state timestamp get last_<agent>_date`), skip. Heartbeat also dedup-checks via TaskList before creating the task.

---

## Step 8: Save State

Persist state via CLI commands:

1. Save last run summary (pipe JSON via stdin):
   ```bash
   kvido planner-state last-run set
   ```
2. All `last_*_date` timestamps updated in Steps 2, 5, 7 via `kvido planner-state timestamp set <key> <value>` — no separate action needed here.
3. All reminder dates updated in Step 6b via `kvido planner-state reminder set <slug> <date>` — no separate action needed here.
4. All event keys recorded in Step 4 via `kvido planner-state event report <key>` — no separate action needed here.
5. Clean up stale reported events (older than 72h):
   ```bash
   kvido planner-state event cleanup
   ```

---

## Output Format

Return a natural language summary of all notifications. Format per item:

- **Event:** `Event: <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: <high|normal|low>. Severity: <:red_circle:|:large_yellow_circle:|:large_green_circle:>.`
- **Event (batch):** `Event (batch): <emoji> <title> — <desc>. Source: <src>. Reference: <ref>. Urgency: normal. Severity: :large_yellow_circle:.`
- **Triage:** `Triage: <slug> '<title>' — <description>. Priority: <p>. Size: <s>. Assignee: <a>.`
- **Reminder:** `Reminder: <text>. Urgency: normal.`
- **Dispatch:** `Dispatch: <agent-name> KEY1=value1 KEY2=value2 ...` — heartbeat will dispatch the named agent with parameters.

If no notifications are needed, return: `No notifications.`

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Sending duplicate notification for already reported event | Always run `kvido planner-state event check <key>` before notifying |
| Creating worker tasks for things planner can log | Planner only creates tasks for actual work; status updates and reminders go into output as `Event:` or `Reminder:` |
| Skipping `last_*_date` update after maintenance task creation | Always run `kvido planner-state timestamp set <key> <value>` after creating a maintenance task to prevent duplicates |
| Creating worker tasks for maintenance agents | Emit `Dispatch: <agent>` lines — heartbeat dispatches directly with agent's own model/tools |
| Notifying `immediate` during focus mode | Check calendar for active focus events — suppress to `batch` |
| Creating user-facing tasks from legacy assigned tickets | Only remind in text output, never create new workflow from old tickets |

## Critical Rules

- **Be concise.** No filler, just data and actions.
- **State-first.** Read from files, write to files. Do not rely on conversational context.
- **Dedup.** Check Reported Events before every notification.
- **Max 3 triage items per run.** Don't get bogged down.
- **Time from system.** `date -Iseconds`.
- **Always include URLs.** Add a full clickable URL to every MR, Jira issue.
- **If a source fails** (non-zero, non-10 exit) → emit `Event:` with `:warning:` severity, log via `kvido log add`, dedup via `kvido planner-state event check/report`, continue with next source. Exit code 10 = MCP fallback, not an error.
- **Don't try to do the work yourself** — create a worker task.
