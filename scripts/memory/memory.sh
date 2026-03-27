#!/usr/bin/env bash
# memory.sh — Memory file access for agents and scripts
# Storage: $KVIDO_HOME/memory/ (markdown files)
#
# Usage:
#   memory.sh read <name>            → cat file to stdout (exit 1 if missing)
#   memory.sh write <name>           → stdin → file (creates parent dirs)
#   memory.sh tree                   → tree structure with absolute root path
#   memory.sh search <query>         → grep all .md files for query, show matches
#   memory.sh list [--type <type>]   → list memory files, optionally filter by frontmatter type

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
  --help|-h)
    cat <<'HELP'
kvido memory — persistent memory file access

Usage: kvido memory <subcommand> [args]

Subcommands:
  read <name>              Print memory file to stdout (exit 1 if missing)
  write <name>             Write stdin to memory file (creates parent dirs)
  tree                     Show memory directory structure
  search <query>           Search all memory files for query (grep, case-insensitive)
  list [--type <type>]     List memory files; filter by frontmatter type field
                           Known types: user, feedback, project, reference

File names resolve to $KVIDO_HOME/memory/<name>.md (auto-appends .md).
Path traversal (.. or absolute paths) is rejected.

Examples:
  kvido memory read persona
  echo "new content" | kvido memory write notes
  kvido memory tree
  kvido memory search "gitlab"
  kvido memory list
  kvido memory list --type feedback
HELP
    exit 0
    ;;
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
  search)
    [[ -z "${2:-}" ]] && { echo "Usage: memory.sh search <query>" >&2; exit 1; }
    QUERY="$2"
    if [[ ! -d "$MEMORY_DIR" ]]; then
      echo "ERROR: memory directory not found: $MEMORY_DIR" >&2
      exit 1
    fi
    # grep -r: recursive, -i: case-insensitive, -n: line numbers, --include: only .md files
    # Output format: relative-filename:line-number:matching-line
    RESULTS=$(grep -r -i -n -F --include="*.md" -- "$QUERY" "$MEMORY_DIR" 2>/dev/null || true)
    if [[ -z "$RESULTS" ]]; then
      echo "No matches found for: $QUERY" >&2
      exit 0
    fi
    # Print results with relative paths (strip MEMORY_DIR prefix)
    while IFS= read -r line; do
      # Replace absolute MEMORY_DIR prefix with relative path
      echo "${line#"${MEMORY_DIR}/"}"
    done <<< "$RESULTS"
    ;;
  list)
    if [[ ! -d "$MEMORY_DIR" ]]; then
      echo "ERROR: memory directory not found: $MEMORY_DIR" >&2
      exit 1
    fi
    FILTER_TYPE=""
    # Parse optional --type flag
    shift  # remove "list"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)
          [[ -z "${2:-}" ]] && { echo "Usage: memory.sh list [--type <type>]" >&2; exit 1; }
          FILTER_TYPE="$2"
          shift 2
          ;;
        *)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
      esac
    done
    # Find all .md files, print relative paths
    while IFS= read -r filepath; do
      relpath="${filepath#"${MEMORY_DIR}/"}"
      if [[ -n "$FILTER_TYPE" ]]; then
        # Extract type from YAML frontmatter (read until closing ---)
        file_type=$(awk '/^---$/{found++; next} found>=2{exit} found==1 && /^type:/{gsub(/^type:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit}' "$filepath")
        [[ "$file_type" == "$FILTER_TYPE" ]] || continue
      fi
      echo "$relpath"
    done < <(find "$MEMORY_DIR" -name "*.md" | sort)
    ;;
  *)
    cat >&2 <<USAGE
Usage: memory.sh <command> [args]

Commands:
  read <name>              Read memory file to stdout
  write <name>             Write stdin to memory file
  tree                     Show memory directory structure
  search <query>           Search all memory files for query
  list [--type <type>]     List memory files, optionally filter by frontmatter type

Run 'kvido memory --help' for details.
USAGE
    exit 1
    ;;
esac
