# State Directory Cleanup Mechanism

**Issue:** [#102](https://github.com/spajxo/kvido/issues/102)
**Date:** 2026-03-25

---

## Problem

Files in `state/` accumulate over time with no cleanup mechanism. Old research files, orphaned temp outputs, and stale ad-hoc files stay indefinitely alongside live runtime state. There is no distinction between ephemeral scratch files and permanent runtime state.

Examples of accumulation observed in `~/.config/kvido/state/`:
- `claude-features-audit.md` — 2 days old, one-off research
- `kvido-timeline-presentation.md` — 1 day old, one-off output
- `marketplace-research.md` — 2 days old, one-off research
- `test-git-summary.txt`, `test-output.txt` — stale test artifacts

**Constraint from issue:** never auto-delete — always require user confirmation.

---

## Design

### Two-phase approach

**Phase 1 — Detection (planner):** Planner scans `state/` for candidate files older than a configurable threshold and surfaces them as triage items. The user approves or rejects each batch.

**Phase 2 — Execution (worker):** A worker task carries out the approved deletions.

### What is a candidate file?

A file is a cleanup candidate when ALL of the following are true:

1. It is **not** a known runtime file (allowlist below)
2. Its `mtime` is older than the configured threshold (default: 7 days)
3. It is a plain file (not a directory, not a lock file)

**Allowlist — files that are never candidates:**

```
current.md
dashboard.html
heartbeat-state.json
heartbeat-state.json.lock
log.jsonl
planner-state.json
planner-state.json.lock
planner-state.md
session-context.md
source-health.json
task_counter
today.md
```

**Allowlist — directories that are never touched:**

```
tasks/
kvido-plugin/
plugin-proposals/
```

All other plain files in `state/` are eligible for cleanup after the threshold.

### Configuration

Two new keys in `settings.json`:

```json
"skills": {
  "cleanup": {
    "state_max_age_days": 7,
    "enabled": true
  }
}
```

Default: 7 days, enabled. If `enabled` is false, planner skips the scan entirely.

### Planner integration (detection)

Add a maintenance rule to `context-planner.md`. The planner runs the scan at most once per day (tracked via `kvido planner-state timestamp get last_state_cleanup_scan_date`).

When triggered, the planner runs `skills/cleanup/scan-state.sh`, reads its output (list of candidate files with age and size), and creates a single triage task:

```bash
kvido task create \
  --instruction "Delete stale state files: <file1>, <file2>, ..." \
  --size s \
  --priority low \
  --source planner
```

The task body lists each candidate with its age and size so the user can make an informed decision when approving.

The planner records: `kvido planner-state timestamp set last_state_cleanup_scan_date "$(date -Iseconds)"`.

If no candidates are found, the planner logs it and skips task creation.

### Scan script

New file: `plugins/kvido/skills/cleanup/scan-state.sh`

Responsibilities:
1. Read config values via `kvido config 'skills.cleanup.state_max_age_days'` and `kvido config 'skills.cleanup.enabled'`
2. Exit 0 with no output if `enabled` is false
3. List `$KVIDO_HOME/state/` (top-level only, non-recursive)
4. Filter against allowlist (files and directories)
5. Check `mtime` via `stat --format=%Y` and compare against threshold
6. Output one line per candidate: `<path>\t<age_days>d\t<size>`

No deletion happens in this script — it only scans and reports.

### Worker execution

When the user approves the triage task, the worker receives the instruction and runs `skills/cleanup/delete-state-files.sh <file1> <file2> ...`.

New file: `plugins/kvido/skills/cleanup/delete-state-files.sh`

Responsibilities:
1. Validate each file is inside `$KVIDO_HOME/state/` (safety guard)
2. Validate each file is not in the allowlist (double-check)
3. Delete each file and log: `kvido log add cleanup delete --message "Deleted state file: <path>"`
4. Print a summary of what was deleted

---

## Affected files

| File | Change |
|------|--------|
| `plugins/kvido/skills/cleanup/scan-state.sh` | New — scanning logic |
| `plugins/kvido/skills/cleanup/delete-state-files.sh` | New — deletion with safety guards |
| `plugins/kvido/hooks/context-planner.md` | Add cleanup maintenance row to the maintenance table |
| `plugins/kvido/settings.json.example` | Add `skills.cleanup` config section with defaults |

No changes to `heartbeat.sh`, `planner.md`, or the task system — this fits into the existing planner maintenance dispatch pattern using standard `kvido task create` (user approval required, not a `Dispatch:` agent).

---

## What doesn't change

- Task system, heartbeat, worker agent — no changes
- Memory directory (`memory/`) — out of scope; librarian handles memory cleanup separately
- Log file (`log.jsonl`) — managed by `kvido log purge`; out of scope

---

## Acceptance criteria

- [ ] `scan-state.sh` correctly identifies stale non-allowlisted files
- [ ] `scan-state.sh` never flags allowlisted files or task directories
- [ ] Planner creates a triage task when candidates exist (at most once per day)
- [ ] Triage task body lists all candidates with age and size
- [ ] Worker deletes only files explicitly listed in the approved task instruction
- [ ] `delete-state-files.sh` rejects paths outside `$KVIDO_HOME/state/`
- [ ] `delete-state-files.sh` rejects allowlisted paths even if passed explicitly
- [ ] Config `enabled: false` disables the scan entirely with no side effects
- [ ] All deletions logged via `kvido log add cleanup delete`
