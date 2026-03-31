#!/usr/bin/env bash
# instructions.sh — Per-agent instruction file access
# Storage: $KVIDO_HOME/instructions/ (markdown files)
#
# Usage:
#   instructions.sh write <name>           → stdin → file (creates parent dirs)
#   instructions.sh list                   → list instruction files
#   instructions.sh tree                   → tree structure with absolute root path
#
# Note: 'read' subcommand removed — agents should use the Read tool directly
#       with path $KVIDO_HOME/instructions/<name>.md

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
INSTRUCTIONS_DIR="${KVIDO_HOME}/instructions"

# Resolve name → absolute path (auto-append .md if no extension)
# Rejects path traversal (.. components, absolute paths)
_resolve() {
  local name="$1"
  if [[ "$name" == /* || "$name" == *..* ]]; then
    echo "ERROR: invalid instruction name (path traversal): $name" >&2
    exit 1
  fi
  if [[ "$name" != *.* ]]; then
    name="${name}.md"
  fi
  echo "${INSTRUCTIONS_DIR}/${name}"
}

case "${1:-}" in
  --help|-h)
    cat <<'HELP'
kvido instructions — per-agent instruction file access

Usage: kvido instructions <subcommand> [args]

Subcommands:
  write <name>             Write stdin to instruction file (creates parent dirs)
  list                     List instruction files
  tree                     Show instruction directory structure

File names resolve to $KVIDO_HOME/instructions/<name>.md (auto-appends .md).
Path traversal (.. or absolute paths) is rejected.

Per-agent instructions are read by agents at startup. Users can customize
agent behavior by writing instruction files named after the agent
(e.g. `kvido instructions write worker`).

Note: 'read' subcommand was removed — agents read files directly via the Read tool
      with absolute path \$KVIDO_HOME/instructions/<name>.md

Examples:
  echo "Always use conventional commits" | kvido instructions write worker
  kvido instructions list
  kvido instructions tree
HELP
    exit 0
    ;;
  read)
    echo "DEPRECATED: 'kvido instructions read' has been removed." >&2
    echo "Use the Read tool directly with path: \$KVIDO_HOME/instructions/<name>.md" >&2
    exit 1
    ;;
  write)
    [[ -z "${2:-}" ]] && { echo "Usage: instructions.sh write <name>" >&2; exit 1; }
    FILE="$(_resolve "$2")"
    mkdir -p "$(dirname "$FILE")"
    cat > "$FILE"
    ;;
  list)
    if [[ ! -d "$INSTRUCTIONS_DIR" ]]; then
      echo "ERROR: instructions directory not found: $INSTRUCTIONS_DIR" >&2
      exit 1
    fi
    find "$INSTRUCTIONS_DIR" -name "*.md" | sort | while IFS= read -r filepath; do
      echo "${filepath#"${INSTRUCTIONS_DIR}/"}"
    done
    ;;
  tree)
    if [[ ! -d "$INSTRUCTIONS_DIR" ]]; then
      echo "ERROR: instructions directory not found: $INSTRUCTIONS_DIR" >&2
      exit 1
    fi
    if command -v tree &>/dev/null; then
      tree -F --noreport "$INSTRUCTIONS_DIR"
    else
      echo "${INSTRUCTIONS_DIR}/"
      (cd "$INSTRUCTIONS_DIR" && find . -not -name '.' | sort | while IFS= read -r path; do
        path="${path#./}"
        depth=$(echo "$path" | tr -cd '/' | wc -c)
        indent=""
        for ((i=0; i<depth; i++)); do indent+="    "; done
        name=$(basename "$path")
        if [[ -d "$INSTRUCTIONS_DIR/$path" ]]; then
          echo "${indent}${name}/"
        else
          echo "${indent}${name}"
        fi
      done)
    fi
    ;;
  *)
    cat >&2 <<USAGE
Usage: instructions.sh <command> [args]

Commands:
  write <name>             Write stdin to instruction file
  list                     List instruction files
  tree                     Show instruction directory structure

Note: 'read' was removed — use the Read tool with \$KVIDO_HOME/instructions/<name>.md

Run 'kvido instructions --help' for details.
USAGE
    exit 1
    ;;
esac
