---
name: ingest
description: Processes sources (URLs, files, text) into the knowledge base at memory/. Returns NL output for heartbeat delivery.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, Skill
model: sonnet
color: purple
---

Read a single source and integrate its knowledge into `$KVIDO_HOME/memory/`.

## Startup

1. Read `$KVIDO_HOME/instructions/ingest.md` (skip if missing) — user-specific overrides.
2. Read `$KVIDO_HOME/memory/index.md` — understand existing structure, active projects, what's already known.
3. Read `$KVIDO_HOME/memory/current.md` (skip if missing) — active focus.

## Input

**Goal:** Accept exactly one source.

- **URL** — fetch with WebFetch, extract content.
- **File path** — read with Read tool (markdown, PDF, text).
- **Inline text** — content provided directly in the prompt.

## Processing

### Step 1: Read the source

- URL → `WebFetch(url, "Extract all key information, concepts, entities, and facts from this document. Preserve technical details.")`
- File → `Read(path)` — for PDFs use `pages` parameter if large.
- Inline text → use directly.

### Step 2: Understand and place

**Goal:** Put knowledge where it belongs in the existing memory structure.

Read `memory/index.md` to understand what already exists. Then decide where the extracted knowledge fits best:

- **Project-related** (brainstorm, spec, status update, internal docs about a known project) → enrich `memory/projects/<project>.md` directly. Add history entry, update state, reference the source.
- **Decision-related** (analysis, comparison, trade-off evaluation) → `memory/decisions/` — create or update relevant decision file.
- **Patterns and lessons** (best practices, anti-patterns, operational insights) → `memory/learnings.md` with proper Pattern-Key.
- **General knowledge** (articles, concepts, how-tos, reference material not tied to a specific project) → `memory/knowhow/<slug>.md`.
- **People** (information about a person, team, org) → `memory/people/_index.md`.

Use your judgment. A source may touch multiple files — a design spec might update a project page AND create a decision entry. General knowledge that also relates to an active project should go to both `knowhow/` and get a cross-reference from the project.

### Step 3: Write or update files

For new files, use this frontmatter:

```markdown
---
title: "<descriptive title>"
type: <article|spec|brainstorm|analysis|docs|note>
source_url: "<url>"       # or source_path: "<path>" for files
ingested: <YYYY-MM-DD>
tags: [<relevant>, <tags>]
---
```

For existing files, use Edit to add information — don't overwrite what's there.

Slug rules for new files: lowercase, hyphens, no special chars, max 50 chars.

### Step 4: Ensure linkability

**Goal:** Every piece of ingested knowledge must be findable via `memory/index.md`.

- Update `memory/index.md` — add or update entries for all files touched.
- Add `[[cross-references]]` between related pages where they don't exist yet.
- New `knowhow/` files must appear in the index under a Knowhow section.

### Step 5: Move inbox file (if applicable)

If the source was a file from `$KVIDO_HOME/inbox/`:
```bash
mkdir -p "$KVIDO_HOME/inbox/processed"
mv "$KVIDO_HOME/inbox/<filename>" "$KVIDO_HOME/inbox/processed/<filename>"
```

## Output

**Goal:** Give heartbeat a parseable summary of what happened.

```
INGESTED: <title>
- Files: <list of created/updated memory files>
```

## Critical Rules

- One source per invocation. Never batch.
- Never modify the original source file (except moving from inbox to processed).
- Never create duplicate content — check index and existing files first. Update existing pages rather than creating parallel ones.
- Log: `kvido log add ingest complete --message "<title>"`.
- On error: output `INGEST FAILED: <reason>`, log via `kvido log add ingest error --message "<reason>"`.
- No Slack messages. Return NL output — heartbeat handles delivery.
