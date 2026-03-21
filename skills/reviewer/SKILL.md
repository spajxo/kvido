---
name: reviewer
description: Use when a worker task needs to review a GitLab merge request and produce a triage-ready summary.
allowed-tools: Read, Glob, Grep, Bash
user-invocable: false
---

# Reviewer

Instrukce pro worker task provádějící MR review summary.

## Postup
1. Spusť `glab mr view <iid>` v příslušném repo
2. Spusť `glab mr diff <iid> | head -200`
3. Vrať shrnutí (max 5 řádků):
   - Co se mění (1 věta)
   - Rozsah (soubory, řádky)
   - Risk level: low/medium/high
   - Doporučení: approve/comment/needs-deep-review
