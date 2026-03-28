# Agent Output Contract

This document formally specifies what heartbeat expects from each agent, how it parses agent output, and what fallback behavior applies. All agents must conform to this contract.

---

## Core Principle

Agents communicate exclusively via NL stdout output. Heartbeat collects this output, parses it, and handles all Slack delivery. No agent calls `kvido slack` directly.

---

## 1. Planner Output Format

The planner outputs structured lines that heartbeat parses one by one. Only these line types are valid:

### DISPATCH

```
DISPATCH <agent>
DISPATCH worker <slug>
```

- `DISPATCH <agent>` — heartbeat dispatches the named agent in background (`run_in_background: true`).
- `DISPATCH worker <slug>` — heartbeat reads task `<slug>`, moves it to `in-progress`, then dispatches the worker.
- One dispatch per line.
- Multiple `DISPATCH` lines are processed in parallel by default.

### DISPATCH_AFTER

```
DISPATCH_AFTER <agent> <after-agent>
```

- Heartbeat sets `addBlockedBy` so `<agent>` waits for `<after-agent>` to complete before being dispatched.
- Example: `DISPATCH_AFTER triager gatherer` — triager runs after gatherer finishes.

### NOTIFY

```
NOTIFY <type> [detail]
```

- Heartbeat handles the notification directly without dispatching an agent.
- Known types and their behavior:

| Type | Detail | Heartbeat action |
|------|--------|-----------------|
| `stale-worker` | `<slug>` | Slack notification that a worker task has been in-progress > 10 min |
| `triage-overflow` | — | Slack notification that triage queue >= 10 items |
| `backlog-stale` | — | Slack notification that a low-priority todo task is > 30 days old |

### No dispatches

```
No dispatches needed.
```

- Heartbeat skips Steps 5 and 6 for planner-originated dispatches, but still processes `pending` chat tasks and completed background agents.

### Fallback

If the planner returns no recognized lines, heartbeat treats it as "No dispatches needed." and logs the raw output for debugging.

---

## 2. Agent Output Format

Each agent type has a defined NL output structure. Heartbeat parses these outputs to determine Slack template, delivery level, and routing.

### 2.1 Gatherer

**Purpose:** Reports new findings from configured data sources (GitLab, Jira, Slack, Calendar, Gmail, sessions).

**Format:**

```
## Gatherer Results

**Sources fetched:** <N> ok, <N> failed, <N> disabled

### Findings

- [<urgency>] <source>: <description with context>
  URL: <full clickable URL>

### Errors

- <source>: <error description>

### Summary

<1-2 sentence summary>
```

**Urgency values:**

| Value | When |
|-------|------|
| `immediate` | Meeting in < 15 min, review requested, blocking issue, direct message |
| `normal` | New MR, assigned issue, email from priority sender |
| `low` | Status changes, FYI updates, routine notifications |

**Delivery:** Heartbeat classifies each finding and delivers via `event` template. Multiple findings in a single cycle → digest threading.

**Fallback:** If gatherer returns `Gatherer: no sources enabled`, heartbeat logs and skips delivery.

---

### 2.2 Triager

**Purpose:** Reports triage lifecycle transitions and items needing user attention.

**Format (transitions present):**

```
Triage update: "<slug>" approved (moved to todo), "<slug>" rejected (cancelled).
```

**Format (notifications needed):**

```
Pending triage — please react in Slack to approve or reject:

1. <slug> (waiting <duration>) — <description>. <URL>
2. <slug> (waiting <duration>) — <description>.
```

**Format (nothing to do):**

```
Triager: no triage items pending
```

**Delivery:** Heartbeat uses `triage-item` template, `immediate` level. After delivery, heartbeat saves the returned Slack `ts` to the task frontmatter via `kvido task update <slug> triage_ts <ts>`.

> **Note:** `heartbeat.md` currently references `triage_slack_ts` instead of `triage_ts`. These need to be aligned — triager reads `triage_ts`.

**Fallback:** `Triager: no triage items pending` → heartbeat skips delivery.

---

### 2.3 Worker

**Purpose:** Reports the result of executing a task.

**Format:**

The worker writes a free-form natural language message in the tone from `persona.md` (Heartbeat section), followed by routing fields:

```
<free-form result message>

Task: #<task_id>
Type: worker-report
Source: <source_ref>
```

The free-form message contains the substance — what was done, findings, branch name, etc. Tone and structure are controlled by persona, not by this contract.

**Routing fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `Task:` | yes | Numeric task ID — used for routing and logging |
| `Type:` | yes | Always `worker-report` |
| `Source:` | if non-empty | Original source ref (Slack `ts`, Jira key, etc.) — used for thread routing |

**Delivery:** Heartbeat uses `worker-report` template with `--var message="<full output above routing fields>"`. Level is `normal` on success, `high` on failure (detected by context — e.g. "failed" or absence of substantive result). If `Source:` contains a Slack `ts`, heartbeat replies in that thread.

**Slack appearance** (what heartbeat renders): the free-form message as-is in mrkdwn, plus context footer with task ID and duration.

**Fallback:** If `Type:` field is missing, heartbeat treats the output as `worker-report` and delivers as-is with `normal` level.
---

### 2.4 Chat-agent

**Purpose:** Responds to non-trivial Slack DM messages from the owner.

**Format:**

```
Reply: <response text>
Thread: <thread_ts or empty>
Type: chat-reply
```

The `Reply:` value is free-form text written in the tone from `persona.md`. Heartbeat delivers it as-is.

**Parsed fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `Reply:` | yes | The response text — free-form, per persona tone |
| `Thread:` | yes | If replying to a thread: the parent message `thread_ts`. If flat message: empty string. **Never `ts` of the message itself.** |
| `Type:` | yes | Always `chat-reply` |

**Delivery:** Heartbeat uses `chat` template, `immediate` level. If `Thread:` is non-empty, heartbeat replies in that thread; otherwise replies under the original message (`ts` from task subject `chat:<ts>`).

**Lifecycle:** After delivery, heartbeat removes `:eyes:` reaction and checks for next pending `chat:*` task.

**Fallback:** If `Type: chat-reply` is missing, heartbeat attempts to extract `Reply:` and deliver directly under the original message.

---

### 2.5 Maintenance agents (librarian, project-enricher, self-improver, scout)

Maintenance agents return a brief summary line. Heartbeat delivers via the `maintenance` template, falling back to `event` template if `maintenance` is not found.

#### Librarian

```
Librarian: consolidated memory. Archived: <N> journals, <N> decisions. Index updated.
```

Or if nothing needed:

```
Librarian: no cleanup needed.
```

#### Project-enricher

```
Enriched: <project> — <what changed>
```

Or:

```
Enriched: <project> — no changes
```

#### Self-improver

```
Outcome review: X% acceptance (Y/Z in 7d). Local: N tasks (<categories>). Plugin: M GitHub issues. Skill drafts: K. Adaptive limit: L.
```

Or if no proposals:

```
Outcome review: X% acceptance. No proposals.
```

#### Scout

```
Scout: checked 3 topics. New findings: "<topic>" (triage task created). No changes: "<topic>", "<topic>".
```

Or:

```
Scout: no topics due for checking.
```

**Delivery:** Heartbeat uses `maintenance` template. If the template does not exist, falls back to `event` with `--var severity_bar=:large_yellow_circle:`.

**Fallback:** Any non-empty output from a maintenance agent triggers delivery. Empty output → no delivery.

---

## 3. Usage Tag

Every agent output may include a `<usage>` XML-style tag (appended by the Claude Code runtime). Heartbeat parses this to log token and duration data.

**Format:**

```
<usage>
total_tokens: N
duration_ms: N
</usage>
```

**Where heartbeat reads it:**

- After planner completes (foreground): `kvido log add heartbeat dispatch --message "planner" --tokens N --duration_ms N`
- After each background agent completes: `kvido log add <type> execute --tokens N --duration_ms N --message "<summary>"`

**Fallback:** If the `<usage>` tag is missing or malformed, heartbeat logs without token/duration data (the fields are omitted from the log entry).

---

## 4. Parsing Rules

### Line-by-line (planner only)

Heartbeat parses planner output line by line. Each recognized prefix (`DISPATCH`, `DISPATCH_AFTER`, `NOTIFY`) triggers the corresponding action. Unrecognized lines are ignored.

### Field extraction (worker, chat-agent)

Heartbeat scans for `Key: value` patterns. Fields are case-sensitive. Unknown fields are ignored.

### Block extraction (gatherer)

Heartbeat reads the full NL block and applies urgency classification per finding line.

### Markers (heartbeat.sh output only)

`CHAT_MESSAGES_START` / `CHAT_MESSAGES_END` delimit the Slack message block. This is not agent output — it is the bash heartbeat script output consumed by the heartbeat command.

---

## 5. Invariants

These invariants hold across all agents:

1. **No Slack calls.** Agents never call `kvido slack send|reply|edit`. Heartbeat owns all delivery.
2. **stdout only.** All output goes to stdout. Errors go to stderr (logged, not delivered).
3. **Idempotent output.** Agents may be re-run; heartbeat uses state dedup (`kvido state`) to avoid duplicate deliveries.
4. **Empty output is valid.** An agent returning nothing means nothing to deliver. Heartbeat does not treat silence as an error.
5. **Usage tag is optional.** Agents should not emit it manually — it is appended by the runtime.

---

## 6. Delivery Mapping

| Agent | Template | Default level | Thread routing |
|-------|----------|--------------|----------------|
| gatherer | `event` | per urgency suggestion | standalone or digest |
| triager | `triage-item` | `immediate` | standalone |
| worker | `worker-report` | `normal` (success) / `high` (failure) | source thread if `Source:` is set |
| chat-agent | `chat` | `immediate` | `Thread:` field |
| librarian | `maintenance` → fallback `event` | per delivery rules | standalone |
| project-enricher | `maintenance` → fallback `event` | per delivery rules | standalone |
| self-improver | `maintenance` → fallback `event` | per delivery rules | standalone |
| scout | `maintenance` → fallback `event` | per delivery rules | standalone |
