# n8n for macOS

Run [n8n](https://n8n.io) locally on your Mac as a native app. No internet, no Homebrew, no sudo required.

- Works on Apple Silicon and Intel Macs
- Runs in its own window — no browser needed
- Starts automatically on login
- Nothing installed outside your home folder

## Build the DMG

Requires Xcode Command Line Tools (`xcode-select --install`) and an internet connection.

```bash
make clean && make
```

The output is `dist/n8n-local-installer.dmg`. See [Building from source](docs/building.md) for details.

## Install

1. Open the `.dmg` file
2. Right-click **Install n8n.app** > **Open** (needed once because the app is unsigned)
3. The installer runs — pick a port or press Enter for the default (5678)
4. n8n opens automatically — create your account on the setup page

## Open n8n

After installation, open n8n from **Finder** or **Spotlight**:

- **Finder** — go to `~/Applications` and double-click **n8n**
- **Spotlight** — press `Cmd + Space`, type **n8n**, press Enter

The app starts the n8n service automatically and reconnects if it restarts.

Use the **Service** menu in the menu bar to start, stop, restart, or view logs.

## Upgrade

Open the `.dmg` again and run **Install n8n.app**. The installer upgrades in place — your workflows and credentials are preserved.

## Uninstall

```bash
~/.n8n-local/uninstall.sh
```

Your workflow data (`~/.n8n/`) is preserved unless you choose to delete it.

## Resources

### Build workflows with AI

[**n8n-skills**](https://github.com/czlonkowski/n8n-skills) by Romuald Członkowski — a set of
Claude Code skills that teach Claude how to design and configure n8n workflows. Install them
globally so Claude can help build workflows in any project:

| Skill | What it helps with |
|-------|--------------------|
| `n8n-workflow-patterns` | Proven architectures: webhook, API, database, AI agent, batch, scheduled |
| `n8n-node-configuration` | Operation-aware node setup — required fields and property dependencies |
| `n8n-expression-syntax` | n8n expressions (`{{ }}`, `$json`/`$node`) and fixing common errors |
| `n8n-code-javascript` | Writing JavaScript in Code nodes (`$input`/`$helpers`, loops, dates) |
| `n8n-code-python` | Writing Python in Code nodes |
| `n8n-validation-expert` | Reading and fixing validation errors and warnings |
| `n8n-mcp-tools-expert` | Using the n8n MCP tools effectively |

See the [n8n-skills installation guide](https://github.com/czlonkowski/n8n-skills#-installation)
for setup.

### Environment variables

API access is configured through a `.env` file at the project root:

| Variable | Description |
|----------|-------------|
| `N8N_URL` | Base URL of your local n8n instance (e.g. `http://localhost:5678`) |
| `N8N_API_KEY` | REST API key for full CRUD — create, update, and delete workflows and credentials (sent as the `X-N8N-API-KEY` header) |
| `N8N_MCP_TOKEN` | Bearer token for the built-in MCP server — read-and-execute access (`search_workflows`, `get_workflow_details`, `execute_workflow`) |

Generate the API key from **Settings → n8n API** in the n8n app, and the MCP token from the
MCP server settings.

### Connect Claude to your local n8n

Let Claude query your running instance by registering the built-in n8n MCP server. The token
lives in `.env` at the project root:

```bash
source .env
claude mcp add --transport http n8n "$N8N_URL/mcp-server/http" \
  --header "Authorization: Bearer $N8N_MCP_TOKEN" \
  --scope user
```

Verify with `claude mcp list` (or `/mcp` inside a session) — it exposes `search_workflows`,
`get_workflow_details`, and `execute_workflow`. These are read-and-execute only; creating or
editing workflows uses the n8n REST API (`X-N8N-API-KEY`).

## More

- [Building from source](docs/building.md)
- [Configuration & CLI](docs/configuration.md)
- [Troubleshooting](docs/troubleshooting.md)
