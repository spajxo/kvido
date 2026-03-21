#!/usr/bin/env bash
# fetch-mrs.sh — aggregate open MR status across monitored repos
#
# Usage: fetch-mrs.sh [--priority high|normal|low]
# Reads repos from centrální kvido.local.md via config.sh
# Output: plain text summary of open MRs (authored + reviewing) with CI status
#
# Note: must cd into each repo for glab to work (glab uses git remote context)
# Repos with type: knowledge-base are always skipped

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"

PRIORITY_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --priority) PRIORITY_FILTER="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) echo "Usage: fetch-mrs.sh [--priority high|normal|low]" >&2; exit 1 ;;
  esac
done

process_repo() {
  local name="$1"
  local path="$2"
  local priority="$3"
  local type="$4"

  # Skip knowledge-base repos
  if [[ "$type" == "knowledge-base" ]]; then
    return
  fi

  # Apply priority filter if specified
  if [[ -n "$PRIORITY_FILTER" && "$priority" != "$PRIORITY_FILTER" ]]; then
    return
  fi

  # Trim inline comments and whitespace from path
  path="${path%%#*}"
  path="${path%"${path##*[! ]}"}"
  # Expand ~ to $HOME
  path="${path/#\~/$HOME}"

  if [[ ! -d "$path/.git" ]]; then
    return
  fi

  # Check if repo has a GitLab remote
  if ! git -C "$path" remote get-url origin 2>/dev/null | grep -q 'git\.digital\.cz\|gitlab'; then
    return
  fi

  # glab needs to run from inside the repo
  authored=$(cd "$path" && glab mr list --author=@me --output json 2>/dev/null || echo "[]")
  reviewing=$(cd "$path" && glab mr list --reviewer=@me --output json 2>/dev/null || echo "[]")

  authored_count=$(echo "$authored" | jq 'length' 2>/dev/null || echo 0)
  reviewing_count=$(echo "$reviewing" | jq 'length' 2>/dev/null || echo 0)

  if [[ "$authored_count" -eq 0 && "$reviewing_count" -eq 0 ]]; then
    return
  fi

  echo "=== $name ==="

  if [[ "$authored_count" -gt 0 ]]; then
    echo "My MRs:"
    echo "$authored" | jq -r '.[] | "  !\(.iid): \(if .draft then "DRAFT " else "" end)\(.title) [CI: \((.head_pipeline // {}).status // "no pipeline"), \(if .approved then "approved" elif (.reviewers // []) | length > 0 then "\(.reviewers | length) reviewer(s)" else "no reviewers" end)]"' 2>/dev/null || true
  fi

  if [[ "$reviewing_count" -gt 0 ]]; then
    echo "Reviewing:"
    echo "$reviewing" | jq -r '.[] | "  !\(.iid): \(.title) (by \((.author // {}).username // "?")) [CI: \((.head_pipeline // {}).status // "no pipeline")]"' 2>/dev/null || true
  fi

  echo ""
}

# Parse repos from centrální kvido.local.md via config.sh
while IFS=$'\t' read -r repo_name repo_path repo_priority repo_type; do
  process_repo "$repo_name" "$repo_path" "${repo_priority:-normal}" "${repo_type:-}"
done < <($CONFIG '.sources.gitlab.repos[] | [.name, .path, .priority // "normal", .type // ""] | @tsv')
