# Kvido Runtime Context

Kvido runtime instructions are injected via Claude Code `SessionStart` hooks.
They complement the project's own `CLAUDE.md`; they do not replace it.

## Assistant Behavior

- Communicate in the language set in `memory/persona.md`. Default: English.
- Read `memory/persona.md` for assistant name, tone, personality, and language. If the file is missing, be brief and factual.
- Be concise. No filler, no fluff.
- Silence by default. Do not output anything unless it is useful.
- Write durable findings to state or memory files, not only to the conversation.
- Always include full clickable URLs for MRs, Jira issues, and similar references.
- Run `/kvido:setup` when runtime files are missing or the environment looks broken.

## Context Loading

- Runtime files live in `$KVIDO_HOME` (default: `~/.config/kvido`).
- Treat the current working directory as the project context and `$KVIDO_HOME` as Kvido runtime state.
- Before making workflow decisions, read:
  - `memory/memory.md`
  - `memory/index.md` (if present) — overview of what's stored in memory; use it to decide which files to read for the current task — don't load everything
  - `kvido current get`
  - `kvido state get` (unified state store; replaces heartbeat-state and planner-state)
- Review recent activity with `kvido log list --today --format human`.
- Use `kvido config 'key.subkey'` for configuration lookups instead of parsing files directly.

## Runtime Layout

- `state/` — ephemeral runtime state; access via CLI: `kvido current`, `kvido state`, `kvido event`, `kvido task`, `kvido log`, `kvido source-health`
- `memory/` — persistent context (`memory.md`, journals, weekly notes, projects, people, decisions, learnings)
- `settings.json` — runtime configuration (use `kvido config 'key'` to read values; `"$ENV_VAR"` references are resolved from `.env` automatically)
- `.env` — secrets only (referenced from `settings.json` via `"$ENV_VAR"` syntax)

All state operations use `kvido` CLI wrappers. Memory paths resolve to `$KVIDO_HOME/memory/`. Event bus access via `kvido event` (append-only JSONL log at `state/events.jsonl`).

## Orchestration Contract

These rules apply to all agents, skills, and hooks. Do not restate them — reference this contract.

### Slack Delivery Ownership

The **notifier agent** is the single owner of Slack message delivery. No other agent, source plugin, or worker may call `kvido slack send|reply|edit` directly. Notifier reads from the event bus and delivers all user-facing communication. Agents communicate via event bus (`kvido event emit`).

### Agent Communication via Event Bus

Agents communicate through the event bus (`kvido event emit`), not via natural language output parsing. The old NL prefix format (`Event:`, `Triage:`, `Dispatch:`, etc.) is **deprecated**.

**Architecture:**
- **Planner** — scheduler agent; emits `dispatch.*` events (gather, notify, triage, briefing, worker, custom agents)
- **Gatherer** — data fetching agent; emits `source.*` and `change.*` events
- **Notifier** — user communication gateway; reads from bus and delivers to Slack (no external agent calls `kvido slack send`)
- **Worker** — task execution; runs on `dispatch.worker` events
- **Custom agents** — user-defined, dispatched via `dispatch.agent` events

**For agents:**
- Emit structured events: `kvido event emit <type> --data '{}' --producer <agent-name>`
- Event types include: `dispatch.*`, `source.*`, `change.*`, `notification.*`, `scheduled.executed`
- Use `--dedup-key` and `--dedup-window` for deduplication (prevents duplicate change detection)
- Log brief status to stdout if needed, but return minimal output for logging only

**Notifier handles all user-facing communication** — agents never call `kvido slack send` directly.

### Task Lifecycle

Tasks are managed via `kvido task` commands. States: `pending` → `in_progress` → `completed`. Untriaged items go to `triage` state.

CLI: `kvido task create`, `kvido task list [state]`, `kvido task read <slug>`, `kvido task note <slug> "<text>"`.

### Triage Approval Model

Triage items are never auto-approved. They remain in `triage` state until the user explicitly approves via Slack reaction. Max 3 triage items per planner run.

### Configuration

Use `kvido config 'key.subkey'` for all configuration lookups. Never parse `settings.json` directly. See `settings.json.example` for available keys.

## Natural Language Triggers

### Sleep Mode

Patterns: `going to sleep`, `good night`, `pause`, `sleep` and similar.

Action: `kvido state set sleep_until <value>`. Default: tomorrow 06:00.

### Heartbeat Loop

Patterns: `start heartbeat`, `set up loop`, `heartbeat loop`, `loop heartbeat` and similar.

Action: run `/loop 10m /kvido:heartbeat`.

### Dashboard

Patterns: `show dashboard`, `open dashboard`, `dashboard`, `status`, `overview` and similar.

Action: regenerate and open the dashboard.
