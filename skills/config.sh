#!/usr/bin/env bash
# =============================================================================
# config.sh — Unified config loader for assistant
# =============================================================================
# Usage: config.sh 'key'
#   config.sh 'sources.gitlab.repos.group-project.path'
#   config.sh 'skills.worker.task_timeout_minutes'
#   config.sh 'skills.dashboard.enabled' 'true'    # with default
#   config.sh --keys 'sources.gitlab.repos'         # list child keys
#   config.sh --validate                            # check config format
#
# Reads flat dot-notation YAML frontmatter from kvido.local.md.
# Exit codes:
#   0 — success
#   1 — config not found
#   2 — invalid config format
#   3 — key not found (no default provided)
# =============================================================================

set -euo pipefail

# CONFIG_FILE — kvido.local.md in project's .claude/ directory
CONFIG_FILE="${PWD}/.claude/kvido.local.md"

# ── Extract frontmatter ──────────────────────────────────────────────────────

_extract_frontmatter() {
    awk '/^---$/{c++; next} c==1' "$CONFIG_FILE"
}

# ── Scalar lookup ─────────────────────────────────────────────────────────────

_get_value() {
    local key="$1" default="${2:-}"
    local has_default="${3:-false}"
    local result
    result=$(_extract_frontmatter | awk -v k="$key" '
        {
            # Match key at start of line followed by ": "
            if (index($0, k ": ") == 1) {
                print substr($0, length(k) + 3)
                found = 1
                exit
            }
        }
        END { if (!found) exit 1 }
    ') || {
        if [[ "$has_default" == "true" ]]; then
            echo "$default"
            return 0
        fi
        return 3
    }
    # Strip surrounding double quotes
    if [[ "${result:0:1}" == '"' && "${result: -1}" == '"' ]]; then
        result="${result:1:${#result}-2}"
    fi
    echo "$result"
}

# ── Prefix key listing ────────────────────────────────────────────────────────

_list_keys() {
    local prefix="$1"
    _extract_frontmatter | awk -v p="$prefix." '
        substr($0, 1, length(p)) == p {
            rest = substr($0, length(p) + 1)
            sub(/:.*/, "", rest)
            sub(/\..*/, "", rest)
            if (rest != "" && !(rest in seen)) { seen[rest] = 1; print rest }
        }'
}

# ── Validate ──────────────────────────────────────────────────────────────────

_validate() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: Config file not found: $CONFIG_FILE" >&2
        return 1
    fi

    local errors=0
    local line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Each line must be "key: value"
        if [[ ! "$line" =~ ^[a-zA-Z0-9._-]+:\ .+ ]]; then
            echo "ERROR: Invalid line $line_num: $line" >&2
            errors=$((errors + 1))
        fi
    done < <(_extract_frontmatter)

    if [[ $errors -gt 0 ]]; then
        echo "ERROR: $errors invalid lines in config" >&2
        return 2
    fi
    echo "OK: Config is valid"
}

# ── Check config file ────────────────────────────────────────────────────────

if [[ "${1:-}" != "--validate" && ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    echo "  Expected at: $CONFIG_FILE" >&2
    echo "  Copy kvido.local.md.example from the plugin and fill in your data." >&2
    exit 1
fi

# ── Main ──────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --validate)
        _validate
        ;;
    --keys)
        [[ -z "${2:-}" ]] && { echo "Usage: config.sh --keys 'prefix'" >&2; exit 3; }
        _list_keys "$2"
        ;;
    "")
        echo "Usage: config.sh 'key' [default]" >&2
        echo "       config.sh --keys 'prefix'" >&2
        echo "       config.sh --validate" >&2
        exit 3
        ;;
    *)
        if [[ $# -ge 2 ]]; then
            _get_value "$1" "$2" "true"
        else
            _get_value "$1" "" "false"
        fi
        ;;
esac
