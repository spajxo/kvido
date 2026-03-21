---
name: morning
description: Use when the user says good morning or invokes /morning for a daily briefing.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_channel
---

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Morning Briefing

Proceed step by step. Be concise. Do not skip steps.

## Tone Guidelines

Tone and style per `memory/persona.md` (Morning section). If persona does not exist, be concise and factual.

---

## Step 1: Load Context

### Activity log rotation

Rotate yesterday's activity log to archive:
```bash
mkdir -p state/archive
YESTERDAY=$(date -d yesterday +%Y-%m-%d)
if [[ -f state/activity-log.jsonl ]]; then
  mv state/activity-log.jsonl "state/archive/activity-log-${YESTERDAY}.jsonl"
fi
# Delete archives older than 7 days
find state/archive -name "activity-log-*.jsonl" -mtime +7 -delete 2>/dev/null || true
```

### Load state

Read `state/current.md`. Note Active Focus, WIP, Blockers, Parked, Notes for Tomorrow.

Read `memory/memory.md` for long-term context.

List files in `memory/journal/`. If any exist, read the most recent (highest date in filename). Note what was worked on yesterday and what remains open.

---

## Step 2: Gather Fresh Data

Determine yesterday's date (YYYY-MM-DD).

Run `kvido skills/discover-sources.sh` to find installed source plugins. For each discovered source, read its `skills/source-*/SKILL.md` from the install path and call the morning fetch command. Pass the date as a literal string (not command substitution).

If no source plugins are installed, skip to Step 3.

Extract: active repo, session durations, touched tasks, MR status.

---

## Step 3: Query External Sources

Run all queries before synthesizing.

### Jira

Jira data are part of the morning gather mode (source-jira fetch).
Record keys, summaries, statuses. Note issues with status changes.

### Google Calendar

Calendar data comes from gather (source-calendar fetch.sh) — categorization and deep-work calculation are part of the fetch.sh output.
Extract: event overview by category, total meeting time, remaining free deep-work time.

### Slack

Slack data are part of the morning gather mode (source-slack watch-channels).
Read `.claude/kvido.local.md` → `sources.slack` for channel priorities.

Filter for: direct mentions, thread replies, DMs.

Mentions from unmonitored channels → write to Recommendations: "Mentions from unmonitored channel #X — add to sources?"

---

## Step 4: Synthesize Briefing

Output the briefing in this format:

```
# Morning Briefing — YYYY-MM-DD

## Yesterday's Work
<!-- For each project with > 30 min: one line describing activities.
     Sources (by priority): 1. git commits (subject lines, max 3), 2. user messages from sessions (keywords).
     Format: - project (~Xh Ym) — what was done, max 10 words
     Projects with <= 30 min: just - project (~Xm) with no description -->

## Overnight Changes
<!-- New commits from others, MR status changes, Jira updates, Slack mentions -->

## Today's Schedule
<!-- Events chronologically with category -->
<!-- Total meeting time + free time -->

## Inbox
<!-- Total unread email count -->
<!-- Important emails from priority senders (per kvido.local.md) — from, subject -->
<!-- If empty: "Inbox: empty" -->

## Recommendations
<!-- 2-3 action items with specific references (MR numbers, ticket keys) -->
```

Be concise. Bullet points. No filler.

### Triage check

Count triage tasks:
```bash
kvido skills/worker/task.sh count triage
```
If > 0:
> "X items in agent triage — run `/triage` to process."

---

## Step 5: Set Today's Focus

Ask:

> "What do you want to focus on today?"

Wait for a response. Then update `state/current.md`:

- **Active Focus** — what the user said
- **Pinned Today** — 1-3 most important priorities for the day derived from focus and morning context
- **Work in Progress** — keep open items, remove completed ones
- **Blockers** — clear resolved, keep unresolved
- **Parked** — no change
- **Notes for Tomorrow** — clear (surfaced)

Write updated `state/current.md`.

Write briefing to `state/today.md` (overwrite if exists).

Return NL output with day overview — heartbeat will deliver it to Slack via `slack.sh`. Do not call `slack.sh` directly. Structure output per `morning` template (date, briefing body, triage_count, meeting_time, deepwork_time).

---

## Step 6: Start Heartbeat

> "Starting heartbeat. Running `/loop 10m`."

Run `/loop 10m`.
