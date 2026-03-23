#!/usr/bin/env bash
# =============================================================================
# config.sh — Unified config loader for assistant (jq wrapper)
# =============================================================================
# Usage: config.sh 'key'
#   config.sh 'sources.gitlab.repos.group-project.path'
#   config.sh 'skills.worker.task_timeout_minutes'
#   config.sh 'skills.dashboard.enabled' 'true'    # with default
#   config.sh --keys 'sources.gitlab.repos'         # list child keys
#   config.sh --validate                            # check config format
#
# Reads KVIDO_HOME/settings.json (standard JSON via jq).
# Dot-notation keys map to nested JSON paths: 'a.b.c' → .a.b.c
#
# Exit codes:
#   0 — success
#   1 — config file not found
#   2 — invalid config format (not valid JSON)
#   3 — key not found (no default provided)
# =============================================================================

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
CONFIG_FILE="${KVIDO_HOME}/settings.json"

# ── Dot-notation → jq path ───────────────────────────────────────────────────
# Converts 'a.b.c' to '.a.b.c' for use with jq.
# Keys that are numeric stay as object keys (jq handles them as string keys).

_dot_to_jq() {
    local key="$1"
    # Split on dots and reassemble as .key1.key2... with proper quoting for
    # keys that contain hyphens or start with digits.
    local jq_path="."
    IFS='.' read -ra parts <<< "$key"
    for part in "${parts[@]}"; do
        jq_path="${jq_path}[\"${part}\"]"
    done
    echo "$jq_path"
}

# ── Scalar lookup ─────────────────────────────────────────────────────────────

_get_value() {
    local key="$1"
    local default="${2:-}"
    local has_default="${3:-false}"

    local jq_path
    jq_path="$(_dot_to_jq "$key")"

    local result
    result=$(jq -r "if ${jq_path} == null then empty else (${jq_path} | tostring) end" "$CONFIG_FILE" 2>/dev/null) || {
        echo "ERROR: Failed to parse config file: $CONFIG_FILE" >&2
        return 2
    }

    if [[ -z "$result" ]]; then
        if [[ "$has_default" == "true" ]]; then
            echo "$default"
            return 0
        fi
        echo "ERROR: Key not found: $key" >&2
        return 3
    fi

    echo "$result"
}

# ── Prefix key listing ────────────────────────────────────────────────────────
# Lists immediate child keys under a given dot-notation prefix.

_list_keys() {
    local prefix="$1"
    local jq_path
    jq_path="$(_dot_to_jq "$prefix")"

    local raw
    raw=$(jq -r "${jq_path} | if type == \"object\" then keys_unsorted[] else empty end" \
        "$CONFIG_FILE" 2>/dev/null) || {
        echo "ERROR: Failed to list keys from config file: $CONFIG_FILE" >&2
        return 2
    }
    echo "$raw" | grep -v '^_' || true
}

# ── Validate ──────────────────────────────────────────────────────────────────

_validate() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: Config file not found: $CONFIG_FILE" >&2
        return 1
    fi

    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo "ERROR: Invalid JSON in config file: $CONFIG_FILE" >&2
        return 2
    fi

    echo "OK: Config is valid ($(jq 'keys | length' "$CONFIG_FILE") top-level keys)"
}

# ── Check config file ────────────────────────────────────────────────────────

if [[ "${1:-}" != "--validate" && ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    echo "  Expected at: $CONFIG_FILE" >&2
    echo "  Copy settings.json.example from the plugin and fill in your data." >&2
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
