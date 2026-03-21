---
name: source-gmail
description: Gmail source — nepřečtené emaily, priority sender watch. Lightweight fetch/watch pro gather.
allowed-tools: Read, Bash
user-invocable: false
---

> **Konfigurace:** Přečti `kvido.local.md` v této složce pro filtry a priority senders.

# Source: Gmail

## Capabilities

### fetch
Spusť `fetch.sh`. Vrátí formátovaný souhrn nepřečtených emailů filtrovaných dle kvido.local.md.
Výstup: lidsky čitelný souhrn — od, předmět, datum, snippet. Max `max_results` položek.

### watch
Quick check počtu nepřečtených od priority senderů od posledního checku.
Pokud nový důležitý email (od priority_senders) → emit event pro heartbeat.
Event key pattern: `email:<message_id>` — pro dedup v heartbeat-state.json.

### health
```bash
gws gmail users getProfile me
```
Výsledek do `state/source-health.json` pod klíč `gmail`.

## Schedule
- morning: `fetch` (nepřečtený inbox)
- heartbeat-quick: skip
- heartbeat-full: `watch` (nové od posledního checku)
- heartbeat-maintenance: skip
- eod: skip
