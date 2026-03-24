---
name: reviewer
description: Use when a worker task needs to review a GitLab merge request and produce a triage-ready summary.
allowed-tools: Read, Glob, Grep, Bash
user-invocable: false
---

# Reviewer

Instructions for a worker task performing an MR review summary.

## Steps
1. Run `glab mr view <iid>` in the relevant repo
2. Run `glab mr diff <iid> | head -200`
3. Return a summary (max 5 lines):
   - What is changing (1 sentence)
   - Scope (files, lines)
   - Risk level: low/medium/high
   - Recommendation: approve/comment/needs-deep-review
