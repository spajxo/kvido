#!/usr/bin/env bash
# memory.sh — Memory file access for agents and scripts
# Storage: $KVIDO_HOME/memory/ (markdown files)
#
# Usage:
#   memory.sh read <name>       → cat file to stdout (exit 1 if missing)
#   memory.sh write <name>      → stdin → file (creates parent dirs)
#   memory.sh tree              → tree structure with absolute root path

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
MEMORY_DIR="${KVIDO_HOME}/memory"

# Resolve name → absolute path (auto-append .md if no extension)
# Rejects path traversal (.. components, absolute paths)
_resolve() {
  local name="$1"
  if [[ "$name" == /* || "$name" == *..* ]]; then
    echo "ERROR: invalid memory name (path traversal): $name" >&2
    exit 1
  fi
  if [[ "$name" != *.* ]]; then
    name="${name}.md"
  fi
  echo "${MEMORY_DIR}/${name}"
}

case "${1:-}" in
  read)
    [[ -z "${2:-}" ]] && { echo "Usage: memory.sh read <name>" >&2; exit 1; }
    FILE="$(_resolve "$2")"
    if [[ ! -f "$FILE" ]]; then
      echo "ERROR: memory file not found: $FILE" >&2
      exit 1
    fi
    cat "$FILE"
    ;;
  write)
    [[ -z "${2:-}" ]] && { echo "Usage: memory.sh write <name>" >&2; exit 1; }
    FILE="$(_resolve "$2")"
    mkdir -p "$(dirname "$FILE")"
    cat > "$FILE"
    ;;
  tree)
    if [[ ! -d "$MEMORY_DIR" ]]; then
      echo "ERROR: memory directory not found: $MEMORY_DIR" >&2
      exit 1
    fi
    if command -v tree &>/dev/null; then
      tree -F --noreport "$MEMORY_DIR"
    else
      # Fallback: find-based tree
      echo "${MEMORY_DIR}/"
      (cd "$MEMORY_DIR" && find . -not -name '.' | sort | while IFS= read -r path; do
        path="${path#./}"
        depth=$(echo "$path" | tr -cd '/' | wc -c)
        indent=""
        for ((i=0; i<depth; i++)); do indent+="    "; done
        name=$(basename "$path")
        if [[ -d "$MEMORY_DIR/$path" ]]; then
          echo "${indent}${name}/"
        else
          echo "${indent}${name}"
        fi
      done)
    fi
    ;;
  *)
    cat >&2 <<USAGE
Usage: memory.sh <command> [args]

Commands:
  read <name>     Read memory file to stdout
  write <name>    Write stdin to memory file
  tree            Show memory directory structure
USAGE
    exit 1
    ;;
esac
