---
name: gatherer
description: Discovers source plugins, fetches data, detects changes via event bus.
allowed-tools: Read, Glob, Grep, Bash
user-invocable: false
---

# Gatherer

Discovers installed source plugins, runs their fetch scripts, and emits events for fetched data and detected changes. Does NOT decide urgency, does NOT notify the user.

---

## Step 1: Discover Sources

```bash
kvido discover-sources
```

Output: one line per installed source — `name<TAB>install_path`. If empty, exit with brief status.

---

## Step 2: Fetch Data

For each discovered source plugin, read its `skills/source-*/SKILL.md` from the `install_path` and follow its fetch instructions.

### Fetch execution

For each source:
1. Run the fetch command as documented in the source SKILL.md
2. Capture stdout, stderr, and exit code

### Fetch result handling

- **Exit code 0** — success. Parse output. Emit:
  ```bash
  kvido event emit source.fetched \
    --data '{"source":"<name>","items_count":<N>,"summary":"<brief>"}' \
    --producer gatherer
  ```

- **Exit code 10** — CLI tool not available. Follow MCP fallback instructions in the source SKILL.md. This is NOT an error.

- **Any other non-zero exit code** — fetch failure. Emit:
  ```bash
  kvido event emit source.error \
    --data '{"source":"<name>","error":"<stderr>","exit_code":<N>}' \
    --producer gatherer
  ```
  Log: `kvido log add gatherer error --message "fetch failed: <name>: <stderr>"`
  Continue processing remaining sources.

---

## Step 3: Change Detection

For each successfully fetched source, compare items against previously reported events. For each new or changed item:

```bash
kvido event emit change.detected \
  --data '{"source":"<name>","ref":"<ref>","title":"<title>","kind":"<kind>","url":"<url>","dedup_key":"<key>"}' \
  --producer gatherer \
  --dedup-key "<key>" \
  --dedup-window 72h
```

### Kind values

| Kind | When |
|------|------|
| `mr_new` | New merge request |
| `mr_updated` | MR status change, new commits |
| `mr_review_requested` | Review requested for me |
| `issue_assigned` | Issue assigned to me |
| `email_received` | New email from priority sender |
| `calendar_event` | Upcoming meeting (< 15min) |
| `slack_mention` | Mentioned in watched channel |

### Dedup keys

Format: `<type>:<identifier>` — e.g., `mr:project!123`, `issue:PROJ-456`, `email:<message-id>`

The `--dedup-key` + `--dedup-window 72h` ensures the same change is not reported twice within 72 hours.

---

## Step 4: Dispatch Notifier

After all sources are fetched and change events emitted, dispatch the notifier so it can process the new data:

```bash
kvido event emit dispatch.notify --data '{"reason":"post-gather"}' --producer gatherer
```

---

## Step 5: Save State

```bash
kvido state set gatherer.last_run "$(date -Iseconds)"
```

---

## Output Format

Brief status line for logging:

```
Gatherer: fetched 4 sources, 2 changes detected, 1 error (kvido-gmail)
```

---

## Critical Rules

- **No urgency decisions.** Emit raw `change.detected` events — notifier decides urgency.
- **No user communication.** No Slack, no formatting.
- **Dedup via event bus.** Always use `--dedup-key` on change events.
- **Continue on failure.** One source failing must not abort other fetches.
- **Exit 10 = MCP fallback, not error.** Follow source SKILL.md instructions.
