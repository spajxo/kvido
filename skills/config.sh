#!/usr/bin/env bash
# =============================================================================
# config.sh — Unified config loader for assistant
# =============================================================================
# Usage: config.sh '<yq_expression>'
#   config.sh '.sources.gitlab.repos'
#   config.sh '.sources.gitlab.repos[] | select(.priority == "high") | .name'
#   config.sh '.skills.worker.task_timeout_minutes'
#
# Reads YAML frontmatter from kvido.local.md (per-project config).
# Validates config on first call per session (checks yq + YAML syntax).
# Exit codes:
#   0 — success
#   1 — yq not found
#   2 — invalid YAML / config not found
#   3 — invalid expression / yq error
# =============================================================================

set -euo pipefail

# PLUGIN_ROOT — directory where config.sh lives (e.g. <plugin>/skills)
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# CONFIG_FILE — kvido.local.md in project's .claude/ directory
CONFIG_FILE="${PWD}/.claude/kvido.local.md"

# ── Check arguments ──────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    echo "Usage: config.sh '<yq_expression>'" >&2
    echo "Example: config.sh '.sources.gitlab.repos[].name'" >&2
    exit 3
fi

EXPRESSION="$1"

# ── Check yq availability ───────────────────────────────────────────────────

YQ_BIN=""
if command -v yq &>/dev/null; then
    YQ_BIN="yq"
elif [[ -x "$HOME/.local/bin/yq" ]]; then
    YQ_BIN="$HOME/.local/bin/yq"
else
    echo "ERROR: yq not found. Install: https://github.com/mikefarah/yq#install" >&2
    echo "  wget -qO ~/.local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && chmod +x ~/.local/bin/yq" >&2
    exit 1
fi

# ── Check config file exists ────────────────────────────────────────────────

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    echo "  Expected at: $CONFIG_FILE" >&2
    echo "  Copy kvido.local.md.example from the plugin and fill in your data." >&2
    exit 2
fi

# ── Extract YAML frontmatter ────────────────────────────────────────────────

_extract_frontmatter() {
    awk '/^---$/{c++; next} c==1' "$CONFIG_FILE"
}

# ── Validate YAML (only on explicit --validate flag) ────────────────────────

if [[ "$EXPRESSION" == "--validate" ]]; then
    if _extract_frontmatter | $YQ_BIN eval '.' - >/dev/null 2>&1; then
        echo "OK: Config is valid YAML"
        exit 0
    else
        echo "ERROR: Invalid YAML frontmatter in $CONFIG_FILE" >&2
        _extract_frontmatter | $YQ_BIN eval '.' - 2>&1 | head -5 >&2
        exit 2
    fi
fi

# ── Execute yq expression ───────────────────────────────────────────────────

OUTPUT=$(_extract_frontmatter | $YQ_BIN eval "$EXPRESSION" - 2>&1) || {
    echo "ERROR: yq expression failed: $EXPRESSION" >&2
    echo "$OUTPUT" >&2
    exit 3
}

echo "$OUTPUT"
