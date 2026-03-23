# Jira Setup

## Prerequisites
| Tool | Required | Check |
|------|----------|-------|
| acli or Atlassian MCP | yes (either) | command -v acli or MCP available |

## Config Keys
| Key | Required | Check |
|-----|----------|-------|
| sources.jira.projects | yes, at least one child with filter | kvido config --keys 'sources.jira.projects' returns non-empty |
