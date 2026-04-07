### Inbox

> Config: `inbox.*` keys. No external dependencies.

#### Capabilities

**check:**
Use Glob/Read tools directly — no CLI needed:
```
Glob("$(kvido config 'inbox.path' "$KVIDO_HOME/inbox")/*")
```
Lists files waiting for ingest processing. If files found, set state for planner:
```bash
kvido state set gatherer.inbox_pending "$(date -Iseconds)"
```
If no files, delete the key: `kvido state delete gatherer.inbox_pending`.

**triage-detect:** Each file is a pending ingest item. Gatherer returns one finding per file with urgency `normal`.

**health:** Directory exists and is writable.

#### Schedule
- morning: check
- heartbeat: check
- heartbeat-maintenance: skip
- eod: skip

#### Setup
| Prerequisite | Check |
|---|---|
| inbox directory | `test -d "$(kvido config 'inbox.path' "$KVIDO_HOME/inbox")"` |

#### Dedup Keys
- `inbox:<filename>:<mtime>` — file processed once per modification time
