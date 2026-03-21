#!/usr/bin/env bash
# fetch.sh — aggregate Jira issues across monitored projects
#
# Usage: fetch.sh [--since YYYY-MM-DD] [--project KEY]
# Reads projects from central kvido.local.md via config.sh
# Output: plain text summary of open issues per project
#
# --since: only show issues updated since given date (optional)
# --project: only process the given project key (optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"

if ! command -v acli &>/dev/null; then
  echo "ERROR: acli not installed" >&2
  exit 1
fi

SINCE=""
PROJECT_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --project) PROJECT_FILTER="$2"; shift 2 ;;
    *) echo "Usage: fetch.sh [--since YYYY-MM-DD] [--project KEY]" >&2; exit 1 ;;
  esac
done

# Parse projects from central kvido.local.md via config.sh
projects=()
labels=()
jql_filters=()
for proj_key in $($CONFIG --keys 'sources.jira.projects'); do
  projects+=("$proj_key")
  labels+=("$($CONFIG "sources.jira.projects.${proj_key}.label" "$proj_key")")
  jql_filters+=("$($CONFIG "sources.jira.projects.${proj_key}.filter")")
done

if [[ ${#projects[@]} -eq 0 ]]; then
  echo "ERROR: no projects found in config" >&2
  exit 1
fi

for i in "${!projects[@]}"; do
  key="${projects[$i]}"
  display="${labels[$i]}"
  jql="${jql_filters[$i]}"

  # Apply project filter if specified
  if [[ -n "$PROJECT_FILTER" && "$key" != "$PROJECT_FILTER" ]]; then
    continue
  fi

  # Scope JQL to project if not already scoped (skip for parentEpic queries)
  if [[ ! "$jql" =~ project[[:space:]]*= ]] && [[ ! "$jql" =~ parentEpic ]]; then
    jql="project = $key AND $jql"
  fi

  # Append since filter if provided (insert before ORDER BY if present)
  if [[ -n "$SINCE" ]]; then
    if [[ "$jql" =~ (.+)(ORDER[[:space:]]+BY.+) ]]; then
      jql="${BASH_REMATCH[1]} AND updated >= \"$SINCE\" ${BASH_REMATCH[2]}"
    else
      jql="$jql AND updated >= \"$SINCE\""
    fi
  fi

  output=$(acli jira workitem search --jql "$jql" --fields "key,summary,status,priority" --limit 20 --csv 2>&1) || {
    echo "=== $key ==="
    echo "  ERROR: acli failed — $output"
    echo ""
    continue
  }

  # Skip header, count lines
  count=$(echo "$output" | tail -n +2 | grep -c . || true)

  if [[ "$count" -eq 0 ]]; then
    continue
  fi

  echo "=== $display ($count issues) ==="
  # CSV header: Key,Priority,Status,Summary (summary may contain commas)
  echo "$output" | tail -n +2 | while IFS=',' read -r issue_key priority status summary_rest; do
    echo "  $issue_key [$status] $summary_rest"
  done
  echo ""
done
