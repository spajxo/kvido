# Kvido Plugin Release Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate the kvido plugin to English, polish documentation, and validate end-to-end for public release.

**Architecture:** All markdown files (skills, agents, commands, docs) are translated to English. Runtime language is configurable via `memory/persona.md` (default: English). Each SKILL.md and agent gets a language directive. Bash script comments translated. No i18n framework — LLM generates output in persona's language.

**Tech Stack:** Markdown, Bash, JSON (Slack templates). No build step, no test suite. Validation via manual `/setup` in clean workspace.

**Spec:** `docs/specs/2026-03-21-release-polish-design.md`

**Working directory:** `/home/spajxo/Projects/github.com/spajxo/kvido`

---

## File Map

### Phase 1: Translation (Czech → English)

| Action | File | Lines | Notes |
|--------|------|-------|-------|
| Rewrite | `CLAUDE.md.template` | 100 | High priority — user's first impression |
| Rewrite | `commands/setup.md` | 163 | High priority — onboarding entry point |
| Translate | `skills/planner/SKILL.md` | 242 | Largest skill |
| Translate | `skills/heartbeat/SKILL.md` | 231 | Core orchestrator |
| Translate | `skills/eod/SKILL.md` | 230 | End-of-day |
| Translate | `skills/worker/SKILL.md` | 192 | Worker queue |
| Translate | `skills/morning/SKILL.md` | 154 | Morning briefing |
| Translate | `skills/slack/SKILL.md` | 131 | Slack transport |
| Translate | `skills/triage/SKILL.md` | 55 | Triage inbox |
| Translate | `skills/source-slack/SKILL.md` | 93 | Source |
| Translate | `skills/source-jira/SKILL.md` | 61 | Source |
| Translate | `skills/source-gitlab/SKILL.md` | 45 | Source |
| Translate | `skills/source-calendar/SKILL.md` | ~30 | Source |
| Translate | `skills/source-gmail/SKILL.md` | 34 | Source |
| Translate | `skills/source-sessions/SKILL.md` | 46 | Source |
| Translate | `skills/interests/SKILL.md` | 54 | Interests monitoring |
| Translate | `skills/daily-questions/SKILL.md` | ~30 | EOD questions |
| Translate | `skills/reviewer/SKILL.md` | ~30 | MR reviewer |
| Translate | `skills/researcher/SKILL.md` | ~20 | Already mostly EN |
| Translate | `agents/self-improver.md` | 211 | Largest agent |
| Translate | `agents/chat-agent.md` | 110 | Chat handler |
| Translate | `agents/worker.md` | 89 | Worker agent |
| Translate | `agents/planner.md` | ~60 | Planner agent |
| Translate | `agents/librarian.md` | 45 | Memory consolidation |
| Translate | `agents/morning.md` | ~40 | Morning agent |
| Translate | `agents/eod.md` | ~40 | EOD agent |
| Translate | `agents/project-enricher.md` | ~30 | Enricher agent |
| Translate | `commands/eod.md` | ~20 | Command wrapper |
| Translate | `commands/morning.md` | ~20 | Command wrapper |
| Translate | `commands/heartbeat.md` | ~20 | Command wrapper |
| Translate | `commands/triage.md` | ~20 | Command wrapper |
| Translate | `skills/heartbeat/heartbeat.sh` | comments | Bash comments |
| Translate | `skills/heartbeat/heartbeat-state.sh` | comments | Bash comments |
| Translate | `hooks/pre-compact.sh` | comments | Hook script |

### Phase 2: Documentation

| Action | File | Notes |
|--------|------|-------|
| Rewrite | `README.md` | Full English rewrite |
| Update | `.claude-plugin/plugin.json` | Add license, keywords |

### Phase 3: Functional validation

Manual testing, no file changes expected.

---

## Language Directive

Every SKILL.md and agent definition must include this near the top:

```
**Language:** Communicate in the language set in `memory/persona.md`. Default: English.
```

---

## Task 1: High-priority user-facing files

**Files:**
- Rewrite: `CLAUDE.md.template`
- Rewrite: `commands/setup.md`

- [ ] **Step 1: Rewrite CLAUDE.md.template to English**

Translate all content to English. Change default persona fallback from Czech to English:
- "Pokud soubor neexistuje, bud strucny a vecny, mluv cesky" → "If persona file doesn't exist, be brief and factual, speak English"
- All trigger patterns: add English equivalents alongside Czech
  - Morning: `good morning`, `hello`, `hi`, `morning`
  - EOD: `done for today`, `eod`, `end of day`, `signing off`
  - Sleep: `going to sleep`, `good night`, `pause`, `sleep`
  - Heartbeat: `start heartbeat`, `heartbeat loop`, `loop heartbeat`
  - Dashboard: `show dashboard`, `dashboard`, `status`, `overview`
- Storage table headers: English
- Env vars table: English
- Add note: "Runtime language follows `memory/persona.md`"

- [ ] **Step 2: Rewrite commands/setup.md to English**

Translate all instructions. Key changes:
- Step 0: "If a required tool is missing, inform the user and offer installation"
- Step 1a: "If files don't exist, create them"
- Step 1b: persona setup question in English: "What language should Kvido use? (default: en)" + "What's your assistant's name? What tone/personality?"
- Step 1b: store `language: en` (or user's choice) in persona.md
- All step descriptions, comments, output messages → English

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md.template commands/setup.md
git commit -m "feat: translate CLAUDE.md.template and setup command to English"
```

---

## Task 2: Core skills — orchestration

**Files:**
- Translate: `skills/heartbeat/SKILL.md`
- Translate: `skills/planner/SKILL.md`
- Translate: `skills/worker/SKILL.md`

- [ ] **Step 1: Translate skills/heartbeat/SKILL.md**

Add language directive after frontmatter. Translate all prompt text, step descriptions, log format examples. Keep code blocks, config keys, and variable names as-is.

- [ ] **Step 2: Translate skills/planner/SKILL.md**

Add language directive. Translate gather instructions, change detection rules, notification format descriptions, dispatch format. Keep structured output format (Event:, Triage:, Dispatch:) as-is since heartbeat parses these.

- [ ] **Step 3: Translate skills/worker/SKILL.md**

Add language directive. Translate task execution instructions, output format, error handling.

- [ ] **Step 4: Commit**

```bash
git add skills/heartbeat/SKILL.md skills/planner/SKILL.md skills/worker/SKILL.md
git commit -m "feat: translate core skills (heartbeat, planner, worker) to English"
```

---

## Task 3: Core skills — daily routines

**Files:**
- Translate: `skills/morning/SKILL.md`
- Translate: `skills/eod/SKILL.md`
- Translate: `skills/daily-questions/SKILL.md`

- [ ] **Step 1: Translate skills/morning/SKILL.md**

Add language directive. Translate briefing structure, section descriptions, example output. Morning greeting examples should be English defaults.

- [ ] **Step 2: Translate skills/eod/SKILL.md**

Add language directive. Translate journal structure, worklog instructions, weekly summary format.

- [ ] **Step 3: Translate skills/daily-questions/SKILL.md**

Add language directive. Translate question templates and instructions.

- [ ] **Step 4: Commit**

```bash
git add skills/morning/SKILL.md skills/eod/SKILL.md skills/daily-questions/SKILL.md
git commit -m "feat: translate daily routine skills (morning, eod, daily-questions) to English"
```

---

## Task 4: Core skills — slack, triage, interests

**Files:**
- Translate: `skills/slack/SKILL.md`
- Translate: `skills/triage/SKILL.md`
- Translate: `skills/interests/SKILL.md`
- Translate: `skills/reviewer/SKILL.md`
- Translate: `skills/researcher/SKILL.md`

- [ ] **Step 1: Translate skills/slack/SKILL.md**

Add language directive. Translate template descriptions, delivery rules, Block Kit formatting guidelines.

- [ ] **Step 2: Translate skills/triage/SKILL.md**

Add language directive. Translate triage flow, approval format, WIP limit instructions.

- [ ] **Step 3: Translate skills/interests/SKILL.md**

Add language directive. Translate topic monitoring instructions.

- [ ] **Step 4: Translate skills/reviewer/SKILL.md and skills/researcher/SKILL.md**

Add language directive. Translate instructions for worker-dispatched research/review tasks.

- [ ] **Step 5: Translate Slack templates with Czech text**

- `skills/slack/templates/eod.json` — translate "odpracovano", "hotovo", "otevreno" labels
- `skills/slack/templates/triage-item.json` — translate "reaguj... schvalit / zamitnout" instructions
- Audit remaining templates (`chat.json`, `event.json`, `maintenance.json`, `morning.json`, `worker-report.json`) — verify they are language-neutral or translate as needed

- [ ] **Step 6: Commit**

```bash
git add skills/slack/SKILL.md skills/triage/SKILL.md skills/interests/SKILL.md \
  skills/reviewer/SKILL.md skills/researcher/SKILL.md skills/slack/templates/*.json
git commit -m "feat: translate support skills and Slack templates to English"
```

---

## Task 5: Source skills

**Files:**
- Translate: `skills/source-slack/SKILL.md`
- Translate: `skills/source-jira/SKILL.md`
- Translate: `skills/source-gitlab/SKILL.md`
- Translate: `skills/source-calendar/SKILL.md`
- Translate: `skills/source-gmail/SKILL.md`
- Translate: `skills/source-sessions/SKILL.md`

- [ ] **Step 1: Translate all 6 source skills**

Add language directive to each. Translate fetch instructions, health check descriptions, output format docs. Keep config key references and bash command examples as-is.

- [ ] **Step 2: Commit**

```bash
git add skills/source-*/SKILL.md
git commit -m "feat: translate source skills to English"
```

---

## Task 6: Agent definitions

**Files:**
- Translate: `agents/self-improver.md` (211 lines — largest)
- Translate: `agents/chat-agent.md` (110 lines)
- Translate: `agents/worker.md` (89 lines)
- Translate: `agents/planner.md`
- Translate: `agents/librarian.md`
- Translate: `agents/morning.md`
- Translate: `agents/eod.md`
- Translate: `agents/project-enricher.md`

- [ ] **Step 1: Translate agents/self-improver.md**

Add language directive. Translate analysis instructions, scoring criteria, output format. Keep structured fields (patterns, proposals) as-is.

- [ ] **Step 2: Translate agents/chat-agent.md**

Add language directive. Translate message handling rules, response format, inline vs dispatch decision tree.

- [ ] **Step 3: Translate agents/worker.md**

Add language directive. Translate task execution instructions, output format (`Result:`, `Task:`, `Type:`).

- [ ] **Step 4: Translate remaining agents (planner, librarian, morning, eod, project-enricher)**

Add language directive to each. Translate prompt templates and output format descriptions.

- [ ] **Step 5: Commit**

```bash
git add agents/*.md
git commit -m "feat: translate all agent definitions to English"
```

---

## Task 7: Command wrappers

**Files:**
- Translate: `commands/eod.md`
- Translate: `commands/morning.md`
- Translate: `commands/heartbeat.md`
- Translate: `commands/triage.md`

- [ ] **Step 1: Translate all 4 command wrappers**

These are thin wrappers — translate description and any Czech instructions.

- [ ] **Step 2: Commit**

```bash
git add commands/*.md
git commit -m "feat: translate command wrappers to English"
```

---

## Task 8: Bash scripts & hooks

**Files:**
- Translate comments: `skills/heartbeat/heartbeat.sh`
- Translate comments: `skills/heartbeat/heartbeat-state.sh`
- Translate comments: `hooks/pre-compact.sh`
- Translate comments: `skills/worker/task.sh` (lines 2, 8-15 — keep Czech transliteration in slug generation intentionally)
- Translate comments: `skills/source-jira/fetch.sh` (lines 5, 31)
- Translate comments: `skills/source-gitlab/fetch-mrs.sh` (lines 5, 83)
- Translate comments: `skills/source-gitlab/fetch-activity.sh` (lines 5, 120)
- Translate output strings: `skills/source-gmail/fetch.sh` (lines 33, 38, 40, 51, 56, 58 — "Inbox: prazdno", "neprectench", "Predmet:", "Nahled:")
- Translate output strings: `skills/source-calendar/fetch.sh` (lines 30, 34, 42, 64, 83 — "Kalendar", "zadne udalosti", "cely den")
- Normalize title: `skills/heartbeat/generate-dashboard.sh` (lines 211, 341 — "Kvido" without diacritic)
- Note: `config.sh`, `slack.sh`, `triage-poll.sh` are already English (audited)

- [ ] **Step 1: Translate bash comments in heartbeat.sh and heartbeat-state.sh**

Translate Czech comments to English. Keep code logic unchanged.

- [ ] **Step 2: Translate hooks/pre-compact.sh comments**

- [ ] **Step 3: Translate comments in task.sh, source fetch scripts**

Translate Czech comments in `task.sh`, `fetch.sh` (jira), `fetch-mrs.sh`, `fetch-activity.sh`. Keep Czech transliteration in task.sh slug generation (intentional for international character support).

- [ ] **Step 4: Translate output strings in source-gmail/fetch.sh and source-calendar/fetch.sh**

These produce user-visible output — translate Czech strings to English defaults.

- [ ] **Step 5: Normalize dashboard title in generate-dashboard.sh**

Ensure "Kvido" is spelled consistently (no diacritics) in HTML output.

- [ ] **Step 6: Commit**

```bash
git add skills/heartbeat/heartbeat.sh skills/heartbeat/heartbeat-state.sh hooks/pre-compact.sh \
  skills/worker/task.sh skills/source-jira/fetch.sh skills/source-gitlab/fetch-mrs.sh \
  skills/source-gitlab/fetch-activity.sh skills/source-gmail/fetch.sh \
  skills/source-calendar/fetch.sh skills/heartbeat/generate-dashboard.sh
git commit -m "feat: translate bash script comments and output strings to English"
```

---

## Task 9: CLAUDE.md (plugin instructions)

**Files:**
- Rewrite: `CLAUDE.md`

- [ ] **Step 1: Rewrite CLAUDE.md**

Already mostly English. Fix:
- Line 11: Czech section "Uživatel si vytvoří..." → English
- Line 69: "Triviální chat zprávy..." → English
- Any remaining Czech fragments
- Add language convention note: "All prompts default to English. Runtime language is configured in user's `memory/persona.md`."

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: complete English translation of plugin CLAUDE.md"
```

---

## Task 10: README & metadata

**Files:**
- Rewrite: `README.md`
- Update: `.claude-plugin/plugin.json`

- [ ] **Step 1: Rewrite README.md**

Full rewrite in English:
- Pitch: "Kvido is a Claude Code plugin that turns your terminal into a living workspace assistant. It monitors your work tools (Jira, GitLab, Slack, Calendar, Gmail) and communicates with you via Slack DM."
- Features section with bullet list
- Prerequisites table (jq required, rest optional)
- Installation: 4 steps (mkdir, plugin install, claude, /setup)
- Daily usage: natural language triggers with examples
- Configuration: kvido.local.md, .env, persona.md
- Structure: directory tree
- How it works: brief architecture
- Status + known limitations

- [ ] **Step 2: Update plugin.json**

Add `license` and `keywords`:
```json
{
  "name": "kvido",
  "version": "0.1.0",
  "description": "Personal AI workflow assistant — heartbeat, planner, worker, triage",
  "license": "MIT",
  "keywords": ["assistant", "workflow", "heartbeat", "planner", "monitoring"],
  "author": { "name": "Pavel Stejskal" },
  "homepage": "https://github.com/spajxo/kvido",
  "repository": "https://github.com/spajxo/kvido"
}
```

- [ ] **Step 3: Verify LICENSE**

Verify `LICENSE` file exists and matches the `license` field in `plugin.json` (MIT).

- [ ] **Step 4: Commit**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: rewrite README for public release, update plugin.json metadata"
```

---

## Task 11: Functional validation — clean install

**No file changes expected. Manual testing.**

- [ ] **Step 1: Create clean workspace**

```bash
mkdir -p ~/kvido-test && cd ~/kvido-test && git init
```

- [ ] **Step 2: Install plugin locally**

```bash
claude plugin install /home/spajxo/Projects/github.com/spajxo/kvido --scope local
```

- [ ] **Step 3: Run /setup**

Verify:
- Prerequisites check runs (jq found, optional tools reported)
- `.claude/kvido.local.md` created from example
- `.env` created with empty values
- `memory/` and `state/` directories created
- `CLAUDE.md` copied from template
- persona.md creation prompt appears (in English)
- Language question appears

- [ ] **Step 4: Verify config.sh path resolution**

```bash
# From workspace directory, config.sh should find .claude/kvido.local.md
skills/config.sh 'skills.heartbeat.wh_start'
# Should return: 7
```

- [ ] **Step 5: Test graceful degradation**

Verify these don't crash:
- Run without glab installed → GitLab source skips
- Run without acli → Jira source skips
- Run without gws → Calendar/Gmail sources skip
- Empty .env → Slack disabled, clear message
- No persona.md → defaults to English

- [ ] **Step 6: Test /setup idempotence**

Run `/setup` again — should report "all good", not overwrite existing files.

- [ ] **Step 7: Runtime tests (requires live credentials)**

If Slack credentials are configured in test workspace:
- Run `/morning` — verify briefing generates in English (or persona language)
- Run `/heartbeat` — verify cron starts, planner dispatches
- Send Slack DM — verify chat-agent responds

Skip if no live credentials available — these tests are done in the dev instance.

- [ ] **Step 8: Cleanup**

```bash
rm -rf ~/kvido-test
```

---

## Task 12: kvido.local.md.example polish

**Files:**
- Update: `kvido.local.md.example`

- [ ] **Step 1: Add English section headers and descriptions**

The file already uses English comments. Verify and enhance:
- Each section should have a brief description of what it configures
- Commented-out examples should be clear about format
- Add a "Quick start" comment at top explaining minimum config needed

- [ ] **Step 2: Commit**

```bash
git add kvido.local.md.example
git commit -m "docs: polish kvido.local.md.example with better descriptions"
```

---

## Execution Order

Tasks 1–9 (translation) can be parallelized — they touch independent files. Recommended grouping for parallel execution:

| Batch | Tasks | Description |
|-------|-------|-------------|
| A | 1, 9 | User-facing: CLAUDE.md.template + setup.md (Task 1), CLAUDE.md (Task 9) — different files |
| B | 2, 3 | Core skills: orchestration + daily routines |
| C | 4, 5 | Support + source skills |
| D | 6, 7, 8 | Agents, commands, bash scripts |
| E | 10, 12 | README, metadata, config example |
| F | 11 | Functional validation (after all translations) |

Task 11 (validation) must run last, after all translations are committed.
