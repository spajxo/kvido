### GitLab

> Config: `gitlab.*` keys. Requires: `glab` CLI.

#### Capabilities

**fetch-activity:**
```bash
kvido gitlab-activity YYYY-MM-DD [--priority high]
```
`--priority high` filters only repos with `priority: high`.

**fetch-mrs:**
```bash
kvido gitlab-mrs [--priority high]
```
Repos with `type: knowledge-base` are always skipped (no MRs).

**watch:** Run fetch-activity + fetch-mrs. Compare with previous state.

**triage-detect:** New MR where I am reviewer, not in backlog → triage item:
`- [ ] Review MR !IID: title (repo) #source:gitlab #added:YYYY-MM-DD #ref:repo!IID`

**health:** For each repo via `kvido config --keys 'gitlab.repos'`:
`test -d <path>/.git` + `glab auth status 2>/dev/null`

#### Schedule
- morning: fetch-activity (yesterday) + fetch-mrs
- heartbeat: fetch-activity (today) + fetch-mrs
- heartbeat-maintenance: health
- eod: fetch-activity (today)

#### Setup
| Prerequisite | Check |
|---|---|
| glab | `command -v glab` |
| gitlab.repos | `kvido config --keys 'gitlab.repos'` returns non-empty |

#### Dedup Keys
- `git:<repo>:<branch>:<hash>` — commit activity
- `mr:<repo>!<iid>:ci_<status>` — CI status change
- `mr:<repo>!<iid>:review_<state>` — review state change
- `mr:<repo>!<iid>:comment_<count>` — MR comment count change

#### Triage Detection
New MR where I am reviewer, no matching task found via `kvido task list triage --source gitlab` → triage item.
Dedup: check existing tasks with `kvido task list triage --source gitlab --source-ref <repo>!<IID>`.
Repos with type: knowledge-base → skip triage detection.

**Done/Cancelled dedup:** Before creating a new triage task for a PR/MR review, also check `done/` and `cancelled/` queues. If any task there has the same `source` field value (e.g. `gitlab:group/repo!<IID>`), skip creation — the PR was already reviewed. This prevents duplicate code-review tasks from re-appearing after merge or close.

```bash
# Example check before kvido task create for MR !IID in repo "group/project":
SOURCE_REF="gitlab:group/project!<IID>"
for status in done cancelled; do
  existing=$(kvido task list "$status" | while read tid slug; do
    src=$(kvido task read "$tid" 2>/dev/null | grep "^source=" | cut -d= -f2-)
    [[ "$src" == "$SOURCE_REF" ]] && echo "$tid"
  done)
  [[ -n "$existing" ]] && echo "SKIP: already $status as task $existing" && continue 2
done
# Only reach here if no match found — safe to create
kvido task create --title "..." --source "$SOURCE_REF" ...
```

#### Notification Rules
- MR CI failure → template: event, level: immediate
- MR approved/merged → template: event, level: normal
- New MR assigned for review → template: triage-item, level: immediate
- MR comment → template: event, level: batch
