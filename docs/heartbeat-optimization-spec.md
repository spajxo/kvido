# Design Spec: Heartbeat Instruction Optimization

**Issue:** https://github.com/spajxo/kvido/issues/193
**Status:** Draft
**Date:** 2026-03-30

---

## Problem

`commands/heartbeat.md` is 355 lines and is loaded in full on every heartbeat tick — typically every 10 minutes. Steps 4–6 (planner dispatch, agent dispatch, output collection and delivery) contain dense context that is only relevant when specific conditions are met:

- Step 4 (Planner) — only runs when `PLANNER_DUE=true` (every 3rd iteration by default)
- Step 5 (Dispatch) — only relevant if planner actually produced `DISPATCH` lines
- Step 6 (Collect & Deliver) — only relevant if background agents have completed

In the common case (non-planner tick, no completed agents), the model loads this context and then does nothing with it — wasted prompt tokens and increased TTFT.

**Precedent:** `agents/gatherer.md` was refactored similarly in #150 — per-source docs extracted into `agents/sources/<source>.md`, reducing context from ~397 to ~139 lines for disabled sources.

---

## Approach 1: Skills Lazy-Loading (Recommended First Step)

Extract Steps 4–6 from `heartbeat.md` into separate skills. The base heartbeat prompt remains small; steps are loaded on demand only when the condition is true.

### Proposed skill split

| Skill | Loaded when | Content |
|-------|-------------|---------|
| `kvido:heartbeat-planner` | `PLANNER_DUE=true` | Step 4: planner dispatch logic, planner output format, DISPATCH/NOTIFY parsing |
| `kvido:heartbeat-dispatch` | Planner returned DISPATCH lines | Step 5: full dispatch rules per agent type (worker, maintenance, chat), blockedBy logic |
| `kvido:heartbeat-deliver` | Background agents completed | Step 6: output collection, urgency classification, Slack delivery rules, per-agent delivery table, digest threading |

### How it works

In the base `heartbeat.md`, each step becomes a conditional load:

```markdown
## Step 4: Run Planner

If `PLANNER_DUE=true`: load skill `kvido:heartbeat-planner` and follow its instructions.
Otherwise: skip to Step 5.

## Step 5: Dispatch Agents

If planner returned DISPATCH lines, or `chat:*` tasks are pending: load skill `kvido:heartbeat-dispatch`.
Otherwise: skip to Step 6.

## Step 6: Collect Outputs & Deliver

If any background agent tasks completed this iteration: load skill `kvido:heartbeat-deliver`.
Otherwise: silent exit.
```

### Estimated savings

Current `heartbeat.md`: 355 lines
Proposed base heartbeat: ~120 lines (Steps 0–3 + Step 7 + Common Mistakes + Critical Rules)

| Scenario | Lines loaded | vs. current |
|----------|-------------|-------------|
| Quiet tick (no planner, no completions) | ~120 | -66% |
| Planner tick, no completions | ~120 + ~60 = ~180 | -49% |
| Full tick (planner + completions) | ~120 + ~60 + ~80 + ~100 = ~360 | ~same (worst case) |

Worst case is neutral. Common case is 66% smaller prompt.

### What stays in base heartbeat.md

- Step 0: kvido CLI check
- Step 1: Loop verification (first tick)
- Step 2: Init (`kvido heartbeat`, recovery check)
- Step 3: Chat Check (full — runs every tick, trivial classification is inline)
- Step 7: Adaptive Interval
- Common Mistakes (condensed — only mistakes relevant to Steps 0–3 and Step 7)
- Critical Rules (all — essential for every tick)

### Skill boundaries

**`kvido:heartbeat-planner`** contains:
- Planner dispatch logic (foreground agent, task lifecycle)
- Planner output format reference (DISPATCH, DISPATCH_AFTER, NOTIFY)
- Throttle rules (PLANNER_DUE check already done — skill assumes it's true)

**`kvido:heartbeat-dispatch`** contains:
- DISPATCH parsing loop
- Worker specifics (task read, source-ref ack, model parameter)
- Maintenance specifics (blockedBy logic)
- DISPATCH_AFTER sequential ordering
- NOTIFY handling (direct delivery)
- Chat dispatch from Step 3

**`kvido:heartbeat-deliver`** contains:
- Common pattern (TaskOutput, logging, notify task lifecycle)
- Urgency classification table
- Notification levels
- Per-agent delivery table (chat, planner, worker, gatherer, triager, maintenance, researcher)
- Planner summary composition (bash commands + template vars)
- Digest threading and batch flush rules
- Processing status edits table

### File layout

```
commands/
  heartbeat.md          # base — ~120 lines, loads skills on demand
skills/
  heartbeat-planner.md  # step 4 — ~60 lines
  heartbeat-dispatch.md # step 5 — ~80 lines
  heartbeat-deliver.md  # step 6 — ~100 lines
```

Skills live in the plugin's `skills/` directory (same as other kvido skills).

### Compatibility notes

- Skills are loaded via `Skill` tool call — this is already the mechanism heartbeat uses for subagent instructions
- No changes to planner, workers, or other agents
- No changes to `kvido heartbeat` CLI output format
- Behavioral change: none — only the loading strategy changes

---

## Approach 2: `agents/heartbeat-session.md` with `--agent` (Larger Refactor)

Create a dedicated agent definition file for the heartbeat session. Run heartbeat as:

```bash
claude --agent heartbeat-session
```

The agent file sets a minimal system prompt and preloads only the skills needed for the session.

### Investigation results

Research for issue #193 confirmed:
- `--agents=kvido` syntax does **not** exist
- `claude --agent <name>` **does** work — sets a session-wide system prompt from an agent definition file in `agents/`
- Skills in agent frontmatter are available for the session (preloaded)

### Proposed agent file

`agents/heartbeat-session.md`:

```markdown
---
name: heartbeat-session
description: Minimal heartbeat session agent — focused context, lazy skill loading
model: haiku
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronCreate, CronList, CronDelete, TaskCreate, TaskList, TaskUpdate, TaskGet, TaskOutput, mcp__claude_ai_Slack__slack_read_channel
---

You are the kvido heartbeat — a lightweight orchestrator that runs every 10 minutes.
Load persona from `kvido instructions read persona` (Heartbeat section).
Run `/kvido:heartbeat` for the full heartbeat sequence.
Be extremely brief — no output if nothing to report.
```

The agent sets the session context (model, tools, persona); the actual heartbeat logic remains in `commands/heartbeat.md` (or skills, if Approach 1 is implemented first).

### Benefit

- Session model can be `haiku` by default (cheaper for quiet ticks where nothing happens)
- System prompt is minimal — not the full heartbeat.md
- Combined with Approach 1: base heartbeat ~120 lines on haiku = very cheap common case

### Tradeoffs

- Requires changing how the heartbeat loop is launched (`claude --agent heartbeat-session` instead of current mechanism)
- The `--agent` flag behavior needs to be validated against the current kvido loop/cron setup
- More invasive change — risk of regressions in session lifecycle

### Open questions

1. Does `claude --agent` work correctly when invoked from a cron job via `CronCreate`?
2. Can the agent definition coexist with the current `/kvido:heartbeat` slash command?
3. What happens to `CLAUDE.md` injection when `--agent` is used — does it still apply?

---

## Recommended Path

### Phase 1 (lower effort, immediate benefit)

Implement Approach 1 — skills lazy-loading:

1. Extract Step 6 into `skills/heartbeat-deliver.md` (biggest section, most conditionally needed)
2. Extract Step 5 into `skills/heartbeat-dispatch.md`
3. Extract Step 4 into `skills/heartbeat-planner.md`
4. Update `commands/heartbeat.md` with conditional skill load instructions
5. Smoke test: quiet tick, planner tick, worker completion

### Phase 2 (bigger refactor, better architecture)

Implement Approach 2 — `agents/heartbeat-session.md`:

1. Resolve open questions (cron compat, CLAUDE.md injection)
2. Create `agents/heartbeat-session.md` with haiku model + minimal prompt
3. Update launch mechanism
4. Validate session lifecycle end-to-end

### Phase 3 (experimental)

Persistent agent memory between ticks — state reuse without re-injecting full context. Requires agent-level memory support; lower priority.

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Base heartbeat prompt size | < 130 lines |
| Quiet tick prompt tokens | < 50% of current |
| Planner tick prompt tokens | < 70% of current |
| No behavioral regressions | All existing heartbeat behaviors preserved |
