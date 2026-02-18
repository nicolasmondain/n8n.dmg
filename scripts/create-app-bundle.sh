#!/usr/bin/env bash
# create-app-bundle.sh — Build a minimal .app wrapper that opens Terminal and runs install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[app-bundle]${NC} $*"; }

APP_DIR="${PROJECT_ROOT}/${BUILD_DIR}/Install n8n.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

log "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Install n8n</string>
    <key>CFBundleDisplayName</key>
    <string>Install n8n</string>
    <key>CFBundleIdentifier</key>
    <string>com.n8n.local.installer</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>CFBundleIconFile</key>
    <string>n8n</string>
    <key>NSHumanReadableCopyright</key>
    <string>n8n local installer</string>
</dict>
</plist>
PLIST

# Copy icon if available
ICON_FILE="${PROJECT_ROOT}/${BUILD_DIR}/n8n.icns"
if [[ -f "$ICON_FILE" ]]; then
    cp "$ICON_FILE" "${RESOURCES_DIR}/n8n.icns"
    log "Icon embedded"
else
    log "No icon found — using default macOS icon"
fi

# Launcher script — opens Terminal and runs install.sh from the DMG
# If n8n is already installed, opens the management UI instead.
cat > "${MACOS_DIR}/launcher" << 'LAUNCHER'
#!/usr/bin/env bash
INSTALL_DIR="${HOME}/.n8n-local"

# If n8n is already installed, open the native app
if [[ -d "${INSTALL_DIR}/n8n.app" ]]; then
    open "${INSTALL_DIR}/n8n.app"
    exit 0
fi

# Otherwise, run the installer from the DMG
DMG_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
INSTALL_SCRIPT="${DMG_ROOT}/.payload/install.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    osascript -e 'display dialog "Installation files not found.\n\nMake sure you are running this from the mounted DMG." with title "n8n Installer" buttons {"OK"} default button "OK" with icon stop'
    exit 1
fi

# Open Terminal and run the installer
osascript << EOF
tell application "Terminal"
    activate
    do script "clear && bash '${INSTALL_SCRIPT}'; exit"
end tell
EOF
LAUNCHER

chmod +x "${MACOS_DIR}/launcher"

log "App bundle created: ${APP_DIR}"
