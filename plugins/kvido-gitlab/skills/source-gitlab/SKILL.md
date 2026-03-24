---
name: source-gitlab
description: Use when fetching git activity, MR status, or detecting new MRs from configured GitLab repos.
allowed-tools: Read, Bash
user-invocable: false
---

> **Configuration:** Via `kvido config` (`sources.gitlab.*` keys).

**Language:** Communicate in the language set in memory/persona.md. Default: English.

# Source: GitLab

## Capabilities

### fetch-activity
```bash
skills/source-gitlab/fetch-activity.sh YYYY-MM-DD [--priority high]
```
`--priority high` filters only repos with `priority: high` (for quick heartbeat).

### fetch-mrs
```bash
skills/source-gitlab/fetch-mrs.sh [--priority high]
```
Repos with `type: knowledge-base` are always skipped (no MRs).

### watch
Run fetch-activity + fetch-mrs. Compare with previous state.

### triage-detect
New MR where I am reviewer, not in backlog → triage item:
`- [ ] Review MR !IID: title (repo) #source:gitlab #added:YYYY-MM-DD #ref:repo!IID`

### health
For each repo via `kvido config --keys 'sources.gitlab.repos'`:
```bash
test -d <path>/.git && echo "OK: <name>" || echo "FAIL: <name>"
```
Plus: `glab auth status 2>/dev/null`

## Schedule
- morning: fetch-activity (yesterday) + fetch-mrs
- heartbeat-quick: fetch-activity (today) + fetch-mrs --priority high
- heartbeat-full: fetch-activity + fetch-mrs (all)
- heartbeat-maintenance: health
- eod: fetch-activity (today)
