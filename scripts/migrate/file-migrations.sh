#!/usr/bin/env bash
# file-migrations.sh — Migrate file locations (memory → instructions, state → memory)
# Called from migrate.sh on startup. Idempotent.
#
# Migrates:
#   memory/persona.md → instructions/persona.md (refactor/move-persona-to-instructions)
#   state/current.md → memory/current.md (feat/move-current-to-memory)

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"

migrated=0

# Migrate memory/persona.md → instructions/persona.md
OLD_PERSONA="${KVIDO_HOME}/memory/persona.md"
NEW_PERSONA="${KVIDO_HOME}/instructions/persona.md"
if [[ -f "$OLD_PERSONA" && ! -f "$NEW_PERSONA" ]]; then
  mkdir -p "${NEW_PERSONA%/*}"
  mv "$OLD_PERSONA" "$NEW_PERSONA"
  migrated=1
  echo "file-migrations: moved memory/persona.md → instructions/persona.md" >&2
fi

# Migrate state/current.md → memory/current.md
OLD_CURRENT="${KVIDO_HOME}/state/current.md"
NEW_CURRENT="${KVIDO_HOME}/memory/current.md"
if [[ -f "$OLD_CURRENT" && ! -f "$NEW_CURRENT" ]]; then
  mkdir -p "${NEW_CURRENT%/*}"
  mv "$OLD_CURRENT" "$NEW_CURRENT"
  migrated=1
  echo "file-migrations: moved state/current.md → memory/current.md" >&2
fi

if [[ "$migrated" -eq 1 ]]; then
  echo "file-migrations: file migration complete" >&2
fi
