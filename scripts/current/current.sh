#!/usr/bin/env bash
# current.sh — read/write state/current.md with section-level operations
set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_FILE="${KVIDO_HOME}/state/current.md"

# --- helpers ---

_ensure_file() {
  mkdir -p "$(dirname "$STATE_FILE")"
  [[ -f "$STATE_FILE" ]] || touch "$STATE_FILE"
}

_normalize() {
  # slug: replace - with space, lowercase
  echo "${1//-/ }" | tr '[:upper:]' '[:lower:]'
}

_normalize_header() {
  # strip "## " prefix, trim at first " — ", " -- ", or " ("
  local h="${1#\#\# }"
  h="${h%% — *}"
  h="${h%% -- *}"
  h="${h%% (*}"
  echo "$h" | tr '[:upper:]' '[:lower:]'
}

_find_section() {
  # Returns 1-based line number of matching ## header, or exit 1
  local slug
  slug="$(_normalize "$1")"
  local line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ "$line" == "## "* ]]; then
      local normalized
      normalized="$(_normalize_header "$line")"
      if [[ "$normalized" == "$slug" ]]; then
        echo "$line_num"
        return 0
      fi
    fi
  done < "$STATE_FILE"
  return 1
}

_get_section() {
  # Print lines from header_line+1 to next ## or EOF
  local start="$1"
  local from=$((start + 1))
  local line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ $line_num -lt $from ]]; then
      continue
    fi
    if [[ "$line" == "## "* ]]; then
      break
    fi
    echo "$line"
  done < "$STATE_FILE"
}

_replace_section() {
  # Replace section body (between header and next ## / EOF) with new content
  local start="$1"
  local content="$2"
  _ensure_file
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  local line_num=0
  local skipping=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ $line_num -eq $start ]]; then
      echo "$line" >> "$tmp"  # preserve header
      if [[ -n "$content" ]]; then
        printf '%b\n' "$content" >> "$tmp"
      fi
      skipping=true
      continue
    fi
    if $skipping; then
      if [[ "$line" == "## "* ]]; then
        # Ensure blank line before next section
        echo "" >> "$tmp"
        skipping=false
        echo "$line" >> "$tmp"
      fi
      continue
    fi
    echo "$line" >> "$tmp"
  done < "$STATE_FILE"
  mv "$tmp" "$STATE_FILE"
}

_append_to_section() {
  # Append a line to the end of a section
  local start="$1"
  local text="$2"
  _ensure_file
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  local line_num=0
  local in_section=false
  local last_content_line=0
  local total
  total=$(wc -l < "$STATE_FILE")

  # First pass: find the last non-blank line in the section
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ $line_num -eq $start ]]; then
      in_section=true
      continue
    fi
    if $in_section; then
      if [[ "$line" == "## "* ]]; then
        break
      fi
      if [[ -n "$line" ]]; then
        last_content_line=$line_num
      fi
    fi
  done < "$STATE_FILE"

  # If section body is empty, insert right after header
  if [[ $last_content_line -eq 0 ]]; then
    last_content_line=$start
  fi

  # Second pass: write with insertion
  line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    echo "$line" >> "$tmp"
    if [[ $line_num -eq $last_content_line ]]; then
      printf '%b\n' "$text" >> "$tmp"
    fi
  done < "$STATE_FILE"

  mv "$tmp" "$STATE_FILE"
}

_slug_to_header() {
  # Convert slug to display header: resolved-today → Resolved Today, wip → WIP
  local slug="$1"
  local result=""
  for word in ${slug//-/ }; do
    if [[ ${#word} -le 4 ]] && [[ "$word" =~ ^[a-zA-Z]+$ ]]; then
      word=$(echo "$word" | tr '[:lower:]' '[:upper:]')
    else
      word="$(echo "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}"
    fi
    result="${result:+$result }$word"
  done
  echo "$result"
}

_create_section() {
  # Append a new section at end of file
  local slug="$1"
  local content="${2:-}"
  _ensure_file
  local header
  header="$(_slug_to_header "$slug")"
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  cat "$STATE_FILE" > "$tmp"
  # Ensure trailing newline before new section
  [[ -s "$STATE_FILE" ]] && echo "" >> "$tmp"
  echo "## $header" >> "$tmp"
  if [[ -n "$content" ]]; then
    printf '%b\n' "$content" >> "$tmp"
  fi
  mv "$tmp" "$STATE_FILE"
}

# --- argument parsing ---

_parse_section_flag() {
  # Parse --section <slug> from args, set SECTION and ARGS
  SECTION=""
  ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --section)
        [[ $# -lt 2 ]] && { echo "Error: --section requires a value" >&2; exit 1; }
        SECTION="$2"
        shift 2
        ;;
      *)
        ARGS+=("$1")
        shift
        ;;
    esac
  done
}

# --- commands ---

cmd="${1:-}"
[[ -n "$cmd" ]] && shift

case "$cmd" in
  get)
    _parse_section_flag "$@"
    if [[ -z "$SECTION" ]]; then
      # Backwards compatible: dump full file
      if [[ ! -f "$STATE_FILE" ]]; then
        echo "Error: state not initialized. Run: kvido setup" >&2
        exit 1
      fi
      cat "$STATE_FILE"
    else
      if [[ ! -f "$STATE_FILE" ]]; then
        echo "Error: state not initialized. Run: kvido setup" >&2
        exit 1
      fi
      line=$(_find_section "$SECTION") || { echo "Error: section '$SECTION' not found" >&2; exit 1; }
      _get_section "$line"
    fi
    ;;

  dump)
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE"
    ;;

  set)
    _parse_section_flag "$@"
    if [[ -z "$SECTION" ]]; then
      # Backwards compatible: overwrite from stdin
      mkdir -p "$(dirname "$STATE_FILE")"
      tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
      cat > "$tmp"
      mv "$tmp" "$STATE_FILE"
    else
      _ensure_file
      # Content from positional args or stdin
      if [[ ${#ARGS[@]} -gt 0 ]]; then
        content="${ARGS[*]}"
      else
        content="$(cat)"
      fi
      if line=$(_find_section "$SECTION" 2>/dev/null); then
        _replace_section "$line" "$content"
      else
        _create_section "$SECTION" "$content"
      fi
    fi
    ;;

  append)
    _parse_section_flag "$@"
    [[ -z "$SECTION" ]] && { echo "Error: append requires --section <name>" >&2; exit 1; }
    [[ ${#ARGS[@]} -eq 0 ]] && { echo "Error: append requires text argument" >&2; exit 1; }
    text="${ARGS[*]}"
    _ensure_file
    if line=$(_find_section "$SECTION" 2>/dev/null); then
      _append_to_section "$line" "$text"
    else
      _create_section "$SECTION" "$text"
    fi
    ;;

  clear)
    _parse_section_flag "$@"
    [[ -z "$SECTION" ]] && { echo "Error: clear requires --section <name>" >&2; exit 1; }
    [[ -f "$STATE_FILE" ]] || exit 0
    if line=$(_find_section "$SECTION" 2>/dev/null); then
      _replace_section "$line" ""
    fi
    # Section not found = no-op
    ;;

  *)
    cat >&2 <<'USAGE'
Usage: current.sh <command> [options]

Commands:
  get [--section <name>]             Read full file or a specific section
  dump                               Read full file (alias for get)
  set [--section <name>] [content]   Write full file (stdin) or a section
  append --section <name> <text>     Append a line to a section
  clear --section <name>             Clear a section's content (keep header)

Section names use slugs: wip, resolved-today, active-focus, pinned-today, triage
USAGE
    exit 1
    ;;
esac
