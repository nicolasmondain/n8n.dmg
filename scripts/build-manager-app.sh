#!/usr/bin/env bash
# build-manager-app.sh — Compile the native n8n Manager app (universal binary)
# Requires: Xcode Command Line Tools (swiftc, lipo)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[manager-app]${NC} $*"; }
warn() { echo -e "${YELLOW}[manager-app]${NC} $*"; }

SWIFT_SRC="${PROJECT_ROOT}/swift/N8nManager.swift"
APP_DIR="${PROJECT_ROOT}/${BUILD_DIR}/n8n.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ICON_FILE="${PROJECT_ROOT}/${BUILD_DIR}/n8n.icns"

# Skip if already built
if [[ -x "${MACOS}/N8nManager" ]]; then
    log "Manager app already built, skipping"
    exit 0
fi

if [[ ! -f "$SWIFT_SRC" ]]; then
    warn "Swift source not found at ${SWIFT_SRC}"
    exit 1
fi

log "Compiling n8n Manager app..."

# Prepare .app bundle
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Compile for arm64
log "  Compiling arm64..."
swiftc -O \
    -target arm64-apple-macosx12.0 \
    -o "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-arm64" \
    "$SWIFT_SRC"

# Compile for x86_64
log "  Compiling x86_64..."
swiftc -O \
    -target x86_64-apple-macosx12.0 \
    -o "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-x64" \
    "$SWIFT_SRC"

# Create universal binary
log "  Creating universal binary..."
lipo -create \
    "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-arm64" \
    "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-x64" \
    -output "${MACOS}/N8nManager"

# Clean intermediates
rm -f "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-arm64" \
      "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-x64"

# Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>n8n</string>
    <key>CFBundleDisplayName</key>
    <string>n8n</string>
    <key>CFBundleIdentifier</key>
    <string>com.n8n.local.manager</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>N8nManager</string>
    <key>CFBundleIconFile</key>
    <string>n8n</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>n8n — workflow automation</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Copy icon
if [[ -f "$ICON_FILE" ]]; then
    cp "$ICON_FILE" "${RESOURCES}/n8n.icns"
    log "  Icon embedded"
fi

# Report binary info
binary_size=$(du -sh "${MACOS}/N8nManager" | awk '{print $1}')
log "Manager app built: ${APP_DIR} (${binary_size})"
log "$(file "${MACOS}/N8nManager")"
