#!/usr/bin/env bash
set -euo pipefail

# Discover installed kvido-* source plugins
# Reads ~/.claude/plugins/installed_plugins.json
# Expected schema: array of objects with .name (string) and .installPath (string)
#
# Usage:
#   discover-sources.sh                     → list all: "name\tinstall_path" per line
#   discover-sources.sh --check gitlab      → exit 0 if kvido-gitlab installed
#   discover-sources.sh --check kvido-gitlab → also accepted (kvido- prefix is normalized)

REGISTRY="$HOME/.claude/plugins/installed_plugins.json"
[[ -f "$REGISTRY" ]] || exit 0

if [[ "${1:-}" == "--check" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "Usage: discover-sources.sh --check <source-name>" >&2
    exit 1
  fi
  # Accept both "gitlab" and "kvido-gitlab"
  local_name="${2#kvido-}"
  jq -e --arg name "kvido-${local_name}" \
    '.[] | select(.name == $name) | .installPath' "$REGISTRY" >/dev/null 2>&1
  exit $?
fi

jq -r '.[] | select(.name | startswith("kvido-")) | select(.name != "kvido-assistant") | select(.installPath) | "\(.name)\t\(.installPath)"' \
  "$REGISTRY"
