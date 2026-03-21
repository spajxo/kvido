#!/usr/bin/env bash
# generate-dashboard.sh — Generates state/dashboard.html from assistant state files.
# Called from heartbeat.sh. Must never fail fatally (heartbeat calls with || true).
#
# Data sources:
#   1. state/activity-log.jsonl  (issue #7, may not exist)
#   2. state/heartbeat-state.json
#   3. state/current.md
#   4. state/today.md
#   5. state/tasks/ (local task files)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"
STATE_DIR="${PWD}/state"
OUTPUT="$STATE_DIR/dashboard.html"

# Check if dashboard is enabled
DASHBOARD_ENABLED=$($CONFIG '.skills.dashboard.enabled // true' 2>/dev/null || echo "true")
if [[ "$DASHBOARD_ENABLED" == "false" ]]; then
  exit 0
fi

AUTO_REFRESH=$($CONFIG '.skills.dashboard.auto_refresh // 20' 2>/dev/null || echo 20)
NOW=$(date -Iseconds)
TODAY=$(date -I)
WARNINGS=()

# ---------------------------------------------------------------------------
# Source 1: activity-log.jsonl
# ---------------------------------------------------------------------------
JSONL_FILE="$STATE_DIR/activity-log.jsonl"
TIMELINE_JSON="[]"
TOKEN_STATS_JSON="[]"
TOTAL_TOKENS=0
TOTAL_RUNS=0

if [[ -f "$JSONL_FILE" ]]; then
  # Filter today's entries, last 50 for timeline
  TIMELINE_JSON=$(jq -s --arg today "${TODAY}T00:00:00" \
    '[.[] | select(.ts >= $today)] | sort_by(.ts) | .[-50:] | reverse' \
    "$JSONL_FILE" 2>/dev/null) || { WARNINGS+=("activity-log.jsonl: parse error"); TIMELINE_JSON="[]"; }

  # Aggregate token stats per agent
  TOKEN_STATS_JSON=$(jq -s --arg today "${TODAY}T00:00:00" \
    '[.[] | select(.ts >= $today)] | group_by(.agent) | map({
      agent: .[0].agent,
      tokens: (map(.tokens // 0) | add),
      runs: length
    }) | sort_by(-.tokens)' \
    "$JSONL_FILE" 2>/dev/null) || { WARNINGS+=("activity-log.jsonl: stats error"); TOKEN_STATS_JSON="[]"; }

  TOTAL_TOKENS=$(echo "$TOKEN_STATS_JSON" | jq '[.[].tokens] | add // 0' 2>/dev/null || echo 0)
  TOTAL_RUNS=$(echo "$TOKEN_STATS_JSON" | jq '[.[].runs] | add // 0' 2>/dev/null || echo 0)
else
  WARNINGS+=("activity-log.jsonl not found (issue #7 not implemented?)")
  echo "WARNING: activity-log.jsonl not found" >&2
fi

HAS_JSONL=false
[[ -f "$JSONL_FILE" ]] && HAS_JSONL=true

# ---------------------------------------------------------------------------
# Source 2: heartbeat-state.json
# ---------------------------------------------------------------------------
HB_FILE="$STATE_DIR/heartbeat-state.json"
ITERATION=0
ACTIVE_PRESET="?"
LAST_QUICK=""
SLEEP_UNTIL=""
TURBO_UNTIL=""
INTERACTION_AGO="?"

if [[ -f "$HB_FILE" ]] && jq empty "$HB_FILE" 2>/dev/null; then
  ITERATION=$(jq -r '.iteration_count // 0' "$HB_FILE")
  ACTIVE_PRESET=$(jq -r '.active_preset // "?"' "$HB_FILE")
  LAST_QUICK=$(jq -r '.last_quick // ""' "$HB_FILE")
  SLEEP_UNTIL=$(jq -r '.sleep_until // ""' "$HB_FILE")
  TURBO_UNTIL=$(jq -r '.turbo_until // ""' "$HB_FILE")

  LAST_INTERACTION_TS=$(jq -r '.last_interaction_ts // ""' "$HB_FILE")
  if [[ -n "$LAST_INTERACTION_TS" && "$LAST_INTERACTION_TS" != "null" ]]; then
    INTERACTION_S=$(date -d "$LAST_INTERACTION_TS" +%s 2>/dev/null || echo 0)
    NOW_S=$(date +%s)
    INTERACTION_AGO="$(( (NOW_S - INTERACTION_S) / 60 ))m"
  fi
else
  WARNINGS+=("heartbeat-state.json missing or invalid")
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
# Source 3: current.md
# ---------------------------------------------------------------------------
CURRENT_FILE="$STATE_DIR/current.md"
FOCUS=""
WIP=""
BLOCKERS=""

if [[ -f "$CURRENT_FILE" ]]; then
  # sed range: match from header to next header OR end of file, strip header lines
  _extract_section() { sed -n "/^## $1/,/^## /{/^## /d;p}" "$CURRENT_FILE" | sed '/^$/d' | _html_escape | head -"$2"; }
  FOCUS=$(_extract_section "Active Focus" 5)
  WIP=$(_extract_section "Work in Progress" 10)
  BLOCKERS=$(_extract_section "Blockers" 5)
fi

# ---------------------------------------------------------------------------
# Source 4: today.md (fallback timeline)
# ---------------------------------------------------------------------------
TODAY_FILE="$STATE_DIR/today.md"
TODAY_LOG_LINES=""

if [[ -f "$TODAY_FILE" ]]; then
  # Extract heartbeat log lines, sort chronologically by time
  TODAY_LOG_LINES=$(grep -E '^\- \*\*[0-9]{2}:[0-9]{2}\*\*' "$TODAY_FILE" | sed 's/^- \*\*\([0-9:]*\)\*\*/\1\t&/' | sort -t$'\t' -k1,1r | cut -f2- | head -50 || true)
fi

# ---------------------------------------------------------------------------
# Source 5: Local task files (work queue)
# ---------------------------------------------------------------------------
TASK_SH="$PLUGIN_ROOT/skills/worker/task.sh"
WQ_PROGRESS=0
WQ_TODO=0
WQ_TRIAGE=0
WQ_DONE=0

if [[ -x "$TASK_SH" ]]; then
  WQ_PROGRESS=$("$TASK_SH" count in-progress 2>/dev/null || echo 0)
  WQ_TODO=$("$TASK_SH" count todo 2>/dev/null || echo 0)
  WQ_TRIAGE=$("$TASK_SH" count triage 2>/dev/null || echo 0)
  # Create today marker if missing (must exist before find -newer)
  [[ -f "${PWD}/state/tasks/.today-marker" ]] || touch -d "${TODAY} 00:00:00" "${PWD}/state/tasks/.today-marker" 2>/dev/null || true
  # Done today: count files in done/ modified today
  WQ_DONE=$(find "${PWD}/state/tasks/done/" -name "*.md" -newer "${PWD}/state/tasks/.today-marker" 2>/dev/null | wc -l || echo 0)
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
if [[ "$HAS_JSONL" == "true" ]]; then
  TIMELINE_HTML=$(echo "$TIMELINE_JSON" | jq -r '.[] | "<tr><td class=\"time\">\(.ts | split("T")[1] | split("+")[0] | .[0:5])</td><td class=\"agent agent-\(.agent)\">\(.agent)</td><td>\(.action)</td><td>\(.detail // "")</td><td class=\"tokens\">\(.tokens // "-")</td></tr>"' 2>/dev/null || echo "")
elif [[ -n "$TODAY_LOG_LINES" ]]; then
  # Fallback: parse today.md log lines
  TIMELINE_HTML=$(echo "$TODAY_LOG_LINES" | sed -E 's/^\- \*\*([0-9]{2}:[0-9]{2})\*\* \[([^]]+)\] (.*)/<tr><td class="time">\1<\/td><td class="agent">\2<\/td><td colspan="3">\3<\/td><\/tr>/' || echo "")
fi

# ---------------------------------------------------------------------------
# Build token stats HTML
# ---------------------------------------------------------------------------
TOKEN_STATS_HTML=""
if [[ "$HAS_JSONL" == "true" && "$TOTAL_TOKENS" =~ ^[0-9]+$ && "$TOTAL_TOKENS" -gt 0 ]]; then
  TOKEN_STATS_HTML=$(echo "$TOKEN_STATS_JSON" | jq -r --argjson total "$TOTAL_TOKENS" \
    '.[] | {agent, tokens, runs, pct: ((.tokens / $total * 100) | floor)} |
    "<div class=\"token-row\"><span class=\"agent agent-\(.agent)\">\(.agent)</span><div class=\"bar-container\"><div class=\"bar\" style=\"width: \(.pct)%\"></div></div><span class=\"token-value\">\(if .tokens >= 1000 then "\((.tokens / 1000 * 10 | floor) / 10)k" else "\(.tokens)" end) (\(.pct)%)</span><span class=\"runs\">\(.runs) runs</span></div>"' 2>/dev/null || echo "")
fi

# ---------------------------------------------------------------------------
# HTML Generation
# ---------------------------------------------------------------------------
TMP_FILE=$(mktemp "${OUTPUT}.tmp.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT

cat > "$TMP_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="${AUTO_REFRESH}">
<title>Kvído Dashboard</title>
<style>
:root {
  --bg: #1a1b26; --bg-raised: #1f2031; --card: #24283b; --card-hover: #292e42;
  --border: #414868; --border-subtle: #2f3549;
  --text: #a9b1d6; --text-bright: #c0caf5; --accent: #7aa2f7; --accent-glow: rgba(122,162,247,0.15);
  --success: #9ece6a; --success-glow: rgba(158,206,106,0.12);
  --warning: #e0af68; --warning-glow: rgba(224,175,104,0.12);
  --error: #f7768e; --error-glow: rgba(247,118,142,0.12);
  --purple: #bb9af7; --muted: #565f89;
}
@keyframes pulse-dot { 0%, 100% { opacity: 0.4; } 50% { opacity: 1; } }
*, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: var(--bg);
  background-image: repeating-linear-gradient(0deg, transparent, transparent 3px, rgba(255,255,255,0.008) 3px, rgba(255,255,255,0.008) 4px);
  color: var(--text); font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', monospace;
  font-size: 13px; line-height: 1.6; padding: 24px 20px; max-width: 1200px; margin: 0 auto;
  -webkit-font-smoothing: antialiased;
}
header { margin-bottom: 24px; }
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

.stat-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 20px; }
.stat {
  background: var(--card); border: 1px solid var(--border-subtle); border-radius: 6px;
  padding: 14px 12px; text-align: center; transition: border-color 0.2s, background 0.2s;
  position: relative; overflow: hidden;
}
.stat::before { content: ""; position: absolute; top: 0; left: 0; right: 0; height: 2px; opacity: 0; transition: opacity 0.2s; }
.stat:hover { background: var(--card-hover); border-color: var(--border); }
.stat:hover::before { opacity: 1; }
.stat .value { font-size: 1.7em; font-weight: 700; line-height: 1.2; font-variant-numeric: tabular-nums; }
.stat .label { font-size: 0.7em; color: var(--muted); margin-top: 4px; text-transform: uppercase; letter-spacing: 0.06em; }
.stat.progress .value { color: var(--accent); }
.stat.progress::before { background: var(--accent); }
.stat.todo .value { color: var(--text-bright); }
.stat.todo::before { background: var(--text); }
.stat.triage .value { color: var(--warning); }
.stat.triage::before { background: var(--warning); }
.stat.done .value { color: var(--success); }
.stat.done::before { background: var(--success); }

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

table { width: 100%; border-collapse: collapse; font-size: 0.82em; }
thead th { color: var(--muted); font-weight: 500; font-size: 0.85em; text-transform: uppercase; letter-spacing: 0.06em; padding: 8px; border-bottom: 1px solid var(--border); }
tbody td { padding: 7px 8px; border-bottom: 1px solid var(--border-subtle); transition: background 0.15s; }
tbody tr:hover td { background: rgba(122,162,247,0.04); }
tbody tr:last-child td { border-bottom: none; }
.time { color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
.tokens { color: var(--muted); text-align: right; font-variant-numeric: tabular-nums; }
.agent { font-weight: 600; }
.agent-planner { color: var(--accent); }
.agent-worker { color: var(--success); }
.agent-notifier { color: var(--muted); }
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

footer { text-align: center; color: var(--muted); font-size: 0.7em; padding: 20px 0 8px; opacity: 0.5; }

@media (max-width: 768px) {
  body { padding: 16px 12px; font-size: 12px; }
  .stat-grid { grid-template-columns: repeat(2, 1fr); gap: 8px; }
  .stat .value { font-size: 1.4em; }
  .grid { grid-template-columns: 1fr; }
  .meta { gap: 4px; }
  .token-row { gap: 6px; }
  .token-row .agent { min-width: 60px; font-size: 0.75em; }
  .token-value { min-width: 70px; }
}
@media (max-width: 480px) {
  .stat-grid { grid-template-columns: repeat(2, 1fr); }
  .meta-tag { font-size: 0.72em; padding: 1px 5px; }
  thead th { font-size: 0.75em; }
}
</style>
</head>
<body>
<header>
<h1>Kvído Dashboard</h1>
<div class="meta">
  <span class="meta-tag">${TODAY}</span>
  <span class="meta-tag">#${ITERATION}</span>
  <span class="meta-tag">${ACTIVE_PRESET}</span>
  <span class="meta-tag zone-badge zone-${ZONE}">${ZONE}</span>
  <span class="meta-tag">interaction ${INTERACTION_AGO} ago</span>
  <span class="meta-tag">$(date +%H:%M:%S)</span>
</div>
</header>

${WARNINGS_HTML}

<div class="stat-grid">
  <div class="stat progress"><div class="value">${WQ_PROGRESS}</div><div class="label">In Progress</div></div>
  <div class="stat todo"><div class="value">${WQ_TODO}</div><div class="label">Todo</div></div>
  <div class="stat triage"><div class="value">${WQ_TRIAGE}</div><div class="label">Triage</div></div>
  <div class="stat done"><div class="value">${WQ_DONE}</div><div class="label">Done Today</div></div>
</div>

<div class="grid">
<div class="card">
<h2>Focus & WIP</h2>
$(if [[ -n "$FOCUS" ]]; then echo "<div class=\"focus-text\"><strong>Focus:</strong> ${FOCUS}</div>"; else echo '<div class="empty">No focus set</div>'; fi)
$(if [[ -n "$WIP" ]]; then echo "<div class=\"focus-text\" style=\"margin-top:8px\"><strong>WIP:</strong><br>${WIP//$'\n'/<br>}</div>"; fi)
$(if [[ -n "$BLOCKERS" ]]; then echo "<div class=\"blockers\" style=\"margin-top:8px\"><strong>Blockers:</strong><br>${BLOCKERS//$'\n'/<br>}</div>"; fi)
</div>

$(if [[ -n "$TOKEN_STATS_HTML" ]]; then cat << TOKENEOF
<div class="card">
<h2>Token Usage ($( [[ $TOTAL_TOKENS -ge 1000 ]] && echo "$(( TOTAL_TOKENS / 1000 )).$(( TOTAL_TOKENS % 1000 / 100 ))k" || echo "${TOTAL_TOKENS}" ) total, ${TOTAL_RUNS} runs)</h2>
${TOKEN_STATS_HTML}
</div>
TOKENEOF
fi)
</div>

<div class="card" style="margin-bottom: 16px">
<h2>Activity Timeline</h2>
$(if [[ -n "$TIMELINE_HTML" ]]; then cat << TABLEEOF
<table>
<thead><tr><th>Time</th><th>Agent</th><th>Action</th><th>Detail</th><th style="text-align:right">Tokens</th></tr></thead>
<tbody>
${TIMELINE_HTML}
</tbody>
</table>
TABLEEOF
else
  echo '<div class="empty">No activity data — waiting for activity-log.jsonl (issue #7)</div>'
fi)
</div>

<footer>auto-refresh ${AUTO_REFRESH}s</footer>
</body>
</html>
HTMLEOF

mv "$TMP_FILE" "$OUTPUT"
