# Project Rules

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `build`, `ci`, `test`, `style`, `perf`.

Scope is optional but encouraged (e.g. `docs(readme)`, `build(makefile)`, `feat(app)`).

## Code

- Shell scripts use `set -euo pipefail`
- All shared constants live in `config.sh` — scripts source it, not duplicate values
- Payload scripts (in `payload/`) run on the target machine — keep them self-contained with no build-time dependencies

## README

- Keep the README user-friendly and minimal — no CLI commands, no localhost URLs
- Technical details go in `docs/`

## n8n API

Credentials are stored in `.env` at project root. To interact with the local n8n instance:

```bash
source .env
```

### REST API (full CRUD — create, update, delete workflows, credentials, etc.)
```bash
curl -s "$N8N_URL/api/v1/workflows" \
  -H "X-N8N-API-KEY: $N8N_API_KEY"
```

### MCP Server (read-only + execute — search_workflows, get_workflow_details, execute_workflow)
```bash
curl -s -N -X POST "$N8N_URL/mcp-server/http" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: $N8N_MCP_TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"TOOL_NAME","arguments":{}}}'
```

Prefer the REST API for creating/modifying workflows. Use the MCP endpoint for executing workflows with chat/webhook inputs.
