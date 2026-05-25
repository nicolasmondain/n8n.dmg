#!/usr/bin/env bash
# build-dmg.sh — Assemble the final .dmg from build artifacts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[build-dmg]${NC} $*"; }
warn() { echo -e "${YELLOW}[build-dmg]${NC} $*"; }
err()  { echo -e "${RED}[build-dmg]${NC} $*" >&2; }

STAGING_DIR="${PROJECT_ROOT}/${BUILD_DIR}/dmg-staging"
DMG_TEMP="${PROJECT_ROOT}/${BUILD_DIR}/${DMG_FILENAME%.dmg}-temp.dmg"
DMG_OUTPUT="${PROJECT_ROOT}/${DIST_DIR}/${DMG_FILENAME}"

# Verify required build artifacts exist
log "Checking build artifacts..."
for artifact in \
    "${PROJECT_ROOT}/${BUILD_DIR}/node-arm64/bin/node" \
    "${PROJECT_ROOT}/${BUILD_DIR}/node-x64/bin/node" \
    "${PROJECT_ROOT}/${BUILD_DIR}/n8n-arm64/node_modules/.bin/n8n" \
    "${PROJECT_ROOT}/${BUILD_DIR}/n8n-x64/node_modules/.bin/n8n" \
    "${PROJECT_ROOT}/${BUILD_DIR}/Install n8n.app/Contents/MacOS/launcher" \
    "${PROJECT_ROOT}/${BUILD_DIR}/n8n.app/Contents/MacOS/N8nManager"; do
    if [[ ! -e "$artifact" ]]; then
        err "Missing artifact: $artifact"
        err "Run the full build chain first (make)"
        exit 1
    fi
done

# Clean staging area
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy the .app (visible to user)
log "Staging app bundle..."
cp -R "${PROJECT_ROOT}/${BUILD_DIR}/Install n8n.app" "${STAGING_DIR}/Install n8n.app"

# Create README.txt
cat > "${STAGING_DIR}/README.txt" << 'README'
n8n Local Installer
===================

Double-click "Install n8n.app" to install n8n on your Mac.

What happens:
  - n8n is installed to ~/.n8n-local/
  - A background service starts n8n automatically on login
  - Your browser opens to http://localhost:5678

Custom port:
  The installer prompts for a port (default: 5678).
  Or pass it directly: bash .payload/install.sh --port=3000

After installation, use the CLI helper:
  n8n-dmg start    - Start n8n
  n8n-dmg stop     - Stop n8n
  n8n-dmg restart  - Restart n8n
  n8n-dmg status   - Check if n8n is running
  n8n-dmg logs     - View n8n logs
  n8n-dmg open     - Open n8n in browser

To uninstall:
  ~/.n8n-local/uninstall.sh

Note: Your workflow data in ~/.n8n/ is never touched by
install or uninstall. It's safe to upgrade or reinstall.
README

# Hidden directories (dot-prefix hides them in Finder)
log "Staging payload and binaries..."
mkdir -p "${STAGING_DIR}/.payload"
cp "${PROJECT_ROOT}/payload/install.sh"                    "${STAGING_DIR}/.payload/"
cp "${PROJECT_ROOT}/payload/uninstall.sh"                  "${STAGING_DIR}/.payload/"
cp "${PROJECT_ROOT}/payload/launch-n8n.sh"                 "${STAGING_DIR}/.payload/"
cp "${PROJECT_ROOT}/payload/n8n-dmg.sh"                    "${STAGING_DIR}/.payload/"
cp "${PROJECT_ROOT}/payload/com.n8n.local.plist.template"  "${STAGING_DIR}/.payload/"
chmod +x "${STAGING_DIR}/.payload/"*.sh

# Copy native n8n app
if [[ -d "${PROJECT_ROOT}/${BUILD_DIR}/n8n.app" ]]; then
    cp -R "${PROJECT_ROOT}/${BUILD_DIR}/n8n.app" "${STAGING_DIR}/.payload/n8n.app"
fi

# Copy Node.js binaries
cp -R "${PROJECT_ROOT}/${BUILD_DIR}/node-arm64" "${STAGING_DIR}/.node-arm64"
cp -R "${PROJECT_ROOT}/${BUILD_DIR}/node-x64"   "${STAGING_DIR}/.node-x64"

# Copy n8n bundles
cp -R "${PROJECT_ROOT}/${BUILD_DIR}/n8n-arm64" "${STAGING_DIR}/.n8n-arm64"
cp -R "${PROJECT_ROOT}/${BUILD_DIR}/n8n-x64"   "${STAGING_DIR}/.n8n-x64"

# Create the DMG directly as a compressed, read-only image.
# Let hdiutil auto-size from -srcfolder (no fixed -size): the previous
# du-based estimate undercounted HFS+ overhead for n8n's 300k+ small files,
# so the image ran out of room mid-copy and hdiutil failed with a misleading
# "could not access <file>" error. No volume customization is needed, so a
# single-step UDZO create replaces the old UDRW-then-convert dance.
log "Creating DMG..."
mkdir -p "${PROJECT_ROOT}/${DIST_DIR}"
rm -f "$DMG_TEMP" "$DMG_OUTPUT"

hdiutil create \
    -fs HFS+ \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG_OUTPUT"

# Report
local_final_size=$(du -sh "$DMG_OUTPUT" | awk '{print $1}')
log "=== DMG built successfully ==="
log "Output: ${DMG_OUTPUT} (${local_final_size})"
