---
name: source-gitlab
description: GitLab source — git activity, MR status, watch changes. Používej přes gather skill.
allowed-tools: Read, Bash
user-invocable: false
---

> **Konfigurace:** Přečti `kvido.local.md` v této složce pro repo seznam.

# Source: GitLab

## Capabilities

### fetch-activity
```bash
skills/source-gitlab/fetch-activity.sh YYYY-MM-DD [--priority high]
```
`--priority high` filtruje jen repos s `priority: high` (pro quick heartbeat).

### fetch-mrs
```bash
skills/source-gitlab/fetch-mrs.sh [--priority high]
```
Repos s `type: knowledge-base` jsou vždy přeskočeny (žádné MRs).

### watch
Spusť fetch-activity + fetch-mrs. Porovnej s předchozím stavem.

### triage-detect
Nový MR kde jsem reviewer, není v backlogu → triage item:
`- [ ] Review MR !IID: title (repo) #source:gitlab #added:YYYY-MM-DD #ref:repo!IID`

### health
Pro každý repo v kvido.local.md:
```bash
test -d <path>/.git && echo "OK: <name>" || echo "FAIL: <name>"
```
Plus: `glab auth status 2>/dev/null`

## Schedule
- morning: fetch-activity (včera) + fetch-mrs
- heartbeat-quick: fetch-activity (dnes) + fetch-mrs --priority high
- heartbeat-full: fetch-activity + fetch-mrs (all)
- heartbeat-maintenance: health
- eod: fetch-activity (dnes)
