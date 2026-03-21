---
name: daily-questions
description: Volitelné EOD reflektivní otázky pro self-awareness a pattern detection.
allowed-tools: Read, Write
user-invocable: false
---

> **Konfigurace:** Přečti `kvido.local.md` v této složce. Pokud `enabled: false`, přeskoč.

# Daily Questions

Voláno z EOD skill (po journal entry, před confirm).

## Postup

1. Přečti kvido.local.md — pokud `enabled: false`, přeskoč.
2. Zkontroluj `frequency`:
   - `weekdays` → přeskoč sobotu a neděli
   - `friday_only` → přeskoč pokud není pátek
   - `daily` → vždy
3. Vyber 1-2 otázky kontextově (max dle `max_questions`):
   - Porovnej Active Focus z morning (`state/today.md`) vs skutečná git activity → "Podařilo se zaměřit na plán?"
   - Check Jira deadlines na zítřek → "Máš na zítřek něco co vyžaduje přípravu?"
   - Pokud byl frustrující den (hodně error/blocker entries v `state/today.md`) → "Co tě dneska nejvíc brzdilo?"
   - Random reflective: "Co bys dneska udělal jinak?"
4. Zeptej se uživatele. Zapiš odpovědi do journalu (`memory/journal/YYYY-MM-DD.md`) jako sekce `## Reflection`.
5. Po 20+ odpovědích (spočítej `## Reflection` sekce v `memory/journal/`): analyzuj patterns a zapiš do `memory/learnings.md`.
