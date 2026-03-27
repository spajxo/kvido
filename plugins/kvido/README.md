# kvido

Personal AI workflow assistant for Claude Code. Orchestrates heartbeat, planner, worker, and chat agents to manage tasks, monitor sources, and deliver notifications via Slack.

## Installation

```bash
claude plugin marketplace install kvido
```

Or add to your project's `.claude/plugins/`:

```bash
claude plugin add ./plugins/kvido
```

## Configuration

1. Copy `settings.json.example` to `~/.config/kvido/settings.json`
2. Create `~/.config/kvido/.env` with Slack tokens
3. Run `/kvido:setup` to verify

See [CLAUDE.md](../../CLAUDE.md) for full architecture and configuration reference.

## Components

| Type | Count | Purpose |
|------|-------|---------|
| Commands | 2 | heartbeat, setup |
| Agents | 9 | planner, gatherer, triager, worker, chat-agent, librarian, scout, project-enricher, self-improver |
| Hooks | 2 | SessionStart, PreCompact |
| Scripts | 15 | CLI, state, config, slack, tasks, dashboard |

## License

MIT
