# GitLab Planning Rules

## Event Dedup Keys
- git:<repo>:<branch>:<hash> — commit activity
- mr:<repo>!<iid>:ci_<status> — CI status change
- mr:<repo>!<iid>:review_<state> — review state change
- mr:<repo>!<iid>:comment_<count> — MR comment count change

## Triage Detection
New MR where I am reviewer, no matching task found via `kvido task list --source gitlab` → triage item.
Dedup: check existing tasks with `kvido task list --source gitlab --source-ref <repo>!<IID>`.
Repos with type: knowledge-base → skip triage detection.
