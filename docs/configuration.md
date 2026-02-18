# Configuration

## Environment variables

Set by the installer in the LaunchAgent plist (`~/Library/LaunchAgents/com.n8n.local.plist`):

| Variable | Default | Purpose |
| --- | --- | --- |
| `N8N_PORT` | `5678` | n8n HTTP port |
| `N8N_HOST` | `localhost` | Bind address |
| `N8N_SECURE_COOKIE` | `false` | Disabled for local HTTP access |
| `DB_SQLITE_POOL_SIZE` | `4` | Enables WAL mode for SQLite |
| `N8N_USER_FOLDER` | `~` | Where `.n8n/` data is stored |
| `N8N_DIAGNOSTICS_ENABLED` | `false` | Telemetry disabled |
| `N8N_VERSION_NOTIFICATIONS_ENABLED` | `false` | Update check notifications disabled |
| `EXECUTIONS_DATA_PRUNE` | `true` | Auto-prune old execution data |
| `EXECUTIONS_DATA_MAX_AGE` | `336` | Prune executions older than 14 days (hours) |

## File locations

| Path | Purpose |
| --- | --- |
| `~/.n8n-local/` | Installation directory (Node.js, n8n, scripts) |
| `~/.n8n-local/logs/n8n.log` | n8n output log (auto-rotated at 50 MB) |
| `~/.n8n-local/.port` | Persisted port number |
| `~/.n8n-local/.version` | Installed n8n version |
| `~/.n8n/` | n8n user data (workflows, credentials, settings) |
| `~/Library/LaunchAgents/com.n8n.local.plist` | LaunchAgent (auto-start on login) |
| `~/Applications/n8n.app` | Symlink to the native app |

## CLI

A `n8n-dmg` shell alias is added to `~/.zshrc` during installation. Open a new terminal after install (or run `source ~/.zshrc`).

```bash
n8n-dmg start     # Start n8n service
n8n-dmg stop      # Stop n8n service
n8n-dmg restart   # Restart n8n service
n8n-dmg status    # Show if n8n is running + PID
n8n-dmg logs      # Tail the n8n logs
n8n-dmg open      # Open n8n in default browser
n8n-dmg ui        # Open native n8n app
```
