#\!/usr/bin/env bash
# memory-sync.sh — Commit & push KVIDO_HOME memory to git (always targets main)
#
# Usage:
#   kvido memory-sync                  Full sync: checkout main, pull, stage, commit, push
#   kvido memory-sync --status         Show git status only
#   kvido memory-sync --commit-only    Commit without push
#   kvido memory-sync --dry-run        Show what would be committed
#
# Safety: always checks out main and pulls before committing.
# If the working tree has uncommitted changes on a non-main branch,
# they are stashed, main is checked out, and stash is applied.

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"

cd "$KVIDO_HOME"

# --- Flags ---
MODE="full"
case "${1:-}" in
  --status)     MODE="status" ;;
  --commit-only) MODE="commit-only" ;;
  --dry-run)    MODE="dry-run" ;;
  --help|-h)
    sed -n '2,/^$/{ s/^# //; s/^#$//; p }' "$0"
    exit 0
    ;;
  "") ;;
  *)
    echo "ERROR: Unknown flag: $1" >&2
    echo "Usage: kvido memory-sync [--status|--commit-only|--dry-run]" >&2
    exit 1
    ;;
esac

# --- Ensure we are on main ---
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

if [[ "$MODE" == "status" ]]; then
  git status --short
  exit 0
fi

if [[ "$CURRENT_BRANCH" \!= "main" ]]; then
  echo "memory-sync: switching to main (was on '$CURRENT_BRANCH')"
  # Stash any uncommitted changes so checkout doesn't fail
  STASHED=false
  if \! git diff --quiet HEAD 2>/dev/null || \! git diff --cached --quiet 2>/dev/null; then
    git stash push -m "memory-sync: auto-stash before switching to main" --include-untracked
    STASHED=true
  fi
  git checkout main
  if [[ "$STASHED" == true ]]; then
    git stash pop || {
      echo "WARNING: stash pop failed — changes remain in stash" >&2
    }
  fi
fi

# Pull latest to avoid conflicts (fast-forward only)
git pull --ff-only origin main 2>/dev/null || {
  echo "WARNING: git pull --ff-only failed (possible divergence), continuing with local state" >&2
}

# --- Check for changes ---
if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
  echo "memory-sync: nothing to commit"
  exit 0
fi

if [[ "$MODE" == "dry-run" ]]; then
  echo "memory-sync: would commit the following changes:"
  git status --short
  exit 0
fi

# --- Stage, commit, push ---
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
git add -A
git commit -m "chore: memory sync $TIMESTAMP"

if [[ "$MODE" == "commit-only" ]]; then
  echo "memory-sync: committed (push skipped)"
  exit 0
fi

git push origin main
echo "memory-sync: committed and pushed to main"
