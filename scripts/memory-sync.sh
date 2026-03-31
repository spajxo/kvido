#!/usr/bin/env bash
# memory-sync.sh — Git commit & push KVIDO_HOME to keep it synchronized.
#
# Usage:
#   kvido memory-sync               # commit & push if there are changes
#   kvido memory-sync --status      # show git status only (no commit/push)
#   kvido memory-sync --commit-only # commit but do not push
#   kvido memory-sync --dry-run     # show what would be committed (no changes)
#
# Behavior:
#   - Stages all changes (git add -A), excluding state/ ephemeral files
#   - Commits only if there are staged changes
#   - Always pushes to 'main' branch (not current branch)
#   - Exits 0 even if there is nothing to commit (idempotent)
#
# Integration:
#   Called at the end of each heartbeat cycle (via heartbeat.sh or heartbeat agent).
#   Can also be called manually: kvido memory-sync

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"

DRY_RUN=false
STATUS_ONLY=false
COMMIT_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=true ;;
    --status)       STATUS_ONLY=true ;;
    --commit-only)  COMMIT_ONLY=true ;;
    --help|-h)
      cat <<'HELP'
kvido memory-sync — sync KVIDO_HOME to git remote

Usage: kvido memory-sync [--status] [--commit-only] [--dry-run]

Options:
  --status       Show git status only, do not commit or push
  --commit-only  Commit changes but do not push to remote
  --dry-run      Show what would be committed (no changes made)
  --help, -h     Show this help

Exit codes:
  0  Success (including nothing to commit)
  1  Git error or KVIDO_HOME is not a git repository
HELP
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg" >&2
      echo "Run 'kvido memory-sync --help' for usage." >&2
      exit 1
      ;;
  esac
done

# Verify KVIDO_HOME is a git repo
if [[ ! -d "$KVIDO_HOME/.git" ]]; then
  echo "ERROR: KVIDO_HOME is not a git repository: $KVIDO_HOME" >&2
  echo "Initialize with: git -C \"$KVIDO_HOME\" init" >&2
  exit 1
fi

# --status: just show git status and exit
if [[ "$STATUS_ONLY" == "true" ]]; then
  git -C "$KVIDO_HOME" status
  exit 0
fi

# --dry-run: show what would be staged
if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== Dry run: files that would be committed ==="
  git -C "$KVIDO_HOME" status --short
  exit 0
fi

# Verify we can work with the main branch
# If in detached HEAD, attempt to switch to main
BRANCH=$(git -C "$KVIDO_HOME" symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ -z "$BRANCH" ]]; then
  echo "memory-sync: detached HEAD detected, attempting to switch to main"
  git -C "$KVIDO_HOME" checkout main 2>/dev/null || {
    echo "ERROR: detached HEAD and cannot switch to main branch" >&2
    exit 1
  }
fi

# If on a non-main branch, switch to main
if [[ "$BRANCH" != "main" && -n "$BRANCH" ]]; then
  echo "memory-sync: on branch '$BRANCH', switching to 'main'"
  git -C "$KVIDO_HOME" checkout main 2>/dev/null || {
    echo "ERROR: cannot switch to main branch" >&2
    exit 1
  }
fi

# Stage all changes (including new/deleted files)
# Exclude state/ ephemeral files: session-context.md, dashboard.html
# These are regenerated each heartbeat and should not pollute history.
git -C "$KVIDO_HOME" add -A
git -C "$KVIDO_HOME" reset HEAD -- \
  "state/session-context.md" \
  "state/dashboard.html" \
  2>/dev/null || true

# Check if there is anything staged
STAGED=$(git -C "$KVIDO_HOME" diff --cached --name-only 2>/dev/null || true)
if [[ -z "$STAGED" ]]; then
  echo "memory-sync: nothing to commit"
  exit 0
fi

# Build commit message — include summary of changed areas
CHANGED_AREAS=$(git -C "$KVIDO_HOME" diff --cached --name-only \
  | awk -F/ '{print $1}' \
  | sort -u \
  | tr '\n' ',' \
  | sed 's/,$//')
COMMIT_MSG="chore: memory sync $(date -Iseconds) [${CHANGED_AREAS}]"

git -C "$KVIDO_HOME" commit -m "$COMMIT_MSG"
echo "memory-sync: committed — $COMMIT_MSG"

# Push if remote is configured and not --commit-only
if [[ "$COMMIT_ONLY" == "true" ]]; then
  echo "memory-sync: skipping push (--commit-only)"
  exit 0
fi

REMOTE=$(git -C "$KVIDO_HOME" remote 2>/dev/null | head -1 || true)
if [[ -z "$REMOTE" ]]; then
  echo "memory-sync: no remote configured, skipping push"
  exit 0
fi

# Always push to main branch explicitly (not current branch)
# This ensures memory syncs to main regardless of current branch state
git -C "$KVIDO_HOME" push "$REMOTE" HEAD:main 2>&1
echo "memory-sync: pushed to $REMOTE/main"
