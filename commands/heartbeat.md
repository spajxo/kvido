---
description: Heartbeat — orchestrátor, chat check, worker dispatch, log, adaptive interval
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Agent, CronCreate, CronList, CronDelete, mcp__claude_ai_Slack__slack_read_channel
---

## Krok 0: Nastav cron (pouze jednou za session)

Zavolej `CronList`. Pokud žádný job neobsahuje slovo `heartbeat`, zavolej `CronCreate`:
- `cron`: `*/10 * * * *` (výchozí 10m — adaptive interval pak přepne dle kontextu)
- `recurring`: `true`
- `prompt`: `Přečti a postupuj dle skills/heartbeat/SKILL.md.`

Po vytvoření cronu ulož job ID do `state/heartbeat-state.json` jako `cron_job_id` a nastav `active_preset: "10m"`.

Cron vytvoř tiše — nevypisuj nic, pokud nedojde k chybě.

## Krok 1+: Spusť heartbeat

Přečti a postupuj dle `skills/heartbeat/SKILL.md`.
