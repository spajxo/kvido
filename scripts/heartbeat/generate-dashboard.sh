#!/usr/bin/env bash
# generate-dashboard.sh — Generates state/dashboard.html from assistant state files.
# Called from heartbeat.sh. Must never fail fatally (heartbeat logs errors to stderr).
#
# Data sources:
#   1. kvido log list (unified activity log)
#   2. kvido state (heartbeat.* keys)
#   3. memory/current.md
#   4. tasks/ (local task files)
#   5. tasks/*/*.md (full task data for task list/detail view)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$PLUGIN_ROOT/bin/kvido-config"
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
STATE_DIR="${KVIDO_HOME}/state"
OUTPUT="$STATE_DIR/dashboard.html"

# Check if dashboard is enabled
DASHBOARD_ENABLED=$($CONFIG 'dashboard.enabled' 'true')
if [[ "$DASHBOARD_ENABLED" == "false" ]]; then
  exit 0
fi

AUTO_REFRESH=$($CONFIG 'dashboard.auto_refresh' '20')
NOW=$(date -Iseconds)
TODAY=$(date -I)
WARNINGS=()

# ---------------------------------------------------------------------------
# Source 1: kvido log (unified activity log)
# ---------------------------------------------------------------------------
LOG_SH="$PLUGIN_ROOT/bin/kvido-log"
TIMELINE_JSON="[]"
TOKEN_STATS_JSON="[]"
TOTAL_TOKENS=0
TOTAL_RUNS=0

TIMELINE_JSON=$(bash "$LOG_SH" list --today --format json --limit 50 2>/dev/null) || { WARNINGS+=("kvido log list: parse error"); TIMELINE_JSON="[]"; }
TOKEN_STATS_JSON=$(bash "$LOG_SH" list --today --summary --format json 2>/dev/null) || { WARNINGS+=("kvido log list: stats error"); TOKEN_STATS_JSON="[]"; }

TOTAL_TOKENS=$(echo "$TOKEN_STATS_JSON" | jq '[.[].tokens] | add // 0' 2>/dev/null || echo 0)
TOTAL_RUNS=$(echo "$TOKEN_STATS_JSON" | jq '[.[].runs] | add // 0' 2>/dev/null || echo 0)

# ---------------------------------------------------------------------------
# Source 2: heartbeat state (via kvido state CLI)
# ---------------------------------------------------------------------------
ITERATION=0
ACTIVE_PRESET="?"
LAST_HEARTBEAT=""
SLEEP_UNTIL=""
TURBO_UNTIL=""
INTERACTION_AGO="?"

ITERATION=$(kvido state get heartbeat.iteration_count 2>/dev/null || echo 0)
ACTIVE_PRESET=$(kvido state get heartbeat.active_preset 2>/dev/null || echo "?")
LAST_HEARTBEAT=$(kvido state get heartbeat.last_heartbeat 2>/dev/null || kvido state get heartbeat.last_quick 2>/dev/null || echo "")
SLEEP_UNTIL=$(kvido state get heartbeat.sleep_until 2>/dev/null || echo "")
TURBO_UNTIL=$(kvido state get heartbeat.turbo_until 2>/dev/null || echo "")

LAST_INTERACTION_TS=$(kvido state get heartbeat.last_interaction_ts 2>/dev/null || echo "")
if [[ -n "$LAST_INTERACTION_TS" && "$LAST_INTERACTION_TS" != "null" ]]; then
  INTERACTION_S=$(date -d "$LAST_INTERACTION_TS" +%s 2>/dev/null || echo 0)
  NOW_S=$(date +%s)
  INTERACTION_AGO="$(( (NOW_S - INTERACTION_S) / 60 ))m"
fi

# Determine zone
ZONE="unknown"
NOW_S=$(date +%s)
if [[ -n "$SLEEP_UNTIL" && "$SLEEP_UNTIL" != "null" && "$SLEEP_UNTIL" != "" ]]; then
  SLEEP_S=$(date -d "$SLEEP_UNTIL" +%s 2>/dev/null || echo 0)
  if (( SLEEP_S > NOW_S )); then ZONE="sleep"; fi
fi
if [[ "$ZONE" == "unknown" && -n "$TURBO_UNTIL" && "$TURBO_UNTIL" != "null" && "$TURBO_UNTIL" != "" ]]; then
  TURBO_S=$(date -d "$TURBO_UNTIL" +%s 2>/dev/null || echo 0)
  if (( TURBO_S > NOW_S )); then ZONE="turbo"; fi
fi
if [[ "$ZONE" == "unknown" ]]; then
  HOUR=$(date +%-H)
  DOW=$(date +%u)
  if (( DOW >= 1 && DOW <= 5 && HOUR >= 7 && HOUR < 16 )); then
    ZONE="working"
  else
    ZONE="off-hours"
  fi
fi

# ---------------------------------------------------------------------------
# _html_escape helper (defined before use in _extract_section)
# ---------------------------------------------------------------------------
_html_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# ---------------------------------------------------------------------------
# Source 3: current.md (full content, rendered as structured HTML)
# ---------------------------------------------------------------------------
CURRENT_FILE="$KVIDO_HOME/memory/current.md"
CURRENT_HTML=""

if [[ -f "$CURRENT_FILE" ]]; then
  # Convert markdown to structured HTML sections
  CURRENT_HTML=$(awk '
    BEGIN { in_section=0; has_content=0; buf=""; in_table=0; table_buf="" }
    /^# / { next }
    /^### / {
      if (in_table) {
        buf = buf "</table>\n"
        in_table=0
      }
      if (in_section && has_content) buf = buf "\n"
      title = substr($0, 5)
      gsub(/&/, "\\&amp;", title); gsub(/</, "\\&lt;", title); gsub(/>/, "\\&gt;", title)
      buf = buf "<h3>" title "</h3>"
      has_content=1
      next
    }
    /^## / {
      if (in_table) {
        buf = buf "</table>\n"
        in_table=0
      }
      if (in_section && has_content) print buf "</div>"
      title = substr($0, 4)
      gsub(/&/, "\\&amp;", title); gsub(/</, "\\&lt;", title); gsub(/>/, "\\&gt;", title)
      buf = "<div class=\"current-section\"><h2>" title "</h2>"
      in_section=1; has_content=0
      next
    }
    /^$/ {
      if (in_table) {
        buf = buf "</table>\n"
        in_table=0
      }
      if (in_section && has_content) buf = buf "<br>"
      next
    }
    /^\|.*\|$/ {
      # Markdown table row
      if (!in_table) {
        buf = buf "<table class=\"markdown-table\">\n<tbody>\n"
        in_table=1
      }
      # Parse table cells
      gsub(/^\|/, "", $0); gsub(/\|$/, "", $0)
      gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;")
      # Check if separator row (dashes) BEFORE writing <tr>
      n_cells = split($0, cells, "|")
      is_sep = 0
      for (i=1; i<=n_cells; i++) {
        cell = cells[i]
        gsub(/^[ ]+/, "", cell); gsub(/[ ]+$/, "", cell)
        if (match(cell, /^[-: ]+$/)) { is_sep = 1; break }
      }
      if (is_sep) next
      buf = buf "<tr>"
      for (i=1; i<=n_cells; i++) {
        cell = cells[i]
        # Trim leading/trailing spaces
        gsub(/^[ ]+/, "", cell); gsub(/[ ]+$/, "", cell)
        buf = buf "<td>" cell "</td>"
      }
      buf = buf "</tr>\n"
      has_content=1
      next
    }
    {
      if (in_table) {
        buf = buf "</table>\n"
        in_table=0
      }
      gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;")
      # Render markdown checkboxes (as list items)
      if (match($0, /^- \[x\] /)) {
        $0 = "<div class=\"current-item check-item done\"><span class=\"check done\">✓</span> " substr($0, 7) "</div>"
        buf = buf $0 "\n"; has_content=1; next
      } else if (match($0, /^- \[ \] /)) {
        $0 = "<div class=\"current-item check-item\"><span class=\"check todo\">○</span> " substr($0, 7) "</div>"
        buf = buf $0 "\n"; has_content=1; next
      }
      # Render list items
      if (match($0, /^- /)) {
        $0 = "<div class=\"current-item\">" substr($0, 3) "</div>"
      } else if (match($0, /^[0-9]+\. /)) {
        sub(/^[0-9]+\. /, "", $0)
        $0 = "<div class=\"current-item numbered\">" $0 "</div>"
      }
      # Bold
      while (match($0, /\*\*[^*]+\*\*/)) {
        pre = substr($0, 1, RSTART-1)
        bold = substr($0, RSTART+2, RLENGTH-4)
        post = substr($0, RSTART+RLENGTH)
        $0 = pre "<strong>" bold "</strong>" post
      }
      # Inline code
      while (match($0, /`[^`]+`/)) {
        pre = substr($0, 1, RSTART-1)
        code = substr($0, RSTART+1, RLENGTH-2)
        post = substr($0, RSTART+RLENGTH)
        $0 = pre "<code>" code "</code>" post
      }
      # HTML comments (hidden)
      if (match($0, /&lt;!--.*--&gt;/)) next
      buf = buf $0 "\n"
      has_content=1
    }
    END {
      if (in_table) buf = buf "</table>\n"
      if (in_section && has_content) print buf "</div>"
    }
  ' "$CURRENT_FILE")
fi

# ---------------------------------------------------------------------------
# Source 4: Human-readable timeline from kvido log
# ---------------------------------------------------------------------------
TODAY_LOG_LINES=""
TODAY_LOG_LINES=$(bash "$LOG_SH" list --today --format human --limit 50 2>/dev/null || echo "ERROR: log list failed (exit $?)" >&2)

# ---------------------------------------------------------------------------
# Source 5: Local task files (work queue counts)
# ---------------------------------------------------------------------------
TASK_SH="$PLUGIN_ROOT/bin/kvido-task"
WQ_PROGRESS=0
WQ_TODO=0
WQ_TRIAGE=0
WQ_DONE=0

if [[ -x "$TASK_SH" ]]; then
  WQ_PROGRESS=$("$TASK_SH" count in-progress 2>/dev/null || echo 0)
  WQ_TODO=$("$TASK_SH" count todo 2>/dev/null || echo 0)
  WQ_TRIAGE=$("$TASK_SH" count triage 2>/dev/null || echo 0)
  WQ_DONE=$("$TASK_SH" count done 2>/dev/null || echo 0)
fi

# ---------------------------------------------------------------------------
# Source 6: Full task data for task list/detail views
# ---------------------------------------------------------------------------
TASKS_DIR="$KVIDO_HOME/tasks"
TASKS_JSON="[]"

_read_fm() {
  local file="$1" key="$2"
  awk '/^---$/{c++; next} c==1' "$file" \
    | awk -v k="$key" '{
        if (index($0, k ": ") == 1) { print substr($0, length(k) + 3); found=1; exit }
      } END { if (!found) print "" }'
}

_read_body_section() {
  local file="$1" section="$2"
  # Read everything after the section header until EOF (no early stop on nested ##)
  awk -v s="## $section" '
    found { print }
    $0 == s { found=1 }
  ' "$file"
}

if [[ -d "$TASKS_DIR" ]]; then
  TASK_ENTRIES=()
  for status_dir in in-progress todo triage done failed cancelled; do
    dir="$TASKS_DIR/$status_dir"
    [[ -d "$dir" ]] || continue
    # For archived statuses, limit to 50 most recent by mtime
    local_files=()
    if [[ "$status_dir" == "done" || "$status_dir" == "failed" || "$status_dir" == "cancelled" ]]; then
      while IFS= read -r f; do
        [[ -f "$f" ]] && local_files+=("$f")
      done < <(ls -t "$dir"/*.md 2>/dev/null | head -50)
    else
      for f in "$dir"/*.md; do
        [[ -f "$f" ]] && local_files+=("$f")
      done
    fi
    for f in "${local_files[@]}"; do
      _base=$(basename "$f" .md)
      if [[ "$_base" =~ ^[0-9]+-(.+)$ ]]; then
        SLUG="${BASH_REMATCH[1]}"
      else
        SLUG="$_base"
      fi
      TASK_ID=$(_read_fm "$f" "task_id")
      TITLE=$(_read_fm "$f" "title")
      PRIORITY=$(_read_fm "$f" "priority")
      SIZE=$(_read_fm "$f" "size")
      SOURCE=$(_read_fm "$f" "source")
      SOURCE_REF=$(_read_fm "$f" "source_ref")
      GOAL=$(_read_fm "$f" "goal")
      RECURRING=$(_read_fm "$f" "recurring")
      WAITING_ON=$(_read_fm "$f" "waiting_on")
      CREATED_AT=$(_read_fm "$f" "created_at")
      UPDATED_AT=$(_read_fm "$f" "updated_at")
      TRIAGE_SLACK_TS=$(_read_fm "$f" "triage_slack_ts")
      INSTRUCTION=$(_read_body_section "$f" "Instruction")
      WORKER_NOTES=$(_read_body_section "$f" "Worker Notes")

      TASK_JSON=$(jq -n \
        --arg task_id "$TASK_ID" \
        --arg slug "$SLUG" \
        --arg status "$status_dir" \
        --arg title "$TITLE" \
        --arg priority "$PRIORITY" \
        --arg size "$SIZE" \
        --arg source "$SOURCE" \
        --arg source_ref "$SOURCE_REF" \
        --arg goal "$GOAL" \
        --arg recurring "$RECURRING" \
        --arg waiting_on "$WAITING_ON" \
        --arg created_at "$CREATED_AT" \
        --arg updated_at "$UPDATED_AT" \
        --arg triage_slack_ts "$TRIAGE_SLACK_TS" \
        --arg instruction "$INSTRUCTION" \
        --arg worker_notes "$WORKER_NOTES" \
        '{task_id:$task_id, slug:$slug, status:$status, title:$title, priority:$priority, size:$size,
          source:$source, source_ref:$source_ref,
          goal:$goal, recurring:$recurring, waiting_on:$waiting_on,
          created_at:$created_at, updated_at:$updated_at, triage_slack_ts:$triage_slack_ts,
          instruction:$instruction, worker_notes:$worker_notes}')
      TASK_ENTRIES+=("$TASK_JSON")
    done
  done
  if [[ ${#TASK_ENTRIES[@]} -gt 0 ]]; then
    # Escape </script> sequences (case-insensitive) to prevent breaking the <script> tag
    TASKS_JSON=$(printf '%s\n' "${TASK_ENTRIES[@]}" | jq -s '.' | sed 's/<\/[sS][cC][rR][iI][pP][tT]>/<\\\/script>/gi')
  fi
fi

# ---------------------------------------------------------------------------
# Build warnings HTML
# ---------------------------------------------------------------------------
WARNINGS_HTML=""
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  WARNINGS_HTML='<div class="warnings">'
  for w in "${WARNINGS[@]}"; do
    WARNINGS_HTML+="<div class=\"warning-item\">$(echo "$w" | _html_escape)</div>"
  done
  WARNINGS_HTML+='</div>'
fi

# ---------------------------------------------------------------------------
# Build timeline HTML
# ---------------------------------------------------------------------------
TIMELINE_HTML=""
if [[ "$TIMELINE_JSON" != "[]" ]]; then
  TIMELINE_HTML=$(echo "$TIMELINE_JSON" | jq -r 'reverse | .[] | "<tr><td class=\"time\">\(.ts | split("T")[1] | split("+")[0] | .[0:5])</td><td class=\"agent agent-\(.agent)\">\(.agent)</td><td>\(.action)</td><td>\(.message // .detail // "")</td><td class=\"tokens\">\(.tokens // "-")</td></tr>"' 2>/dev/null || echo "")
fi

# ---------------------------------------------------------------------------
# Build token stats HTML
# ---------------------------------------------------------------------------
TOKEN_STATS_HTML=""
if [[ "$TOTAL_TOKENS" =~ ^[0-9]+$ && "$TOTAL_TOKENS" -gt 0 ]]; then
  TOKEN_STATS_HTML=$(echo "$TOKEN_STATS_JSON" | jq -r --argjson total "$TOTAL_TOKENS" \
    '.[] | {agent, tokens, runs, pct: ((.tokens / $total * 100) | floor)} |
    "<div class=\"token-row\"><span class=\"agent agent-\(.agent)\">\(.agent)</span><div class=\"bar-container\"><div class=\"bar\" style=\"width: \(.pct)%\"></div></div><span class=\"token-value\">\(if .tokens >= 1000 then "\((.tokens / 1000 * 10 | floor) / 10)k" else "\(.tokens)" end) (\(.pct)%)</span><span class=\"runs\">\(.runs) runs</span></div>"' 2>/dev/null || echo "")
fi

# ---------------------------------------------------------------------------
# HTML Generation
# ---------------------------------------------------------------------------
TMP_FILE=$(mktemp "${OUTPUT}.tmp.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT

cat > "$TMP_FILE" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
HTMLEOF

cat >> "$TMP_FILE" << HTMLEOF
<title>Kvido Dashboard</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🦉</text></svg>">
HTMLEOF

cat >> "$TMP_FILE" << 'HTMLEOF'
<style>
:root, [data-theme="dark"] {
  --bg: #1a1b26; --bg-raised: #1f2031; --card: #24283b; --card-hover: #292e42;
  --border: #414868; --border-subtle: #2f3549;
  --text: #a9b1d6; --text-bright: #c0caf5; --accent: #7aa2f7; --accent-glow: rgba(122,162,247,0.15);
  --success: #9ece6a; --success-glow: rgba(158,206,106,0.12);
  --warning: #e0af68; --warning-glow: rgba(224,175,104,0.12);
  --error: #f7768e; --error-glow: rgba(247,118,142,0.12);
  --purple: #bb9af7; --muted: #565f89;
  --scanline: rgba(255,255,255,0.008);
}
[data-theme="light"] {
  --bg: #f0f1f5; --bg-raised: #e4e6ed; --card: #ffffff; --card-hover: #f7f8fb;
  --border: #c8ccd8; --border-subtle: #dde0e9;
  --text: #4a4f69; --text-bright: #1e2030; --accent: #3d6be5; --accent-glow: rgba(61,107,229,0.12);
  --success: #40a02b; --success-glow: rgba(64,160,43,0.10);
  --warning: #df8e1d; --warning-glow: rgba(223,142,29,0.10);
  --error: #d20f39; --error-glow: rgba(210,15,57,0.10);
  --purple: #8839ef; --muted: #8c8fa1;
  --scanline: rgba(0,0,0,0.012);
}
@keyframes pulse-dot { 0%, 100% { opacity: 0.4; } 50% { opacity: 1; } }
*, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: var(--bg);
  background-image: repeating-linear-gradient(0deg, transparent, transparent 3px, var(--scanline) 3px, var(--scanline) 4px);
  color: var(--text); font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', monospace;
  font-size: 13px; line-height: 1.6; padding: 24px 20px; max-width: 1200px; margin: 0 auto;
  -webkit-font-smoothing: antialiased;
}
header { margin-bottom: 16px; display: flex; align-items: center; gap: 12px; }
.header-avatar { width: 42px; height: 42px; border-radius: 50%; flex-shrink: 0; filter: drop-shadow(0 0 6px rgba(122,162,247,0.3)); }
header h1 {
  color: var(--text-bright); font-size: 1.1em; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase;
  display: flex; align-items: center; gap: 8px;
}
header h1::before { content: ""; display: inline-block; width: 6px; height: 6px; background: var(--accent); border-radius: 50%; animation: pulse-dot 2s ease-in-out infinite; box-shadow: 0 0 8px var(--accent-glow); }
.meta { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 8px; }
.meta-tag {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 0.8em; color: var(--muted); background: var(--bg-raised); border: 1px solid var(--border-subtle);
  padding: 2px 8px; border-radius: 3px;
}
.zone-badge { font-weight: 700; letter-spacing: 0.02em; }
.zone-working { background: rgba(158,206,106,0.08); color: var(--success); border-color: rgba(158,206,106,0.2); }
.zone-off-hours { background: rgba(224,175,104,0.08); color: var(--warning); border-color: rgba(224,175,104,0.2); }
.zone-turbo { background: rgba(187,154,247,0.08); color: var(--purple); border-color: rgba(187,154,247,0.2); }
.zone-sleep { background: rgba(86,95,137,0.15); color: var(--muted); border-color: rgba(86,95,137,0.3); }

/* Tab navigation */
.tabs-nav {
  display: flex; gap: 0; margin-bottom: 20px;
  border-bottom: 1px solid var(--border-subtle);
}
.tab-btn {
  background: none; border: none; border-bottom: 2px solid transparent;
  color: var(--muted); font-family: inherit; font-size: 0.82em; font-weight: 600;
  text-transform: uppercase; letter-spacing: 0.06em;
  padding: 8px 18px; cursor: pointer; transition: color 0.15s, border-color 0.15s;
  margin-bottom: -1px;
}
.tab-btn:hover { color: var(--text); }
.tab-btn.active { color: var(--accent); border-bottom-color: var(--accent); }
.tab-btn .tab-count {
  display: inline-block; font-size: 0.75em; font-weight: 700;
  background: var(--bg-raised); border: 1px solid var(--border-subtle);
  padding: 0 5px; border-radius: 10px; margin-left: 6px;
  vertical-align: middle; font-variant-numeric: tabular-nums;
}
.tab-btn.active .tab-count { background: var(--accent-glow); border-color: rgba(122,162,247,0.25); color: var(--accent); }

/* Tab panels */
.tab-panel { display: none; }
.tab-panel.active { display: block; }

/* Views inside tabs (for detail view overlay) */
.view { display: none; }
.view.active { display: block; }

.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 14px; margin-bottom: 14px; }
.card {
  background: var(--card); border: 1px solid var(--border-subtle); border-radius: 6px; padding: 16px;
  transition: border-color 0.2s, background 0.15s, box-shadow 0.2s;
}
.card:hover { background: var(--card-hover); border-color: var(--border); box-shadow: 0 2px 12px rgba(0,0,0,0.15); }
.card h2 {
  color: var(--muted); font-size: 0.75em; font-weight: 600; text-transform: uppercase; letter-spacing: 0.08em;
  margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid var(--border-subtle);
}

/* Stat pills for Overview tab */
.stat-pills { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 16px; }
.stat-pill {
  display: flex; flex-direction: column; align-items: center; gap: 2px;
  background: var(--card); border: 1px solid var(--border-subtle); border-radius: 6px;
  padding: 10px 18px; min-width: 70px;
}
.stat-pill .stat-val { font-size: 1.5em; font-weight: 700; color: var(--text-bright); font-variant-numeric: tabular-nums; line-height: 1; }
.stat-pill .stat-lbl { font-size: 0.65em; color: var(--muted); text-transform: uppercase; letter-spacing: 0.08em; }
.stat-pill.pill-inprogress .stat-val { color: var(--accent); }
.stat-pill.pill-todo .stat-val { color: var(--text-bright); }
.stat-pill.pill-triage .stat-val { color: var(--warning); }
.stat-pill.pill-done .stat-val { color: var(--success); }

table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
thead th { color: var(--muted); font-weight: 500; font-size: 0.85em; text-transform: uppercase; letter-spacing: 0.06em; padding: 8px; border-bottom: 1px solid var(--border); text-align: left; }
tbody td { padding: 7px 8px; border-bottom: 1px solid var(--border-subtle); transition: background 0.15s; }
tbody tr:hover td { background: rgba(122,162,247,0.04); }
tbody tr:last-child td { border-bottom: none; }
.time { color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
.tokens { color: var(--muted); text-align: right; font-variant-numeric: tabular-nums; }
.agent { font-weight: 600; }
.agent-planner { color: var(--accent); }
.agent-worker { color: var(--success); }
.agent-triager { color: var(--muted); }
.agent-listener { color: var(--purple); }
.agent-morning { color: var(--warning); }
.agent-eod { color: var(--warning); }
.agent-heartbeat { color: var(--muted); }

.token-row { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
.token-row .agent { min-width: 76px; font-size: 0.82em; font-weight: 600; }
.bar-container { flex: 1; background: var(--border-subtle); border-radius: 3px; height: 6px; overflow: hidden; }
.bar {
  height: 100%; border-radius: 3px;
  background: linear-gradient(90deg, var(--accent), #89b4fa);
}
.token-row:hover .bar { filter: brightness(1.2); }
.token-value { font-size: 0.78em; color: var(--muted); min-width: 90px; text-align: right; font-variant-numeric: tabular-nums; }
.runs { font-size: 0.72em; color: var(--muted); min-width: 55px; opacity: 0.7; }

.warnings {
  background: var(--error-glow); border: 1px solid rgba(247,118,142,0.25); border-radius: 6px;
  padding: 10px 14px; margin-bottom: 18px;
}
.warning-item { color: var(--error); font-size: 0.82em; padding: 3px 0; display: flex; align-items: baseline; gap: 6px; }
.warning-item::before { content: "!"; font-weight: 700; font-size: 0.75em; background: var(--error); color: var(--bg); width: 14px; height: 14px; border-radius: 2px; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; }

.focus-text { color: var(--text); line-height: 1.6; font-size: 0.9em; }
.focus-text strong { color: var(--text-bright); font-weight: 600; }
.blockers { color: var(--error); }
.blockers strong { color: var(--error); }
.empty { color: var(--muted); font-style: italic; font-size: 0.82em; padding: 8px 0; }

/* Current state card */
.current-section { margin-bottom: 14px; margin-top: 18px; }
.current-section:first-child { margin-top: 0; }
.current-section:last-child { margin-bottom: 0; }
.current-section h3 {
  color: var(--accent); font-size: 0.78em; font-weight: 600; text-transform: uppercase;
  letter-spacing: 0.06em; margin-top: 12px; margin-bottom: 6px; padding-bottom: 4px;
  border-bottom: 1px solid var(--border-subtle);
}
.current-section h3:first-child { margin-top: 0; }
.current-item { color: var(--text); font-size: 0.88em; line-height: 1.5; padding: 2px 0 2px 12px; border-left: 2px solid var(--border-subtle); margin-bottom: 2px; }
.current-item:hover { border-left-color: var(--accent); background: rgba(122,162,247,0.03); }
.current-item.numbered { border-left-color: var(--warning); }
.current-section strong { color: var(--text-bright); }
.current-section code { background: var(--bg-raised); padding: 1px 4px; border-radius: 3px; font-size: 0.9em; }
.check-item { border-left-color: var(--muted); }
.check-item.done { border-left-color: var(--success); opacity: 0.7; text-decoration: line-through; text-decoration-color: var(--muted); }
.check { font-weight: 700; margin-right: 4px; display: inline-block; width: 1.2em; text-align: center; }
.check.done { color: var(--success); }
.check.todo { color: var(--muted); }

footer { text-align: center; color: var(--muted); font-size: 0.7em; padding: 20px 0 8px; opacity: 0.5; }

/* Theme toggle */
.theme-toggle {
  position: fixed; top: 16px; right: 20px; z-index: 100;
  width: 36px; height: 36px; border-radius: 50%;
  background: var(--card); border: 1px solid var(--border-subtle);
  color: var(--muted); cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  font-size: 16px; line-height: 1;
  transition: background 0.2s, border-color 0.2s, color 0.2s, transform 0.2s;
}
.theme-toggle:hover { background: var(--card-hover); border-color: var(--border); color: var(--text-bright); transform: scale(1.1); }

/* Task list/detail — kanban board */
.badge {
  display: inline-block; font-size: 0.68em; font-weight: 600; padding: 1px 6px; border-radius: 3px;
  text-transform: uppercase; letter-spacing: 0.04em; white-space: nowrap;
}
.badge-urgent { background: var(--error-glow); color: var(--error); border: 1px solid rgba(247,118,142,0.25); }
.badge-high { background: var(--warning-glow); color: var(--warning); border: 1px solid rgba(224,175,104,0.25); }
.badge-medium { background: rgba(169,177,214,0.08); color: var(--text); border: 1px solid var(--border-subtle); }
.badge-low { background: rgba(86,95,137,0.15); color: var(--muted); border: 1px solid rgba(86,95,137,0.3); }
.badge-in-progress { background: var(--accent-glow); color: var(--accent); border: 1px solid rgba(122,162,247,0.25); }
.badge-todo { background: rgba(192,202,245,0.08); color: var(--text-bright); border: 1px solid var(--border-subtle); }
.badge-triage { background: var(--warning-glow); color: var(--warning); border: 1px solid rgba(224,175,104,0.25); }
.badge-done { background: var(--success-glow); color: var(--success); border: 1px solid rgba(158,206,106,0.25); }
.badge-failed { background: var(--error-glow); color: var(--error); border: 1px solid rgba(247,118,142,0.25); }
.badge-cancelled { background: rgba(86,95,137,0.15); color: var(--muted); border: 1px solid rgba(86,95,137,0.3); }
.badge-size { background: rgba(187,154,247,0.08); color: var(--purple); border: 1px solid rgba(187,154,247,0.2); }

/* Kanban board */
.kanban { display: flex; gap: 12px; overflow-x: auto; padding-bottom: 8px; min-height: 300px; }
.kanban::-webkit-scrollbar { height: 6px; }
.kanban::-webkit-scrollbar-track { background: var(--bg-raised); border-radius: 3px; }
.kanban::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
.kanban-col {
  min-width: 240px; flex: 1; display: flex; flex-direction: column;
  background: var(--bg-raised); border: 1px solid var(--border-subtle); border-radius: 8px;
}
.kanban-col-header {
  padding: 10px 12px; display: flex; align-items: center; justify-content: space-between; gap: 8px;
  border-bottom: 1px solid var(--border-subtle); position: sticky; top: 0;
}
.kanban-col-header .col-title {
  font-size: 0.72em; font-weight: 600; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted);
}
.kanban-col-header .col-count {
  font-size: 0.72em; font-weight: 700; color: var(--text); background: var(--card);
  padding: 1px 7px; border-radius: 10px; font-variant-numeric: tabular-nums;
  border: 1px solid var(--border-subtle);
}
/* Column accent top border by status */
.kanban-col[data-status="triage"] { border-top: 2px solid var(--warning); }
.kanban-col[data-status="todo"] { border-top: 2px solid var(--text-bright); }
.kanban-col[data-status="in-progress"] { border-top: 2px solid var(--accent); }
.kanban-col[data-status="done"] { border-top: 2px solid var(--success); }
.kanban-col[data-status="failed"] { border-top: 2px solid var(--error); }
.kanban-col[data-status="cancelled"] { border-top: 2px solid var(--muted); }

/* Archived column — collapsed by default, click to expand */
.kanban-col.col-done-collapsed .kanban-cards { display: none; }
.kanban-col.col-done-collapsed { opacity: 0.6; min-width: 44px; flex: 0 0 44px; }
.kanban-col.col-done-collapsed .kanban-col-header {
  flex-direction: column; align-items: center; gap: 6px; padding: 10px 4px;
}
.kanban-col.col-done-collapsed .col-title {
  writing-mode: vertical-rl; text-orientation: mixed; font-size: 0.65em; white-space: nowrap;
}
.kanban-col.col-done-collapsed .col-count { font-size: 0.6em; }
.kanban-col.col-done-collapsed:hover { opacity: 0.8; }
.col-toggle {
  font-size: 0.7em; color: var(--muted); cursor: pointer; padding: 2px 6px;
  border: 1px solid var(--border-subtle); border-radius: 3px; background: var(--card);
  transition: all 0.15s;
}
.col-toggle:hover { color: var(--text); border-color: var(--border); }

.kanban-cards { padding: 8px; flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 6px; }
.kanban-cards::-webkit-scrollbar { width: 4px; }
.kanban-cards::-webkit-scrollbar-thumb { background: var(--border-subtle); border-radius: 2px; }

.kanban-card {
  background: var(--card); border: 1px solid var(--border-subtle); border-radius: 6px;
  padding: 10px 12px; cursor: pointer; transition: all 0.15s;
  position: relative;
}
.kanban-card:hover { background: var(--card-hover); border-color: var(--border); transform: translateY(-1px); box-shadow: 0 4px 12px rgba(0,0,0,0.2); }
.kanban-card-title { color: var(--text-bright); font-size: 0.82em; font-weight: 500; line-height: 1.4; margin-bottom: 8px; }
.kanban-card-meta { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; }
.kanban-card-footer { display: flex; justify-content: space-between; align-items: center; margin-top: 8px; }
.kanban-card-slug { color: var(--muted); font-size: 0.68em; letter-spacing: 0.02em; }
.kanban-card-id { color: var(--accent); font-weight: 600; font-size: 0.68em; }
.kanban-card-time { color: var(--muted); font-size: 0.68em; font-variant-numeric: tabular-nums; }
/* Priority left-edge indicator */
.kanban-card[data-priority="urgent"] { border-left: 3px solid var(--error); }
.kanban-card[data-priority="high"] { border-left: 3px solid var(--warning); }
.kanban-empty { color: var(--muted); font-size: 0.78em; font-style: italic; padding: 16px 8px; text-align: center; }

.back-btn {
  display: inline-flex; align-items: center; gap: 6px; color: var(--accent); font-size: 0.82em;
  cursor: pointer; padding: 4px 0; margin-bottom: 16px; text-decoration: none;
}
.back-btn:hover { color: var(--text-bright); }

.detail-header { margin-bottom: 20px; }
.detail-header h2 { color: var(--text-bright); font-size: 1.2em; font-weight: 600; margin-bottom: 8px; border: none; padding: 0; text-transform: none; letter-spacing: normal; }
.detail-task-id { color: var(--accent); font-size: 0.85em; font-weight: 600; display: block; margin-bottom: 4px; }
.detail-meta {
  display: grid; grid-template-columns: 1fr 1fr; gap: 8px 20px; margin-bottom: 20px;
  background: var(--card); border: 1px solid var(--border-subtle); border-radius: 6px; padding: 14px;
}
.detail-meta-item { display: flex; gap: 8px; font-size: 0.82em; }
.detail-meta-label { color: var(--muted); min-width: 100px; text-transform: uppercase; font-size: 0.85em; letter-spacing: 0.04em; }
.detail-meta-value { color: var(--text); word-break: break-word; }
.detail-meta-value.empty-val { color: var(--muted); font-style: italic; }

.detail-section { margin-bottom: 16px; }
.detail-section h3 {
  color: var(--muted); font-size: 0.75em; font-weight: 600; text-transform: uppercase; letter-spacing: 0.08em;
  margin-bottom: 8px; padding-bottom: 6px; border-bottom: 1px solid var(--border-subtle);
}
.detail-body {
  background: var(--card); border: 1px solid var(--border-subtle); border-radius: 6px; padding: 14px;
  font-size: 0.9em; line-height: 1.7; color: var(--text);
}
.detail-body h1, .detail-body h2, .detail-body h3 { color: var(--text-bright); margin: 12px 0 6px; font-size: 1em; }
.detail-body pre { background: var(--bg); border: 1px solid var(--border-subtle); border-radius: 4px; padding: 10px; overflow-x: auto; margin: 8px 0; }
.detail-body code { background: var(--bg-raised); padding: 1px 4px; border-radius: 2px; font-size: 0.92em; }
.detail-body pre code { background: none; padding: 0; }
.detail-body ul { padding-left: 20px; margin: 6px 0; }
.detail-body li { margin: 3px 0; }
.detail-body strong { color: var(--text-bright); }
.detail-body em { color: var(--purple); }

@media (max-width: 768px) {
  body { padding: 16px 12px; font-size: 12px; }
  .kanban { flex-direction: column; min-height: auto; }
  .kanban-col { min-width: unset; }
  .grid { grid-template-columns: 1fr; }
  .meta { gap: 4px; }
  .token-row { gap: 6px; }
  .token-row .agent { min-width: 60px; font-size: 0.75em; }
  .token-value { min-width: 70px; }
  .detail-meta { grid-template-columns: 1fr; }
  .tabs-nav { overflow-x: auto; }
  .tab-btn { padding: 8px 12px; }
}
@media (max-width: 480px) {
  .meta-tag { font-size: 0.72em; padding: 1px 5px; }
  thead th { font-size: 0.75em; }
}
</style>
</head>
<body>
HTMLEOF

# Avatar — base64 inline (works in self-contained HTML)
AVATAR_SRC="$PLUGIN_ROOT/assets/kvido-avatar.png"
AVATAR_B64=""
if [[ -f "$AVATAR_SRC" ]]; then
  AVATAR_B64="data:image/png;base64,$(base64 -w0 "$AVATAR_SRC" 2>/dev/null || base64 "$AVATAR_SRC" 2>/dev/null)"
fi

AVATAR_HTML=""
if [[ -n "$AVATAR_B64" ]]; then
  AVATAR_HTML="<img class=\"header-avatar\" src=\"${AVATAR_B64}\" alt=\"Kvido\">"
fi

cat >> "$TMP_FILE" << HTMLEOF
<button class="theme-toggle" id="theme-toggle" title="Toggle light/dark mode" aria-label="Toggle theme">☀</button>
<header>
${AVATAR_HTML}
<div>
<h1>Kvido Dashboard</h1>
<div class="meta">
  <span class="meta-tag">${TODAY}</span>
  <span class="meta-tag">#${ITERATION}</span>
  <span class="meta-tag">${ACTIVE_PRESET}</span>
  <span class="meta-tag zone-badge zone-${ZONE}">${ZONE}</span>
  <span class="meta-tag">interaction ${INTERACTION_AGO} ago</span>
  <span class="meta-tag">$(date +%H:%M:%S)</span>
</div>
</div>
</header>

${WARNINGS_HTML}

<!-- Tab navigation -->
<nav class="tabs-nav">
  <button class="tab-btn active" data-tab="overview">Overview</button>
  <button class="tab-btn" data-tab="tasks">Tasks <span class="tab-count" id="tab-count-tasks">0</span></button>
  <button class="tab-btn" data-tab="log">Activity Log</button>
</nav>

<!-- Tab 1: Overview -->
<div id="tab-overview" class="tab-panel active">

<div class="stat-pills">
  <div class="stat-pill pill-triage" onclick="showTab('tasks')" style="cursor:pointer"><span class="stat-val">${WQ_TRIAGE}</span><span class="stat-lbl">Triage</span></div>
  <div class="stat-pill pill-todo" onclick="showTab('tasks')" style="cursor:pointer"><span class="stat-val">${WQ_TODO}</span><span class="stat-lbl">Todo</span></div>
  <div class="stat-pill pill-inprogress" onclick="showTab('tasks')" style="cursor:pointer"><span class="stat-val">${WQ_PROGRESS}</span><span class="stat-lbl">In Progress</span></div>
  <div class="stat-pill pill-done" onclick="showTab('tasks')" style="cursor:pointer"><span class="stat-val">${WQ_DONE}</span><span class="stat-lbl">Done</span></div>
</div>

<div class="card current-card">
$(if [[ -n "$CURRENT_HTML" ]]; then echo "$CURRENT_HTML"; else echo '<div class="empty">No current.md found</div>'; fi)
</div>

</div><!-- /tab-overview -->

<!-- Tab 2: Tasks -->
<div id="tab-tasks" class="tab-panel">

<div id="view-tasks" class="view active">
<div id="kanban" class="kanban"></div>
</div>

<div id="view-detail" class="view"></div>

</div><!-- /tab-tasks -->

<!-- Tab 3: Activity Log -->
<div id="tab-log" class="tab-panel">

$(if [[ -n "$TOKEN_STATS_HTML" ]]; then cat << TOKENEOF
<div class="card" style="margin-bottom:14px">
<h2>Token Usage ($( [[ $TOTAL_TOKENS -ge 1000 ]] && echo "$(( TOTAL_TOKENS / 1000 )).$(( TOTAL_TOKENS % 1000 / 100 ))k" || echo "${TOTAL_TOKENS}" ) total, ${TOTAL_RUNS} runs)</h2>
${TOKEN_STATS_HTML}
</div>
TOKENEOF
fi)

<div class="card">
<h2>Activity Timeline (today)</h2>
$(if [[ -n "$TIMELINE_HTML" ]]; then cat << TABLEEOF
<table>
<thead><tr><th>Time</th><th>Agent</th><th>Action</th><th>Detail</th><th style="text-align:right">Tokens</th></tr></thead>
<tbody>
${TIMELINE_HTML}
</tbody>
</table>
TABLEEOF
else
  echo '<div class="empty">No activity data yet</div>'
fi)
</div>

</div><!-- /tab-log -->

HTMLEOF

# Embed tasks JSON (needs variable expansion)
cat >> "$TMP_FILE" << JSEOF
<script>
var TASKS = ${TASKS_JSON};
JSEOF

# Embed JS routing (quoted — no variable expansion needed)
cat >> "$TMP_FILE" << 'JSEOF'

var STATUS_ORDER = ['triage','todo','in-progress','done','failed','cancelled'];
var STATUS_LABELS = {'triage':'Triage','todo':'Todo','in-progress':'In Progress','done':'Done','failed':'Failed','cancelled':'Cancelled'};
var PRIORITY_ORDER = {'urgent':0,'high':1,'medium':2,'low':3,'':4};

// Tab switching
function showTab(name) {
  document.querySelectorAll('.tab-panel').forEach(function(p) { p.classList.remove('active'); });
  document.querySelectorAll('.tab-btn').forEach(function(b) { b.classList.remove('active'); });
  var panel = document.getElementById('tab-' + name);
  if (panel) panel.classList.add('active');
  document.querySelectorAll('.tab-btn').forEach(function(b) {
    if (b.getAttribute('data-tab') === name) b.classList.add('active');
  });
  if (name !== 'tasks') {
    // When switching away from tasks tab, restore the kanban view
    showView('tasks');
  }
}

document.querySelectorAll('.tab-btn').forEach(function(btn) {
  btn.addEventListener('click', function() {
    var tab = btn.getAttribute('data-tab');
    location.hash = tab === 'overview' ? '' : tab;
    showTab(tab);
  });
});

function showView(name) {
  var tasksEl = document.getElementById('view-tasks');
  var detailEl = document.getElementById('view-detail');
  if (name === 'detail') {
    if (tasksEl) tasksEl.classList.remove('active');
    if (detailEl) detailEl.classList.add('active');
  } else {
    if (tasksEl) tasksEl.classList.add('active');
    if (detailEl) detailEl.classList.remove('active');
  }
}

function badgeClass(type, val) {
  if (!val) return 'badge';
  return 'badge badge-' + val.replace(/\s+/g, '-').toLowerCase();
}

function relTime(iso) {
  if (!iso) return '';
  var d = new Date(iso);
  var now = new Date();
  var diff = Math.floor((now - d) / 1000);
  if (diff < 60) return 'just now';
  if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
  if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
  return Math.floor(diff / 86400) + 'd ago';
}

function esc(s) {
  if (!s) return '';
  var d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

function md(text) {
  if (!text) return '<span class="empty">—</span>';
  var s = esc(text);
  // code blocks
  s = s.replace(/\`\`\`([\s\S]*?)\`\`\`/g, '<pre><code>$1</code></pre>');
  // inline code
  s = s.replace(/\`([^\`]+)\`/g, '<code>$1</code>');
  // headers
  s = s.replace(/^### (.+)$/gm, '<h3>$1</h3>');
  s = s.replace(/^## (.+)$/gm, '<h2>$1</h2>');
  s = s.replace(/^# (.+)$/gm, '<h1>$1</h1>');
  // bold/italic
  s = s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/\*(.+?)\*/g, '<em>$1</em>');
  // markdown tables
  s = s.replace(/(\|[^\n]+\|[ \t]*\n?)+/g, function(tableMatch) {
    var lines = tableMatch.trim().split('\n');
    var html = '<table class="markdown-table"><tbody>';
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      // skip separator rows (contain only dashes, colons, pipes)
      if (/^\|[\s\-:|\s]*\|$/.test(line)) continue;
      // parse table row
      var cells = line.split('|').slice(1, -1);
      html += '<tr>';
      for (var j = 0; j < cells.length; j++) {
        html += '<td>' + esc(cells[j].trim()) + '</td>';
      }
      html += '</tr>';
    }
    html += '</tbody></table>';
    return html;
  });
  // list items
  s = s.replace(/^- (.+)$/gm, '<li>$1</li>');
  // wrap consecutive <li> in <ul>
  s = s.replace(/((?:<li>.*?<\/li>\n?)+)/g, '<ul>$1</ul>');
  // line breaks (but not inside pre)
  s = s.replace(/(?<!\>)\n(?!\<)/g, '<br>');
  return s;
}

function renderKanban() {
  var el = document.getElementById('kanban');
  var html = '';
  // Active columns: in-progress, todo, triage (primary focus)
  var ACTIVE_COLS = ['triage','todo','in-progress'];
  var active = TASKS.filter(function(t) { return ACTIVE_COLS.indexOf(t.status) !== -1; });
  // Update tab count badge
  var countEl = document.getElementById('tab-count-tasks');
  if (countEl) countEl.textContent = active.length;

  ACTIVE_COLS.forEach(function(status) {
    var tasks = TASKS.filter(function(t) { return t.status === status; });
    tasks.sort(function(a, b) { return (PRIORITY_ORDER[a.priority] != null ? PRIORITY_ORDER[a.priority] : 4) - (PRIORITY_ORDER[b.priority] != null ? PRIORITY_ORDER[b.priority] : 4); });

    html += '<div class="kanban-col" data-status="' + status + '">';
    html += '<div class="kanban-col-header"><span class="col-title">' + (STATUS_LABELS[status] || status) + '</span><span class="col-count">' + tasks.length + '</span></div>';
    html += '<div class="kanban-cards">';
    if (tasks.length === 0) {
      html += '<div class="kanban-empty">No tasks</div>';
    }
    tasks.forEach(function(t) {
      html += '<div class="kanban-card" data-priority="' + (t.priority || '') + '" onclick="location.hash=\'task/' + t.slug + '\'">';
      html += '<div class="kanban-card-title">' + esc(t.title) + '</div>';
      html += '<div class="kanban-card-meta">';
      if (t.priority) html += '<span class="' + badgeClass('priority', t.priority) + '">' + esc(t.priority) + '</span>';
      if (t.size) html += '<span class="badge badge-size">' + esc(t.size) + '</span>';
      if (t.source) html += '<span class="badge">' + esc(t.source) + '</span>';
      html += '</div>';
      html += '<div class="kanban-card-footer"><span class="kanban-card-slug">' + (t.task_id ? '<span class="kanban-card-id">#' + esc(t.task_id) + '</span> ' : '') + esc(t.slug) + '</span><span class="kanban-card-time">' + relTime(t.updated_at) + '</span></div>';
      html += '</div>';
    });
    html += '</div></div>';
  });

  // Archived columns (done, failed, cancelled) — collapsed by default
  ['done','failed','cancelled'].forEach(function(status) {
    var items = TASKS.filter(function(t) { return t.status === status; });
    var label = STATUS_LABELS[status] || status;
    html += '<div class="kanban-col col-done-collapsed" id="col-' + status + '" data-status="' + status + '" onclick="this.classList.toggle(\'col-done-collapsed\')">';
    html += '<div class="kanban-col-header"><span class="col-title">' + label + '</span><span class="col-count">' + items.length + '</span></div>';
    html += '<div class="kanban-cards">';
    items.sort(function(a, b) { return (b.updated_at || '').localeCompare(a.updated_at || ''); });
    items.slice(0, 20).forEach(function(t) {
      html += '<div class="kanban-card" onclick="event.stopPropagation(); location.hash=\'task/' + t.slug + '\'">';
      html += '<div class="kanban-card-title">' + esc(t.title) + '</div>';
      html += '<div class="kanban-card-footer"><span class="kanban-card-slug">' + (t.task_id ? '<span class="kanban-card-id">#' + esc(t.task_id) + '</span> ' : '') + esc(t.slug) + '</span><span class="kanban-card-time">' + relTime(t.updated_at) + '</span></div>';
      html += '</div>';
    });
    html += '</div></div>';
  });

  el.innerHTML = html;
}


function renderDetail(slug) {
  showView('detail');
  var el = document.getElementById('view-detail');
  var t = TASKS.find(function(x) { return x.slug === slug; });
  if (!t) { el.innerHTML = '<div class="empty">Task not found: ' + esc(slug) + '</div>'; return; }

  var metaFields = [
    ['Status', '<span class="badge badge-' + t.status + '">' + (STATUS_LABELS[t.status] || t.status) + '</span>'],
    ['Priority', t.priority ? '<span class="' + badgeClass('priority', t.priority) + '">' + esc(t.priority) + '</span>' : null],
    ['Size', t.size ? '<span class="badge badge-size">' + esc(t.size) + '</span>' : null],
    ['Source', t.source],
    ['Source Ref', t.source_ref],
    ['Worktree', t.worktree],
    ['Goal', t.goal],
    ['Recurring', t.recurring],
    ['Waiting On', t.waiting_on],
    ['Created', t.created_at],
    ['Updated', t.updated_at],
    ['Triage Slack TS', t.triage_slack_ts]
  ];

  var html = '<a class="back-btn" href="#tasks">&larr; Tasks</a>';
  html += '<div class="detail-header">' + (t.task_id ? '<span class="detail-task-id">#' + esc(t.task_id) + '</span>' : '') + '<h2>' + esc(t.title) + '</h2></div>';
  html += '<div class="detail-meta">';
  metaFields.forEach(function(f) {
    var val = f[1] || '';
    var cls = val ? 'detail-meta-value' : 'detail-meta-value empty-val';
    html += '<div class="detail-meta-item"><span class="detail-meta-label">' + f[0] + '</span><span class="' + cls + '">' + (val || '&mdash;') + '</span></div>';
  });
  html += '</div>';

  if (t.instruction) {
    html += '<div class="detail-section"><h3>Instruction</h3><div class="detail-body">' + md(t.instruction) + '</div></div>';
  }
  if (t.worker_notes) {
    html += '<div class="detail-section"><h3>Worker Notes</h3><div class="detail-body">' + md(t.worker_notes) + '</div></div>';
  }
  el.innerHTML = html;
}

function route() {
  var hash = location.hash.slice(1);
  if (hash.indexOf('task/') === 0) {
    showTab('tasks');
    renderDetail(hash.slice(5));
  } else if (hash === 'tasks') {
    showTab('tasks');
    showView('tasks');
  } else if (hash === 'log') {
    showTab('log');
  } else {
    showTab('overview');
  }
}

renderKanban();
window.addEventListener('hashchange', route);
route();

// Count-up animation for stat pills
document.querySelectorAll('.stat-val').forEach(function(el) {
  var target = parseInt(el.textContent, 10);
  if (isNaN(target) || target === 0) return;
  el.textContent = '0';
  var start = performance.now();
  var duration = 400;
  (function tick(now) {
    var p = Math.min((now - start) / duration, 1);
    el.textContent = Math.round(p * target);
    if (p < 1) requestAnimationFrame(tick);
  })(start);
});

// Theme toggle
(function() {
  var html = document.documentElement;
  var btn = document.getElementById('theme-toggle');
  var stored = localStorage.getItem('kvido-theme');
  var theme = stored || 'dark';
  html.setAttribute('data-theme', theme);
  btn.textContent = theme === 'dark' ? '\u2600' : '\u263E';
  btn.addEventListener('click', function() {
    theme = theme === 'dark' ? 'light' : 'dark';
    html.setAttribute('data-theme', theme);
    localStorage.setItem('kvido-theme', theme);
    btn.textContent = theme === 'dark' ? '\u2600' : '\u263E';
  });
})();
</script>
JSEOF

# Auto-refresh: use JS location.reload() so the URL hash (active tab) is preserved.
# <meta http-equiv="refresh"> would strip the hash fragment on every reload.
cat >> "$TMP_FILE" << JSEOF
<script>
// Auto-refresh every ${AUTO_REFRESH}s, preserving URL hash for active tab.
setInterval(function() { location.reload(); }, ${AUTO_REFRESH} * 1000);
</script>
JSEOF

cat >> "$TMP_FILE" << HTMLEOF
<footer>auto-refresh ${AUTO_REFRESH}s</footer>
</body>
</html>
HTMLEOF

mv "$TMP_FILE" "$OUTPUT"
