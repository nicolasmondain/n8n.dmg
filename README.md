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

## More

- [Building from source](docs/building.md)
- [Configuration & CLI](docs/configuration.md)
- [Troubleshooting](docs/troubleshooting.md)
