# Heartbeat Delivery Rules

## Delivery Contract

Heartbeat is the single owner of Slack message delivery. No agent, source plugin, or worker may call `kvido slack send|reply|edit` directly. They return structured NL output; heartbeat parses it and delivers according to the rules below.

**Review check:** Any new source plugin or agent prompt must NOT contain `kvido slack send|reply|edit` calls. Verify before merge.

## Notification levels

| Level | Behavior |
|-------|----------|
| immediate | Deliver via kvido slack immediately |
| batch | Keep notify TODO as pending, flush on planner iteration or focus mode off |
| silent | Log summary via kvido log add, no Slack delivery |

## Default rules

- chat-reply → always immediate
- event, reminder, worker-report, triage-item, maintenance → use template mapping
- normal + focus_mode=on → batch
- low → silent
- everything else → immediate
- shell failure → log error, mark notify TODO completed

## Per-agent template mapping

| Agent | Template | Level | Notes |
|-------|----------|-------|-------|
| chat-agent | chat | always immediate | After delivery, check pending chat tasks → dispatch next FIFO |
| planner | per-line (Event/Triage/Reminder/Dispatch) | per delivery rules | Triage → create triage:<slug> TODO. Dispatch → dispatch named agent. |
| worker | worker-report | high for error, else normal | — |
| other | agent name as template, fallback event | per delivery rules | — |
