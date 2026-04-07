### Inbox

> Config: `inbox.*` keys. No external dependencies.

#### Capabilities

**check:**
Use Glob/Read tools directly — no CLI needed:
```
Glob("$KVIDO_HOME/inbox/*")
```
Lists files in `$KVIDO_HOME/inbox/` waiting for ingest processing.

**triage-detect:** Each file is a pending ingest item. Gatherer returns one finding per file with urgency `normal`. Planner dispatches ingest agent per file.

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
