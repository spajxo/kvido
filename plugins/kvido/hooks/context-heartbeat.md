# Heartbeat Delivery Rules

## Delivery Contract

Heartbeat is the single owner of Slack message delivery. No agent, source plugin, or worker may call `kvido slack send|reply|edit` directly. They return structured NL output; heartbeat parses it and delivers according to the rules below.

**Review check:** Any new source plugin or agent prompt must NOT contain `kvido slack send|reply|edit` calls. Verify before merge.

## Chat ack lifecycle

When heartbeat detects a new chat message:
1. `kvido slack react <ts> eyes` — immediate ack
2. Dispatch chat-agent
3. Deliver chat-agent reply
4. `kvido slack unreact <ts> eyes` — remove ack

## Notification levels

| Level | Behavior |
|-------|----------|
| immediate | Deliver via kvido slack immediately |
| batch | Keep notify TODO as pending, flush on planner iteration or focus mode off |
| silent | Log summary via kvido log add, no Slack delivery |

## Default rules

- chat-reply → always immediate
- event, reminder, worker-report, triage-item, maintenance → use template mapping
- normal + `skills.planner.focus_mode.enabled`=true → batch
- low → silent
- everything else → immediate
- shell failure → log error, mark notify TODO completed

## Digest threading

When agents return multiple findings to deliver in a single cycle:
- 1 finding → deliver as standalone
- 2+ findings → send digest parent via `kvido slack send ... digest`, then each finding as `kvido slack reply ... <digest_ts> event`
- `digest_ts` is ephemeral — used only within the current heartbeat execution

## Batch flush threading

When flushing batched notifications:
- Send `batch-header` parent via `kvido slack send ... batch-header` → capture `ts`
- Each batched notification as `kvido slack reply ... <batch_ts> <template>`

## Processing status edits

For worker and planner dispatches, heartbeat sends a status message and edits it on completion:

| Dispatch | Status message | On success | On failure |
|----------|---------------|------------|------------|
| worker | `kvido slack send ... chat --var message=":hourglass_flowing_sand: Working on <title>..."` | `kvido slack edit ... <ts> chat --var message=":white_check_mark: Done: <title> — <duration>"` | `kvido slack edit ... <ts> chat --var message=":x: Failed: <title> — <summary>"` |
| planner | `kvido slack send ... chat --var message=":hourglass_flowing_sand: Planner scanning..."` | `kvido slack edit ... <ts> chat --var message=":white_check_mark: Planner done — <count> dispatches"` | `kvido slack edit ... <ts> chat --var message=":x: Planner failed — <error>"` |

Chat-agent uses ack reactions only (see Chat ack lifecycle above), not status edits.

## Per-agent template mapping

| Agent | Template | Level | Notes |
|-------|----------|-------|-------|
| chat-agent | chat | always immediate | Ack react before dispatch, unreact after delivery. After delivery, check pending chat tasks → dispatch next FIFO |
| worker | worker-report | high for error, else normal | — |
| gatherer | event | per urgency rules | Each finding delivered as separate notification. Gatherer suggests urgency, heartbeat decides. |
| triager | triage-item | immediate | For triage items needing user attention. Save returned `ts` to task note. |
| maintenance | agent name as template, fallback event | per delivery rules | When falling back to `event` template, set `--var severity_bar=:large_yellow_circle:` as default |
