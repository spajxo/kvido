# Agent Dispatch WIP Limits

**Date:** 2026-03-31
**Status:** Design specification

## Overview

This document specifies the implementation of Work-In-Progress (WIP) limits for concurrent agent dispatches in the kvido heartbeat orchestrator. Previously, agents could be dispatched without concurrency limits, leading to scenarios where 8+ agents ran in parallel (as noted in GitHub issue #735).

## Problem Statement

The heartbeat command statement "Max 1 concurrent per group (maintenance, worker, chat)" was aspirational but not enforced in code. Specifically:

- Maintenance agents (e.g., GitLab polling, Jira sync) had no limit, causing multiple instances to run in parallel
- Gatherer agent had no explicit limit, creating resource contention
- No systematic way to configure or monitor concurrent dispatch limits

## Solution

Implement configurable per-group WIP limits that prevent excess concurrent dispatches:

1. **Configuration:** Add `agents.wip_limits` section to `settings.json` with group-specific limits
2. **Enforcement:** Heartbeat Step 5 checks limits before dispatching agents
3. **Queueing:** Excess dispatches create `pending` tasks with `blockedBy` dependencies
4. **Monitoring:** Log all WIP limit events for visibility

## Configuration

Add to `settings.json`:

```json
{
  "agents": {
    "wip_limits": {
      "maintenance": 2,
      "gatherer": 1
    }
  }
}
```

### Default Limits

| Agent Group | Default | Rationale |
|-------------|---------|-----------|
| `maintenance` | 2 | Allows GitLab + Jira polling in parallel without excessive load |
| `gatherer` | 1 | Prevents redundant calendar/email fetches; one active gather per cycle |
| Worker | 3 (via `triage.wip_limit`) | Existing limit, unchanged |
| Chat | 1 | Implicit via single `blockedBy` per task |
| Planner | 1 | Runs foreground, no background concurrency |

Unconfigured groups have unlimited concurrency (no limit).

## Implementation

### Step 5: Dispatch Agents (Heartbeat Command)

Before dispatching an agent, check its group's WIP limit:

```pseudo
For each DISPATCH line from planner output:
  1. Extract agent group and name from DISPATCH line
  2. Read config: agents.wip_limits.<group>
  3. If limit configured:
       current = Count in_progress tasks with subject matching :<group>:*
       if current >= limit:
         Create pending task with blockedBy to in_progress task(s)
         Log skip event
         Continue to next DISPATCH
  4. Create task with subject <group>:<agent-name>
  5. TaskUpdate status in_progress
  6. Dispatch agent (run_in_background: true)
  7. Log dispatch event
```

### Task Subject Naming

When creating tasks for agent groups with WIP limits, use subject format:

```
<group>:<agent-name>
maintenance:gitlab-poll
maintenance:jira-sync
gatherer:calendar-event-sync
```

This enables TaskList filtering to count concurrent instances.

### Helper Function (wip-limits.sh)

Provided in `scripts/heartbeat/wip-limits.sh` for reference. Can be sourced in scripts or used as documentation for the heartbeat.md logic.

### Logging

Log all WIP-related decisions:

```bash
# Dispatch allowed
kvido log add heartbeat dispatch --message "maintenance:gitlab-poll (1/2 WIP)"

# WIP limit reached
kvido log add heartbeat skip --message "maintenance:jira-sync WIP limit reached (2/2)"
```

## Backward Compatibility

- Unconfigured groups (no entry in `agents.wip_limits`) have unlimited concurrency
- Existing worker WIP limit (via `triage.wip_limit`) is independent and unchanged
- Planner foreground execution is unchanged

## Monitoring & Observation

Use `kvido log list --today` to identify WIP limit events:

```bash
kvido log list --today --message "WIP"
```

Dashboard generation can include agent WIP metrics:

```
Agent WIP Status:
  maintenance: 1/2 active
  gatherer: 1/1 active
```

## Future Enhancements

1. **Dynamic limit adjustment** — lower limits during focus mode
2. **Per-agent override** — allow DISPATCH lines to specify urgency/bypass limits
3. **Backpressure notification** — notify user when queues build up due to WIP limits
4. **Aging/timeout** — automatically unblock pending dispatches if parent agent stalls

## References

- GitHub issue #735 — Parallel agent dispatch flooding
- `commands/heartbeat.md` — Step 5: Dispatch Agents
- `settings.json.example` — agents.wip_limits configuration
