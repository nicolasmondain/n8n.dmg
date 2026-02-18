# Building from Source

## Prerequisites

- macOS with Apple Silicon (Rosetta 2 is used for x64 cross-compilation)
- Xcode Command Line Tools: `xcode-select --install` (provides `swiftc`, `sips`, `iconutil`)
- Internet connection (to download Node.js and n8n during build)

## Build

```bash
make clean && make
```

Output: `dist/n8n-local-installer.dmg`

### Individual targets

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

Share the `.dmg` file. Recipients double-click to mount, then double-click **Install n8n.app**.

Since the app is unsigned, macOS Gatekeeper will block it. Users need to right-click > Open (or System Settings > Privacy & Security > Open Anyway).

## Project structure

```text
n8n.dmg/
├── Makefile                              # Build orchestrator
├── config.sh                             # Shared config (versions, paths)
├── icon/
│   └── icon.svg                          # App icon SVG (pink nodes, no text)
├── swift/
│   └── N8nManager.swift                  # Native macOS app (WKWebView + service management)
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
