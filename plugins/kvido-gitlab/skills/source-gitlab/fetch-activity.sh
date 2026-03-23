#!/usr/bin/env bash
# fetch-activity.sh — aggregate git activity across monitored repos for a given day
#
# Usage: fetch-activity.sh [YYYY-MM-DD] [--priority high|normal|low]
# Reads repos from central settings.json via config.sh
# Output: plain text summary of git activity per repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"

DATE=""
PRIORITY_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --priority) PRIORITY_FILTER="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) DATE="$1"; shift ;;
  esac
done

DATE="${DATE:-$(date +%Y-%m-%d)}"
SINCE="${DATE} 00:00:00"
UNTIL="${DATE} 23:59:59"

AUTHOR_NAME="$(git config user.name)"

process_repo() {
  local name="$1"
  local path="$2"
  local priority="$3"

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

  # My commits on this day
  mapfile -t my_commits < <(
    git -C "$path" log --all \
      --since="$SINCE" --until="$UNTIL" \
      --author="$AUTHOR_NAME" \
      --format="  - %s (%h)" 2>/dev/null
  )

  # Others' commits count
  others_count=$(
    git -C "$path" log --all \
      --since="$SINCE" --until="$UNTIL" \
      --invert-grep --author="$AUTHOR_NAME" \
      --oneline 2>/dev/null | wc -l
  )

  # Active branches touched on this day
  mapfile -t branches_raw < <(
    git -C "$path" log --all \
      --since="$SINCE" --until="$UNTIL" \
      --format="%D" 2>/dev/null
  )

  declare -A seen_branches=()
  branch_list=()
  for decoration in "${branches_raw[@]}"; do
    IFS=',' read -ra parts <<< "$decoration"
    for part in "${parts[@]}"; do
      part="${part#"${part%%[! ]*}"}"
      part="${part%"${part##*[! ]}"}"
      [[ -z "$part" ]] && continue
      [[ "$part" == HEAD* ]] && continue
      [[ "$part" == origin/* ]] && continue
      [[ "$part" == tag:* ]] && continue
      part="${part#origin/}"
      if [[ -z "${seen_branches[$part]+_}" ]]; then
        seen_branches[$part]=1
        branch_list+=("$part")
      fi
    done
  done

  has_my_commits="${#my_commits[@]}"
  if [[ "$has_my_commits" -eq 0 && "$others_count" -eq 0 ]]; then
    return
  fi

  echo "=== $name ==="

  echo "My commits:"
  if [[ "$has_my_commits" -gt 0 ]]; then
    for commit in "${my_commits[@]}"; do
      echo "$commit"
    done
  else
    echo "  (none)"
  fi

  echo "Others: $others_count commits"

  if [[ "${#branch_list[@]}" -gt 0 ]]; then
    branches_str=$(IFS=', '; echo "${branch_list[*]}")
    echo "Branches: $branches_str"
  else
    echo "Branches: (none)"
  fi

  echo ""
}

# Parse repos from central settings.json via config.sh
for repo_key in $($CONFIG --keys 'sources.gitlab.repos'); do
  repo_path=$($CONFIG "sources.gitlab.repos.${repo_key}.path")
  repo_priority=$($CONFIG "sources.gitlab.repos.${repo_key}.priority" "normal")
  process_repo "$repo_key" "$repo_path" "$repo_priority"
done
