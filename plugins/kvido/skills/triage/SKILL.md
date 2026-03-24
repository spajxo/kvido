---
name: triage
description: Use when processing untriaged items (`kvido task list triage`) or enforcing WIP limits.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
---

> **Configuration:** WIP limit and thresholds from `settings.json` → `skills.triage` (via `kvido config`). Defaults: wip_limit=3, triage_overflow_threshold=10.

# Triage & Backlog

## Tone Guidelines

Tone and style per `memory/persona.md` (Triage section). If persona does not exist, be concise and factual.

## Interactive triage

Load the list of tasks in triage:

```bash
kvido task list triage
```

If no tasks: "Triage inbox is empty ✓" and stop.

For each task display:

```bash
# For each slug from the listing:
kvido task read <slug>
```

```
📥 [N/total] <slug>: <title>
  priority: <priority> | size: <size> | added: <created_at>
  → [yes / later / no]
```

Wait for a response. Then:
- `yes` → approve and move to todo: `kvido task move <slug> todo`
- `later` → add a note: `kvido task note <slug> "deferred: YYYY-MM-DD"`, leave in triage
- `no` → cancel: `kvido task note <slug> "Rejected by user" && kvido task move <slug> cancelled`

After processing all: "Triage done: X accepted, Y deferred, Z discarded."

## WIP Limit

Worker automatically enforces the WIP limit for in-progress tasks.

Get current WIP:
```bash
kvido task count in-progress
```
If >= 3: "WIP limit of 3 reached. What should be paused or completed?"

Tasks with "waiting_on" in frontmatter do not count toward the limit — check via `kvido task read <slug>` and filter those with a non-empty WAITING_ON.
