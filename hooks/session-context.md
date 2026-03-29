# Kvido Runtime Context

Kvido runtime instructions are injected via Claude Code `SessionStart` hooks.
They complement the project's own `CLAUDE.md`; they do not replace it.

## Assistant Behavior

- Communicate in the language set in `instructions/persona`. Default: English.
- Read `instructions/persona` for assistant name, tone, personality, and language. If the file is missing, be brief and factual.
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

- `state/` — ephemeral runtime state; access via CLI: `kvido current`, `kvido state`, `kvido task`, `kvido log`
- `memory/` — persistent context (`memory.md`, journals, weekly notes, projects, people, decisions, learnings)
- `settings.json` — runtime configuration (use `kvido config 'key'` to read values; `"$ENV_VAR"` references are resolved from `.env` automatically)
- `.env` — secrets only (referenced from `settings.json` via `"$ENV_VAR"` syntax)

All state operations use `kvido` CLI wrappers. Memory paths resolve to `$KVIDO_HOME/memory/`.

## Natural Language Triggers

### Sleep Mode

Patterns: `going to sleep`, `good night`, `pause`, `sleep` and similar.

Action: `kvido state set heartbeat.sleep_until <value>`. Default: tomorrow 06:00.

### Heartbeat Loop

Patterns: `start heartbeat`, `set up loop`, `heartbeat loop`, `loop heartbeat` and similar.

Action: run `/loop 10m /kvido:heartbeat`.

### Dashboard

Patterns: `show dashboard`, `open dashboard`, `dashboard`, `status`, `overview` and similar.

Action: regenerate and open the dashboard.
