#!/usr/bin/env bash
# heartbeat.sh — Pure data gathering: time, zone, adaptive interval, Slack DM read, state update.
# Orchestration logic (dispatch tracking, dependencies) is in heartbeat.md via TaskCreate/TaskUpdate.
# Output: key=value lines + CHAT_MESSAGES block for LLM consumption.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"

# Lazy migration — runs once if old state files exist
kvido migrate 2>/dev/null || echo "ERROR: kvido migrate failed (exit $?)" >&2

TIMESTAMP="$(date -Iseconds)"
HOUR=$(date +%-H)

ITERATION=$(kvido state get heartbeat.iteration_count 2>/dev/null || echo 0)

# Night detection (informational only — no tier logic)
if (( HOUR >= 16 || HOUR < 6 )); then
  NIGHT="true"
else
  NIGHT="false"
fi

# Adaptive interval — calculate TARGET_PRESET
ACTIVE_PRESET=$(kvido state get heartbeat.active_preset 2>/dev/null || echo "10m")
LAST_INTERACTION_TS=$(kvido state get heartbeat.last_interaction_ts 2>/dev/null || echo "")
CRON_JOB_ID=$(kvido state get heartbeat.cron_job_id 2>/dev/null || echo "")
TURBO_UNTIL=$(kvido state get heartbeat.turbo_until 2>/dev/null || echo "")
SLEEP_UNTIL=$(kvido state get heartbeat.sleep_until 2>/dev/null || echo "")

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
    kvido state set heartbeat.turbo_until ""
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
    kvido state set heartbeat.sleep_until ""
    SLEEP_UNTIL=""
  fi
fi

# Load adaptive rules from central settings.json via config.sh
CONFIG="$PLUGIN_ROOT/scripts/config.sh"

WH_START=$($CONFIG 'skills.heartbeat.wh_start')
WH_END=$($CONFIG 'skills.heartbeat.wh_end')
WH_INTERACTION_WINDOW=$($CONFIG 'skills.heartbeat.wh_interaction_window_minutes')
WH_AFTER_INTERACTION=$($CONFIG 'skills.heartbeat.wh_after_interaction')
WH_MIN_INTERVAL=$($CONFIG 'skills.heartbeat.wh_min_interval')

# Parse off_hours decay from flat config
declare -A OH_DECAY_MAX
declare -A OH_DECAY_PRESET
OH_DECAY_COUNT=0
for decay_key in $($CONFIG --keys 'skills.heartbeat.decay'); do
  OH_DECAY_MAX[$OH_DECAY_COUNT]="$decay_key"
  OH_DECAY_PRESET[$OH_DECAY_COUNT]=$($CONFIG "skills.heartbeat.decay.${decay_key}.preset")
  OH_DECAY_COUNT=$((OH_DECAY_COUNT + 1))
done

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
  # If a new interaction occurs outside working hours, switch to a shorter interval
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

# --- Resolve owner user ID ---
# 1. Try kvido config 'slack.user_id' (resolves $SLACK_USER_ID from .env)
# 2. Fall back to $SLACK_USER_ID env var directly
# 3. Fall back to cached value in state (heartbeat.owner_user_id)
OWNER_USER_ID=$($CONFIG 'slack.user_id' '' 2>/dev/null || echo "ERROR: failed to read slack.user_id config (exit $?)" >&2)
if [[ -z "$OWNER_USER_ID" || "$OWNER_USER_ID" == "null" ]]; then
  OWNER_USER_ID="${SLACK_USER_ID:-}"
fi
if [[ -z "$OWNER_USER_ID" || "$OWNER_USER_ID" == "null" ]]; then
  OWNER_USER_ID=$(kvido state get heartbeat.owner_user_id 2>/dev/null || echo "")
fi
if [[ -z "$OWNER_USER_ID" || "$OWNER_USER_ID" == "null" ]]; then
  echo "WARNING: slack.user_id not configured — message annotation disabled. Set SLACK_USER_ID in .env or slack.user_id in settings.json." >&2
fi

# --- Extended: Chat messages, state update ---

# Read last 15 Slack DM messages in heartbeat format (compact key=value lines)
# Format per top-level msg: ts=... user=... text="..." [reactions=emoji1,emoji2] [reply_count=N] [latest_reply=...]
# Thread replies (qualifying threads): indented with "  ┗ ts=... user=... text="..." [reactions=...]"
# Pass --oldest with last_chat_ts so slack.sh knows which threads qualify for reply fetching
SLACK_SH="$PLUGIN_ROOT/scripts/slack/slack.sh"
LAST_CHAT_TS=$(kvido state get heartbeat.last_chat_ts 2>/dev/null || echo "")
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

# Annotate messages: replace raw "user=<ID>" with "user:" (owner) or "bot:" (others).
# This allows the heartbeat skill to distinguish owner messages without comparing raw IDs.
# The annotation applies to both top-level messages and indented thread replies.
if [[ -n "$OWNER_USER_ID" && -n "$CHAT_MESSAGES" ]]; then
  ANNOTATED=""
  while IFS= read -r line; do
    # Extract user ID from "user=<ID>" token
    if [[ "$line" =~ user=([^[:space:]]+) ]]; then
      msg_user="${BASH_REMATCH[1]}"
      if [[ "$msg_user" == "$OWNER_USER_ID" ]]; then
        line="${line/user=$msg_user/user:}"
      else
        line="${line/user=$msg_user/bot:}"
      fi
    fi
    ANNOTATED="${ANNOTATED}${line}"$'\n'
  done <<< "$CHAT_MESSAGES"
  # Strip trailing newline added by loop
  CHAT_MESSAGES="${ANNOTATED%$'\n'}"
fi

# Update state — increment iteration and set last_heartbeat
kvido state increment heartbeat.iteration_count
kvido state set heartbeat.last_heartbeat "$TIMESTAMP"

# Planner throttle — run every N-th iteration (default 3)
PLANNING_INTERVAL=$($CONFIG 'skills.planner.planning_interval')
if (( PLANNING_INTERVAL < 1 )); then PLANNING_INTERVAL=1; fi
if (( ITERATION % PLANNING_INTERVAL == 0 )); then
  PLANNER_DUE="true"
else
  PLANNER_DUE="false"
fi

# Dashboard generation (non-fatal — log errors to stderr)
DASH_ENABLED=$($CONFIG 'skills.dashboard.enabled' 'true')
if [[ "$DASH_ENABLED" != "false" ]]; then
  "$SCRIPT_DIR/generate-dashboard.sh" 2>/dev/null || echo "ERROR: generate-dashboard.sh failed (exit $?)" >&2
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
echo "PLANNER_DUE=$PLANNER_DUE"
echo "INTERACTION_AGO_MIN=$INTERACTION_AGO_MIN"
echo "OWNER_USER_ID=$OWNER_USER_ID"
# CHAT_MESSAGES is compact key=value lines (--heartbeat format), output last
# Top-level: ts=... user:|bot: text="..." [reactions=...] [reply_count=N] [latest_reply=...]
# Thread replies: "  ┗ ts=... user:|bot: text="..." [reactions=...]"
# user: = owner (OWNER_USER_ID), bot: = any other sender
# Empty lines separate top-level messages
echo "CHAT_MESSAGES_START"
echo "$CHAT_MESSAGES"
echo "CHAT_MESSAGES_END"
