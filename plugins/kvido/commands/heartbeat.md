---
description: Heartbeat — orchestrator, chat check, worker dispatch, log, adaptive interval
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronCreate, CronList, CronDelete, mcp__claude_ai_Slack__slack_read_channel
---

## Step 0: Bootstrap kvido CLI (once per session)

Ensure `kvido` CLI is available. Run:

```bash
kvido --root 2>/dev/null || $(jq -r '.plugins | to_entries[] | select(.key | startswith("kvido@")) | .value[0].installPath' ~/.claude/plugins/installed_plugins.json)/kvido --install
```

## Step 1: Set up cron (once per session only)

Call `CronList`. If no job contains the word `heartbeat`, call `CronCreate`:
- `cron`: `*/10 * * * *` (default 10m — adaptive interval will switch based on context)
- `recurring`: `true`
- `prompt`: `/kvido:heartbeat`

After creating the cron, save the job ID to `state/heartbeat-state.json` via `kvido heartbeat-state set cron_job_id "<job_id>"` and `kvido heartbeat-state set active_preset "10m"`.

Create the cron silently — print nothing unless an error occurs.

## Step 2+: Run heartbeat

Follow the heartbeat SKILL.md (loaded via the kvido:heartbeat skill).
