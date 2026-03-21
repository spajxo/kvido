---
description: Heartbeat — orchestrator, chat check, worker dispatch, log, adaptive interval
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronCreate, CronList, CronDelete, mcp__claude_ai_Slack__slack_read_channel
---

## Step 0: Set up cron (once per session only)

Call `CronList`. If no job contains the word `heartbeat`, call `CronCreate`:
- `cron`: `*/10 * * * *` (default 10m — adaptive interval will switch based on context)
- `recurring`: `true`
- `prompt`: `Read and follow skills/heartbeat/SKILL.md.`

After creating the cron, save the job ID to `state/heartbeat-state.json` as `cron_job_id` and set `active_preset: "10m"`.

Create the cron silently — print nothing unless an error occurs.

## Step 1+: Run heartbeat

Read and follow `skills/heartbeat/SKILL.md`.
