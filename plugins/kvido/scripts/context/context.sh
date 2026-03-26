#!/usr/bin/env bash
set -euo pipefail

# kvido context <phase>
# Assembles plugin-contributed markdown context for a lifecycle phase.
# Phases: session, heartbeat, planner, setup, compact
#
# 1. Outputs core hooks/context-<phase>.md (if exists)
# 2. Discovers installed kvido-* plugins
# 3. For each plugin: outputs <installPath>/hooks/context-<phase>.md (if exists)
# Output: concatenated markdown on stdout with <!-- plugin: name --> separators

PHASE="${1:?Usage: kvido context <phase>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Core base rules
CORE_HOOK="$PLUGIN_ROOT/hooks/context-${PHASE}.md"
if [[ -f "$CORE_HOOK" ]]; then
  echo "<!-- core: kvido -->"
  cat "$CORE_HOOK"
  echo ""
fi

# Plugin contributions via discover-sources
DISCOVER="$PLUGIN_ROOT/scripts/discover-sources.sh"
if [[ -x "$DISCOVER" ]]; then
  while IFS=$'\t' read -r name install_path; do
    HOOK_FILE="$install_path/hooks/context-${PHASE}.md"
    if [[ -f "$HOOK_FILE" ]]; then
      echo "<!-- plugin: $name -->"
      cat "$HOOK_FILE"
      echo ""
    fi
  done < <(bash "$DISCOVER" 2>/dev/null || echo "ERROR: discover-sources.sh failed (exit $?)" >&2)
fi
