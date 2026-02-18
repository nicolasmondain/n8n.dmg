# n8n macOS DMG Installer

Self-contained installer for running [n8n](https://n8n.io) locally on macOS. No internet, no Homebrew, no sudo required.

## What it does

- Bundles Node.js + n8n into a single `.dmg` file
- Supports both Apple Silicon (arm64) and Intel (x64) Macs
- Installs to `~/.n8n-local/` (no system paths touched)
- Configures a LaunchAgent so n8n starts automatically on login
- Provides a **native macOS app** — n8n runs in its own window (no browser needed)
- Provides `n8n-dmg` CLI for managing the service

## Build

Requires macOS with Apple Silicon (Rosetta 2 used for x64 cross-compilation) and Xcode Command Line Tools (for `swiftc`).

```bash
make clean && make
```

Output: `dist/n8n-local-installer.dmg`

Individual targets:

```bash
make check-deps      # Verify build tools (including swiftc)
make download-node   # Download Node.js binaries
make bundle-n8n      # Install n8n per architecture
make fetch-icon      # Generate app icon from SVG
make app-bundle      # Create the installer .app wrapper
make manager-app     # Compile native n8n app (universal binary)
make dmg             # Assemble final DMG
make clean           # Remove build artifacts
```

## Distribution

Share the `.dmg` file. Recipients double-click to mount, then double-click `Install n8n.app`.

Since the app is unsigned, macOS Gatekeeper will block it. Users need to right-click > Open (or System Settings > Privacy & Security > Open Anyway).

## Installation

1. Mount the DMG
2. Double-click **Install n8n.app**
3. Terminal opens — the installer prompts for a port (default: 5678)
4. n8n starts and the native **n8n app** opens automatically
5. Go to `http://localhost:5678/setup` to create your owner account (first launch only)

To use a custom port without the prompt:

```bash
bash /Volumes/n8n\ Installer/.payload/install.sh --port=3000
```

## Native App

After installation, n8n runs in a native macOS window — no browser needed. The app is installed to `~/.n8n-local/n8n.app` and symlinked to `~/Applications/n8n.app` for Spotlight discovery.

Open it with:

```bash
n8n-dmg ui
```

The native app provides:

- n8n UI in a WKWebView (native window)
- Auto-starts n8n service on launch
- Auto-reconnects if the service restarts
- Service menu: Start / Stop / Restart / View Logs

## Usage

After installation, manage n8n with `n8n-dmg`:

```bash
n8n-dmg start     # Start n8n service
n8n-dmg stop      # Stop n8n service
n8n-dmg restart   # Restart n8n service
n8n-dmg status    # Show if n8n is running + PID
n8n-dmg logs      # Tail the n8n logs
n8n-dmg open      # Open n8n in browser
n8n-dmg ui        # Open native n8n app
```

> Open a new terminal after install, or run `source ~/.zshrc` first.

## Uninstall

```bash
~/.n8n-local/uninstall.sh
```

This removes the service, binaries, native app, and helper scripts. Your workflow data (`~/.n8n/`) is preserved unless you choose to delete it.

## Troubleshooting

**n8n doesn't start after install:**

```bash
n8n-dmg status          # Check service status
n8n-dmg logs            # Check logs for errors
```

**Change the port after installation:**

```bash
# Reinstall with a different port
bash ~/.n8n-local/uninstall.sh
# Then re-run the installer from the DMG with --port=<new_port>
```

**Port already in use:**

```bash
lsof -i :5678           # Find the process using the port
```

**Service won't stop:**

```bash
launchctl bootout gui/$(id -u)/com.n8n.local
```

**Manual LaunchAgent control:**

```bash
# Start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.n8n.local.plist
```

```bash
# Stop
launchctl bootout gui/$(id -u)/com.n8n.local
```

**Log locations:**

- n8n output: `~/.n8n-local/logs/n8n.log`
- n8n data: `~/.n8n/`

## Configuration

Key environment variables set by the installer (in the LaunchAgent plist):

| Variable              | Default | Purpose                        |
| --------------------- | ------- | ------------------------------ |
| `N8N_PORT`            | `5678`  | n8n HTTP port                  |
| `N8N_SECURE_COOKIE`   | `false` | Disabled for local HTTP access |
| `DB_SQLITE_POOL_SIZE` | `4`     | Enables WAL mode for SQLite    |
| `N8N_USER_FOLDER`     | `~`     | Where `.n8n/` data is stored   |

## Project structure

```text
n8n.dmg/
├── Makefile                              # Build orchestrator
├── config.sh                             # Shared config (versions, paths)
├── icon/
│   └── icon.svg                          # App icon SVG (pink nodes, no text)
├── swift/
│   └── N8nManager.swift                  # Native macOS app (WKWebView + service mgmt)
├── scripts/
│   ├── download-node.sh                  # Download Node.js arm64 + x64
│   ├── bundle-n8n.sh                     # npm install n8n per arch
│   ├── fetch-icon.sh                     # Convert SVG to .icns
│   ├── create-app-bundle.sh              # Build the installer .app wrapper
│   ├── build-manager-app.sh              # Compile native app (universal binary)
│   └── build-dmg.sh                      # Assemble final .dmg
└── payload/
    ├── install.sh                        # Installer (runs on target machine)
    ├── uninstall.sh                      # Uninstaller
    ├── launch-n8n.sh                     # Script called by LaunchAgent
    ├── n8n-dmg.sh                        # CLI helper (start/stop/status/logs/ui)
    └── com.n8n.local.plist.template      # LaunchAgent template
```
