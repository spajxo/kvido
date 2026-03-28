#!/usr/bin/env bash
# config-keys.sh — Migrate settings.json keys from old format to new format
# Called from migrate.sh on startup. Idempotent.
#
# Migrates settings.json keys from old nesting structure to flat top-level format:
#   sources.<name>.* → <name>.*
#   skills.<name>.* → <name>.*
#
# Also renames 'sources.slack' keys within the top-level 'slack' section:
#   Old: sources.slack.* (nested under sources → slack)
#   New: slack.* (moved to top-level slack, merged with other slack config)
#
# Examples of key migrations:
#   sources.gitlab.repos → gitlab.repos
#   sources.jira.projects → jira.projects
#   sources.calendar.categories → calendar.categories
#   sources.slack.channels → slack.channels
#   sources.slack.dm_channels → slack.dm_channels
#   skills.heartbeat.wh_start → heartbeat.wh_start
#   skills.triage.wip_limit → triage.wip_limit
#   skills.interests.topics → interests.topics
#   skills.self_improver.github_issues.enabled → self_improver.github_issues.enabled
#   skills.daily_questions.enabled → daily_questions.enabled

set -euo pipefail

KVIDO_HOME="${KVIDO_HOME:-$HOME/.config/kvido}"
CONFIG_FILE="${KVIDO_HOME}/settings.json"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

# Backup original for safety (but don't fail if already backed up)
BACKUP="${CONFIG_FILE}.pre-0.28.0"
if [[ ! -f "$BACKUP" ]]; then
  cp "$CONFIG_FILE" "$BACKUP"
fi

# Use jq to migrate the structure:
# 1. Extract all sources.* and rename them to top-level
# 2. Extract all skills.* and rename them to top-level
# 3. Keep all other top-level keys (like slack top-level config)
# 4. Merge sources.slack into slack top-level (slack config already exists)

# Create new config with migrated keys
jq '
  # Start with any existing top-level keys (slack, etc.)
  . as $root |

  # Extract top-level keys that are not "sources" or "skills"
  reduce ($root | keys[] | select(. != "sources" and . != "skills")) as $key (
    {};
    .[$key] = $root[$key]
  ) |

  # Migrate sources.* to top-level (except sources.slack which is handled separately)
  . + (
    if $root.sources then
      reduce ($root.sources | keys[] | select(. != "slack")) as $source (
        {};
        .[$source] = $root.sources[$source]
      )
    else {} end
  ) |

  # Migrate sources.slack into slack (merge with existing slack config at top level)
  if $root.sources.slack then
    .slack = (
      (.slack // {}) + $root.sources.slack
    )
  else . end |

  # Migrate skills.* to top-level
  . + (
    if $root.skills then
      reduce ($root.skills | keys[]) as $skill (
        {};
        .[$skill] = $root.skills[$skill]
      )
    else {} end
  )
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"

# Atomic swap
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "config-keys: settings.json migrated to new key format (old version backed up to $BACKUP)" >&2
