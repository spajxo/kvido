---
name: daily-questions
description: Use when EOD skill generates optional reflective questions for self-awareness.
allowed-tools: Read, Write
user-invocable: false
---

**Language:** Communicate in the language set in memory/persona.md. Default: English.

> **Configuration:** Read `kvido.local.md`. If `enabled: false`, skip.

# Daily Questions

Called from EOD skill (after journal entry, before confirm).

## Procedure

1. Read `kvido.local.md` — if `enabled: false`, skip.
2. Check `frequency`:
   - `weekdays` → skip Saturday and Sunday
   - `friday_only` → skip if not Friday
   - `daily` → always
3. Select 1-2 questions contextually (max per `max_questions`):
   - Compare Active Focus from `state/current.md` vs actual git activity → "Did you manage to stay focused on the plan?"
   - Check Jira deadlines for tomorrow → "Is there anything tomorrow that requires preparation?"
   - If it was a frustrating day (many error entries in `kvido log list --today --agent heartbeat`) → "What slowed you down the most today?"
   - Random reflective: "What would you do differently today?"
4. Ask the user. Write responses to the journal (`memory/journal/YYYY-MM-DD.md`) as section `## Reflection`.
5. After 20+ responses (count `## Reflection` sections in `memory/journal/`): analyze patterns and write to `memory/learnings.md`.
