# Kvido Plugin Release Polish — Design Spec

**Date:** 2026-03-21
**Status:** Approved
**Goal:** Make the kvido plugin ready for public release on GitHub.

## Context

Kvido is a Claude Code plugin — a resident AI workflow assistant that monitors Jira, GitLab, Slack, Calendar, and Gmail, communicating via Slack DM. The plugin lives at `github.com/spajxo/kvido` and is installed via `claude plugin install kvido --scope local`.

The plugin is functionally complete (v0.1.0). This spec covers the polish needed for public release: language consistency, documentation, i18n support, and end-to-end functional validation.

## Decision: Language Strategy

- **All code, docs, README, CLAUDE.md, SKILL.md, agent definitions** — English.
- **Runtime language** (how Kvido talks to the user) — configurable via `memory/persona.md`, field `language`. Default: `en`.
- **Approach (b):** No template-based i18n. English defaults in all prompts. LLM generates output in the persona's language naturally. Hardcoded Czech strings in SKILL.md become English defaults with a `"Use the language defined in memory/persona.md"` instruction.
- **Slack templates** remain language-neutral (emoji + structured data). Text fields are populated by the LLM in the persona's language.

## Phase 1: Language & Sanitization

### 1.1 All SKILL.md files

- Translate frontmatter (name, description) to English
- Translate prompt text to English
- Add language directive: `"Communicate in the language set in memory/persona.md. Default: English."`
- Remove hardcoded Czech inline strings (e.g. "Ještě pracuju na předchozím úkolu") — replace with English defaults that the LLM will localize via persona

### 1.2 Agent definitions (agents/*.md)

- Translate description, prompt templates to English
- Add persona language directive to each agent's prompt section

### 1.3 Commands (commands/*.md)

- Translate to English
- **High priority: `commands/setup.md`** — longest command, first thing new users run, heavily Czech

### 1.4 CLAUDE.md (plugin instructions)

- Full rewrite in English
- Keep architecture section, update to reflect current state
- Add language convention note

### 1.5 CLAUDE.md.template (user's project CLAUDE.md)

- **High priority** — first thing users see after `/setup`, currently 100% Czech
- Full rewrite in English
- Minimal — core behavior triggers only (morning, eod, sleep, heartbeat, dashboard)
- Note that runtime language follows persona.md

### 1.6 kvido.local.md.example

- Translate all comments to English
- Add description for each config section

### 1.7 Bash scripts

- Translate comments to English
- Hardcoded Czech error messages / log strings → English
- `slack.sh` inline messages → English defaults
- **Note:** Czech transliteration in `task.sh` slug generation (line 28-29) is intentional — keep it, it handles international characters gracefully

### 1.8 Slack templates (skills/slack/templates/*.json)

- Audit for hardcoded Czech text in template structure
- Labels/headers → English (LLM-generated content stays persona-driven)

### 1.9 hooks/

- Translate hooks.json descriptions and pre-compact.sh comments to English

## Phase 2: Documentation

### 2.1 README.md

Full rewrite:
- **Pitch:** What Kvido is, who it's for, what it solves (3-4 sentences)
- **Features:** Heartbeat, Planner, Worker, Morning/EOD, Chat (bullet list)
- **Prerequisites:** Table (jq required, glab/acli/gws optional)
- **Installation:** 4 steps (mkdir workspace, plugin install, claude, /setup)
- **Daily usage:** Natural language triggers (morning, heartbeat, eod, sleep)
- **Configuration:** kvido.local.md (sources), .env (Slack tokens), persona.md (personality/language)
- **Structure:** Directory tree for both plugin and user workspace
- **How it works:** Brief architecture (heartbeat loop → planner → worker → chat-agent)
- **Status:** Version, known limitations

### 2.2 plugin.json

- Add `license: "MIT"` (or appropriate)
- Add `keywords: ["assistant", "workflow", "heartbeat", "planner"]`

### 2.3 LICENSE

- Verify LICENSE file exists and matches plugin.json

## Phase 3: /setup & Persona Onboarding

### 3.1 /setup language question

During first-time setup (Step 1b — persona setup), ask:
- "What language should Kvido use? (default: en)" → store in persona.md as `language: <code>`
- "What's your assistant's name? What tone/personality?" → existing flow, but in English

### 3.2 /setup idempotence

- Verify running `/setup` twice doesn't break anything
- Existing files should not be overwritten

## Phase 4: Functional Validation

### 4.1 Clean install test

1. Create `~/kvido-test/`, `git init`
2. Install plugin: `claude plugin install kvido --scope local`
3. Run `/setup` — verify all directories, files, config templates created
4. Fill in .env with test Slack tokens
5. Run `/morning` — verify briefing works
6. Run `/heartbeat` — verify cron starts, planner dispatches
7. Send Slack DM — verify chat-agent responds
8. Verify `config.sh` path resolution works from user workspace (plugin lives in `~/.claude/plugins/cache/`, config in workspace)

### 4.2 Graceful degradation

Test with missing optional tools:
- No `glab` → GitLab sources skip gracefully, no crash
- No `acli` → Jira sources skip gracefully
- No `gws` → Calendar/Gmail sources skip gracefully
- Empty `.env` → Slack disabled, heartbeat still runs, clear error message
- No configured sources in kvido.local.md → runs but reports nothing
- No `memory/persona.md` → falls back to English, no crash

### 4.3 Repeated /setup

- Run `/setup` on already-configured workspace → health check only, no overwrites

## Out of Scope

- Multi-language template system (decided against — approach b)
- Test suite (no traditional tests — validate via /setup health check)
- CI/CD pipeline
- npm/pip packaging — plugin uses git clone
