### GitLab

> Config: `gitlab.*` keys. Requires: `glab` CLI.

#### Capabilities

**fetch-activity:**
```bash
kvido-fetch-gitlab-activity YYYY-MM-DD [--priority high]
```
`--priority high` filters only repos with `priority: high`.

**fetch-mrs:**
```bash
kvido-fetch-gitlab-mrs [--priority high]
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

#### Notification Rules
- MR CI failure → template: event, level: immediate
- MR approved/merged → template: event, level: normal
- New MR assigned for review → template: triage-item, level: immediate
- MR comment → template: event, level: batch
