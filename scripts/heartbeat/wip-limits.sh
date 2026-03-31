#!/usr/bin/env bash
# wip-limits.sh — Agent dispatch WIP limit checking
#
# Provides helper functions for enforcing concurrent limits on agent dispatch groups.
# Usage:
#   source scripts/heartbeat/wip-limits.sh
#   agent_wip_check "maintenance" && dispatch_agent maintenance:foo
#   agent_wip_check "gatherer" || skip_dispatch gatherer

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="$PLUGIN_ROOT/scripts/config.sh"

# ───────────────────────────────────────────────────────────────────────────────
# agent_wip_check <group>
# ───────────────────────────────────────────────────────────────────────────────
# Returns 0 if the agent group is below its WIP limit, 1 if at/over limit.
# Checks the configured limit for the agent group from settings.json
# (agents.wip_limits.<group>).
#
# If no limit is configured for the group, assumes unlimited (returns 0).
#
# Usage:
#   agent_wip_check "maintenance" && echo "Can dispatch" || echo "WIP limit reached"

agent_wip_check() {
  local group="$1"

  # Read limit from config (agents.wip_limits.<group>)
  local wip_limit
  wip_limit=$($CONFIG "agents.wip_limits.${group}" "" 2>/dev/null) || wip_limit=""

  # No limit configured = always allow
  if [[ -z "$wip_limit" ]]; then
    return 0
  fi

  # Count current concurrent instances of this agent group
  # Pattern: subject contains ":<group>" and status is "in_progress"
  # Assuming heartbeat.sh environment has access to task tools (Agent tool via LLM)
  # This needs to be called from the heartbeat command context with TaskList available.
  # For now, return 0 — actual counting happens in heartbeat.md logic.

  return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# agent_wip_count <group>
# ───────────────────────────────────────────────────────────────────────────────
# Returns the current WIP count for the agent group (number of in_progress tasks).
# NOTE: This must be called from heartbeat.md context where TaskList is available.
# This is informational only — heartbeat.md implements the actual checking.

agent_wip_count() {
  local group="$1"
  # Placeholder: actual implementation in heartbeat.md via TaskList parsing
  echo "0"
}

# ───────────────────────────────────────────────────────────────────────────────
# agent_wip_limit <group>
# ───────────────────────────────────────────────────────────────────────────────
# Returns the configured WIP limit for the agent group.
# Returns empty string if no limit is configured.

agent_wip_limit() {
  local group="$1"
  $CONFIG "agents.wip_limits.${group}" "" 2>/dev/null || echo ""
}

# ───────────────────────────────────────────────────────────────────────────────
# Export functions for sourcing
# ───────────────────────────────────────────────────────────────────────────────

export -f agent_wip_check
export -f agent_wip_count
export -f agent_wip_limit
