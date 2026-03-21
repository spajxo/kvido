#!/usr/bin/env bash
# heartbeat.sh — Pure data gathering: time, zone, adaptive interval, Slack DM read, worker queue check, state update.
# Orchestration logic (dispatch tracking, dependencies) is in SKILL.md via TodoWrite/TodoRead.
# Output: key=value lines + CHAT_MESSAGES block for LLM consumption.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_FILE="${PWD}/state/heartbeat-state.json"

TIMESTAMP="$(date -Iseconds)"
HOUR=$(date +%-H)

# Fix 3: JSON guard — validate STATE_FILE before parsing, reset to {} if invalid
if [[ -f "$STATE_FILE" ]]; then
  if ! jq empty "$STATE_FILE" 2>/dev/null; then
    echo '{}' > "$STATE_FILE"
  fi
  ITERATION=$(jq -r '.iteration_count // 0' "$STATE_FILE" 2>/dev/null || echo 0)
else
  ITERATION=0
fi

# Night detection (informational only — no tier logic)
if (( HOUR >= 16 || HOUR < 6 )); then
  NIGHT="true"
else
  NIGHT="false"
fi

# Adaptive interval — calculate TARGET_PRESET
ACTIVE_PRESET=$(jq -r '.active_preset // "10m"' "$STATE_FILE" 2>/dev/null || echo "10m")
LAST_INTERACTION_TS=$(jq -r '.last_interaction_ts // ""' "$STATE_FILE" 2>/dev/null || echo "")
CRON_JOB_ID=$(jq -r '.cron_job_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
TURBO_UNTIL=$(jq -r '.turbo_until // ""' "$STATE_FILE" 2>/dev/null || echo "")
SLEEP_UNTIL=$(jq -r '.sleep_until // ""' "$STATE_FILE" 2>/dev/null || echo "")

NOW_S=$(date +%s)

if [[ -n "$LAST_INTERACTION_TS" && "$LAST_INTERACTION_TS" != "null" ]]; then
  INTERACTION_S=$(date -d "$LAST_INTERACTION_TS" +%s 2>/dev/null || echo 0)
  INTERACTION_AGO_MIN=$(( (NOW_S - INTERACTION_S) / 60 ))
else
  INTERACTION_AGO_MIN=9999
fi

# Turbo mode check — overrides adaptive flow if turbo_until is in the future
TURBO_ACTIVE="false"
if [[ -n "$TURBO_UNTIL" && "$TURBO_UNTIL" != "null" ]]; then
  TURBO_S=$(date -d "$TURBO_UNTIL" +%s 2>/dev/null || echo 0)
  if (( TURBO_S > NOW_S )); then
    TURBO_ACTIVE="true"
  else
    # Turbo expired — clear it
    "$SCRIPT_DIR/heartbeat-state.sh" set turbo_until ""
  fi
fi

# Sleep mode check — pauses heartbeat if sleep_until is in the future
SLEEP_ACTIVE="false"
if [[ -n "$SLEEP_UNTIL" && "$SLEEP_UNTIL" != "null" ]]; then
  SLEEP_S=$(date -d "$SLEEP_UNTIL" +%s 2>/dev/null || echo 0)
  if (( SLEEP_S > NOW_S )); then
    SLEEP_ACTIVE="true"
  else
    # Sleep expired — clear it
    "$SCRIPT_DIR/heartbeat-state.sh" set sleep_until ""
    SLEEP_UNTIL=""
  fi
fi

# Load adaptive rules from centrální kvido.local.md via config.sh
CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/config.sh"

WH_START=$($CONFIG '.skills.heartbeat.adaptive.working_hours.start')
WH_END=$($CONFIG '.skills.heartbeat.adaptive.working_hours.end')
WH_INTERACTION_WINDOW=$($CONFIG '.skills.heartbeat.adaptive.working_hours.interaction_window_minutes')
WH_AFTER_INTERACTION=$($CONFIG '.skills.heartbeat.adaptive.working_hours.after_interaction')
WH_MIN_INTERVAL=$($CONFIG '.skills.heartbeat.adaptive.working_hours.min_interval')

# Parse off_hours decay array via yq JSON output
declare -A OH_DECAY_MAX
declare -A OH_DECAY_PRESET
OH_DECAY_COUNT=0
while IFS=$'\t' read -r max_val preset_val; do
  OH_DECAY_MAX[$OH_DECAY_COUNT]="$max_val"
  OH_DECAY_PRESET[$OH_DECAY_COUNT]="$preset_val"
  OH_DECAY_COUNT=$((OH_DECAY_COUNT + 1))
done < <($CONFIG '.skills.heartbeat.adaptive.off_hours.decay[] | [(.max_minutes // "null" | tostring), .preset] | @tsv')

DOW=$(date +%u)
# Sleep mode takes priority over all adaptive rules (including turbo)
if [[ "$SLEEP_ACTIVE" == "true" ]]; then
  TARGET_PRESET="sleep"
  ZONE="sleep"
# Turbo mode takes priority over adaptive rules
elif [[ "$TURBO_ACTIVE" == "true" ]]; then
  TARGET_PRESET="1m"
  ZONE="turbo"
elif (( DOW >= 1 && DOW <= 5 && HOUR >= WH_START && HOUR < WH_END )); then
  ZONE="working_hours"
  if (( INTERACTION_AGO_MIN < WH_INTERACTION_WINDOW )); then
    TARGET_PRESET="$WH_AFTER_INTERACTION"
  else
    TARGET_PRESET="$WH_MIN_INTERVAL"
  fi
else
  ZONE="off_hours"
  # Pokud je nová interakce i mimo working hours, přepni na kratší interval
  if (( INTERACTION_AGO_MIN < WH_INTERACTION_WINDOW )); then
    TARGET_PRESET="$WH_AFTER_INTERACTION"
  else
    TARGET_PRESET=""
    for (( i=0; i<OH_DECAY_COUNT; i++ )); do
      max_val="${OH_DECAY_MAX[$i]:-null}"
      preset_val="${OH_DECAY_PRESET[$i]:-}"
      # Fix 5: null check before arithmetic — skip arithmetic if max_val is null/empty
      if [[ "$max_val" == "null" || -z "$max_val" ]] || (( INTERACTION_AGO_MIN < max_val )); then
        TARGET_PRESET="$preset_val"
        break
      fi
    done
    [[ -z "$TARGET_PRESET" ]] && TARGET_PRESET="60m"
  fi
fi

# Planner dispatch check
PLANNING_INTERVAL=$($CONFIG '.skills.planner.planning_interval')
if (( ITERATION % PLANNING_INTERVAL == 0 )); then
  PLANNER_DUE="true"
else
  PLANNER_DUE="false"
fi

# --- Extended: Chat messages, worker check, state update ---

# Read last 15 Slack DM messages in heartbeat format (compact key=value lines)
# Format per top-level msg: ts=... user=... text="..." [reactions=emoji1,emoji2] [reply_count=N] [latest_reply=...]
# Thread replies (qualifying threads): indented with "  ┗ ts=... user=... text="..." [reactions=...]"
# Pass --oldest with last_chat_ts so slack.sh knows which threads qualify for reply fetching
SLACK_SH="$PLUGIN_ROOT/skills/slack/slack.sh"
LAST_CHAT_TS=$(jq -r '.last_chat_ts // ""' "$STATE_FILE" 2>/dev/null || echo "")
# Pass last_chat_ts via --last-chat-ts so slack.sh can qualify threads with new replies
# (threads where latest_reply > last_chat_ts get their replies fetched inline)
# Note: --last-chat-ts does NOT filter history API — all 15 messages are returned,
# but only threads with new replies are expanded.
if [[ -n "$LAST_CHAT_TS" && "$LAST_CHAT_TS" != "null" ]]; then
  CHAT_MESSAGES=$("$SLACK_SH" read --limit 15 --last-chat-ts "$LAST_CHAT_TS" --heartbeat 2>/dev/null || echo "")
else
  CHAT_MESSAGES=$("$SLACK_SH" read --limit 15 --heartbeat 2>/dev/null || echo "")
fi
# Empty string means no messages — that is valid (no fallback needed)

# Check next worker task (returns issue number or empty)
WORK_NEXT_SH="$PLUGIN_ROOT/skills/worker/work-next.sh"
NEXT_TASK=$("$WORK_NEXT_SH" 2>/dev/null || echo "")

# Update state — increment iteration and set last_quick
"$SCRIPT_DIR/heartbeat-state.sh" increment iteration_count
"$SCRIPT_DIR/heartbeat-state.sh" set last_quick "$TIMESTAMP"

# Dashboard generation (never fails heartbeat — || true)
DASH_ENABLED=$($CONFIG '.skills.dashboard.enabled // true' 2>/dev/null || echo "true")
if [[ "$DASH_ENABLED" != "false" ]]; then
  "$SCRIPT_DIR/generate-dashboard.sh" 2>/dev/null || true
fi

# --- Output ---

echo "TIMESTAMP=$TIMESTAMP"
echo "ITERATION=$ITERATION"
echo "NIGHT=$NIGHT"
echo "ZONE=$ZONE"
echo "TURBO_ACTIVE=$TURBO_ACTIVE"
echo "TURBO_UNTIL=$TURBO_UNTIL"
echo "SLEEP_ACTIVE=$SLEEP_ACTIVE"
echo "SLEEP_UNTIL=$SLEEP_UNTIL"
echo "TARGET_PRESET=$TARGET_PRESET"
echo "ACTIVE_PRESET=$ACTIVE_PRESET"
echo "CRON_JOB_ID=$CRON_JOB_ID"
echo "INTERACTION_AGO_MIN=$INTERACTION_AGO_MIN"
echo "PLANNER_DUE=$PLANNER_DUE"
echo "NEXT_TASK=$NEXT_TASK"
# CHAT_MESSAGES is compact key=value lines (--heartbeat format), output last
# Top-level: ts=... user=... text="..." [reactions=...] [reply_count=N] [latest_reply=...]
# Thread replies: "  ┗ ts=... user=... text="..." [reactions=...]"
# Empty lines separate top-level messages
echo "CHAT_MESSAGES_START"
echo "$CHAT_MESSAGES"
echo "CHAT_MESSAGES_END"
