#!/usr/bin/env bash
set -euo pipefail

# Discover installed kvido-* source plugins
# Reads ~/.claude/plugins/installed_plugins.json
# Supports both registry schemas:
#   - v2: {version: N, plugins: {"name@registry": [{installPath, ...}], ...}}
#   - legacy: [{name, installPath, ...}, ...]
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
    'if type == "object" and has("plugins") then
       .plugins
       | to_entries[]
       | select(.key | split("@")[0] == $name)
       | .value[0].installPath
     elif type == "array" then
       .[]
       | select(.name == $name)
       | .installPath
     else
       empty
     end' \
    "$REGISTRY" >/dev/null 2>&1
  exit $?
fi

jq -r 'if type == "object" and has("plugins") then
    .plugins
    | to_entries[]
    | select(.key | split("@")[0] | startswith("kvido-"))
    | select(.value[0].installPath)
    | "\(.key | split("@")[0])\t\(.value[0].installPath)"
  elif type == "array" then
    .[]
    | select(.name | startswith("kvido-"))
    | select(.installPath)
    | "\(.name)\t\(.installPath)"
  else
    empty
  end' \
  "$REGISTRY"
