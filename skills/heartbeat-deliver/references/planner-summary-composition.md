# Planner Summary Composition

After planner completes successfully, compose a structured summary and **edit** the status message (replacing `:hourglass_flowing_sand: Planner scanning...`) using the `planner-summary` template.

Gather data:

```bash
# Queue counts by priority
kvido task count todo       # total todo
kvido task list todo        # to find next-up task
kvido task count triage     # triage backlog
kvido task list in-progress # currently running workers
```

Build template vars:

| Var | Source | Example |
|-----|--------|---------|
| `iteration` | `ITERATION` from heartbeat.sh output | `245` |
| `dispatches` | Parsed `DISPATCH` lines from planner output — one per line, format `:arrow_forward: <agent/task-title> (<priority>, <size>)`. For `DISPATCH worker <id>`, use task title from `kvido task read <id>`. If no dispatches: `_nothing dispatched_` | `:arrow_forward: code-review-pr-161 (high, s)` |
| `queue_stats` | From `kvido task list todo --sort priority` — count total and breakdown by priority field. Format: `N todo (H high, M medium, L low)`. Omit zero-count priorities. | `6 todo (1 high, 3 medium, 2 low)` |
| `next_up` | Top task from `kvido task list todo --sort priority` — the first non-blocked, non-dispatched task. Format: `#<id> <title> (<priority>)`. If queue empty or all dispatched: `_queue empty_` | `#56 planner-full-task-snapshot (high)` |
| `triage_count` | `kvido task count triage` | `4` |
| `skipped` | Tasks planner explicitly noted as blocked/skipped — parsed from planner NL output (look for "blocked", "waiting", "skipped" phrasing). Format: `:no_entry_sign: #<id> <title> (<reason>)`. If none: pass empty string `""` | `:no_entry_sign: #33 config-unify (blocked by PR merge)` |
| `timestamp` | `date +%H:%M` | `09:34` |

Edit the status message with `planner-summary` template:

```bash
kvido slack edit dm <status_ts> planner-summary \
  --var iteration="<ITERATION>" \
  --var dispatches="<dispatches>" \
  --var queue_stats="<queue_stats>" \
  --var next_up="<next_up>" \
  --var triage_count="<triage_count>" \
  --var skipped="<skipped>" \
  --var timestamp="<HH:MM>"
```

Omit the `skipped` line from the template output by passing `skipped=""` when there are no skipped tasks — the template renders an empty line which is visually clean.
