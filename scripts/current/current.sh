#!/usr/bin/env bash
# current.sh — DEPRECATED: agents should use Read/Write/Edit tools directly
# with $KVIDO_HOME/memory/current.md
#
# All subcommands (get, dump, summary, set, append, clear) are deprecated.
# Use the Read tool to read $KVIDO_HOME/memory/current.md directly.
# Use the Write/Edit tools to modify it.

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"

cmd="${1:-}"

case "$cmd" in
  --help|-h)
    cat <<'HELP'
kvido current — DEPRECATED

All subcommands have been removed. Access memory/current.md directly:

  Read:   Read tool with $KVIDO_HOME/memory/current.md
  Write:  Write tool to $KVIDO_HOME/memory/current.md
  Edit:   Edit tool to modify sections in $KVIDO_HOME/memory/current.md
  List:   Glob tool with $KVIDO_HOME/memory/**/*.md

Note: 'get', 'dump', 'summary', 'set', 'append', 'clear' were removed —
use Read/Write/Edit tools with $KVIDO_HOME/memory/current.md
HELP
    ;;
  get|dump|summary)
    echo "DEPRECATED: 'kvido current $cmd' has been removed." >&2
    echo "Use the Read tool directly with path: \$KVIDO_HOME/memory/current.md" >&2
    exit 1
    ;;
  set|append|clear)
    echo "DEPRECATED: 'kvido current $cmd' has been removed." >&2
    echo "Use the Write/Edit tool directly with path: \$KVIDO_HOME/memory/current.md" >&2
    exit 1
    ;;
  *)
    echo "DEPRECATED: 'kvido current' has been removed." >&2
    echo "Use Read/Write/Edit tools directly with \$KVIDO_HOME/memory/current.md" >&2
    exit 1
    ;;
esac
