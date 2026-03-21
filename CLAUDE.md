# CLAUDE.md

This repository is a **Claude Code plugin marketplace** containing the core kvido assistant and optional source plugins.

## Structure

- `.claude-plugin/marketplace.json` — plugin registry listing all available plugins
- `plugins/kvido/` — core assistant plugin
- `plugins/kvido-*/` — source plugins (gitlab, jira, slack, calendar, gmail, sessions)

For architecture details, see `plugins/kvido/CLAUDE.md`.

## Working on this codebase

- Each plugin is self-contained in its `plugins/<name>/` directory with its own `.claude-plugin/plugin.json`
- Source plugins contain only `skills/source-*/` — they are discovered at runtime by the core plugin via `skills/discover-sources.sh`
- No build step, no tests — validate by reading plugin conventions and running `/setup` health check
