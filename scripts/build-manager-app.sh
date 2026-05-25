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

SWIFT_DIR="${PROJECT_ROOT}/swift"
SWIFT_SOURCES=(
    "${SWIFT_DIR}/main.swift"
    "${SWIFT_DIR}/N8nManager.swift"
    "${SWIFT_DIR}/TerminalManager.swift"
    "${SWIFT_DIR}/TerminalPanelView.swift"
)
BRIDGING_HEADER="${SWIFT_DIR}/pty_shim.h"
APP_DIR="${PROJECT_ROOT}/${BUILD_DIR}/n8n.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ICON_FILE="${PROJECT_ROOT}/${BUILD_DIR}/n8n.icns"
TERMINAL_RESOURCES="${PROJECT_ROOT}/${BUILD_DIR}/terminal-resources"

# Skip if already built
if [[ -x "${MACOS}/N8nManager" ]]; then
    log "Manager app already built, skipping"
    exit 0
fi

for src in "${SWIFT_SOURCES[@]}"; do
    if [[ ! -f "$src" ]]; then
        warn "Swift source not found: ${src}"
        exit 1
    fi
done

if [[ ! -f "$BRIDGING_HEADER" ]]; then
    warn "Bridging header not found: ${BRIDGING_HEADER}"
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
    -import-objc-header "$BRIDGING_HEADER" \
    -o "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-arm64" \
    "${SWIFT_SOURCES[@]}"

# Compile for x86_64
log "  Compiling x86_64..."
swiftc -O \
    -target x86_64-apple-macosx12.0 \
    -import-objc-header "$BRIDGING_HEADER" \
    -o "${PROJECT_ROOT}/${BUILD_DIR}/N8nManager-x64" \
    "${SWIFT_SOURCES[@]}"

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
    <key>NSDocumentsFolderUsageDescription</key>
    <string>n8n runs the commands you type in its built-in terminal, which may read files in this folder.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>n8n runs the commands you type in its built-in terminal, which may read files in this folder.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>n8n runs the commands you type in its built-in terminal, which may read files in this folder.</string>
</dict>
</plist>
PLIST

# Copy icon
if [[ -f "$ICON_FILE" ]]; then
    cp "$ICON_FILE" "${RESOURCES}/n8n.icns"
    log "  Icon embedded"
fi

# Copy terminal resources
if [[ -d "$TERMINAL_RESOURCES" ]]; then
    cp -R "$TERMINAL_RESOURCES" "${RESOURCES}/terminal-resources"
    log "  Terminal resources embedded"
else
    warn "Terminal resources not found at ${TERMINAL_RESOURCES} — terminal will be unavailable"
fi

# Code-sign the assembled bundle with a stable ad-hoc identity.
# After lipo, the universal binary only carries per-arch linker signatures and
# the bundle is left unsealed, so macOS TCC can't remember file-access grants
# and re-prompts on every launch ("n8n.app would like to access Documents…").
# Signing the whole bundle with a fixed identifier yields a consistent cdhash,
# so the user grants each protected folder once and the choice sticks.
log "  Signing app bundle (ad-hoc)..."
codesign --force --sign - --identifier com.n8n.local.manager "$APP_DIR"
codesign --verify --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/    /' || warn "codesign verify reported issues"

# Report binary info
binary_size=$(du -sh "${MACOS}/N8nManager" | awk '{print $1}')
log "Manager app built: ${APP_DIR} (${binary_size})"
log "$(file "${MACOS}/N8nManager")"
