#!/usr/bin/env bash
# lib.sh — Shared helper functions for kvido scripts
# Source this file at the top of scripts that need these helpers:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"   (adjust path as needed)
#
# Provides:
#   _make_tmp <base_path>            — create a mktemp next to <base_path>
#   _lock_acquire <lock_file> [timeout_s]  — acquire an flock, register cleanup
#   _lock_release <lock_file>        — release the flock and remove the lock file

# _make_tmp <base_path>
# Creates a temporary file adjacent to <base_path> using a consistent pattern.
# Prints the path of the created temp file.
# The caller is responsible for removing it (or for mv-ing it into place).
_make_tmp() {
  local base="$1"
  mktemp "${base}.tmp.XXXXXX"
}

# _lock_acquire <lock_file> [timeout_seconds]
# Opens and flocks <lock_file> on fd 200, waits up to timeout_seconds (default 10).
# Registers a trap to call _lock_release on EXIT so stale locks are always cleaned up.
# Exits with status 1 on timeout.
_lock_acquire() {
  local lock_file="$1"
  local timeout="${2:-10}"
  mkdir -p "$(dirname "$lock_file")"
  # Open the lock file on fd 200
  exec 200>"$lock_file"
  if ! flock -w "$timeout" 200; then
    echo "kvido: timeout acquiring lock on $lock_file (${timeout}s)" >&2
    exec 200>&-
    exit 1
  fi
  # Register cleanup so the lock file is removed even on unexpected exit
  trap '_lock_release '"$lock_file"'' EXIT
}

# _lock_release <lock_file>
# Releases the flock on fd 200 and removes the lock file.
# Safe to call multiple times (idempotent).
_lock_release() {
  local lock_file="$1"
  # Close fd 200 if still open (releases the flock)
  exec 200>&- 2>/dev/null || true
  # Remove the lock file so it does not accumulate as a stale file
  [[ -f "$lock_file" ]] && rm -f "$lock_file" || true
}
