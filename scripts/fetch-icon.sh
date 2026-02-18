#!/usr/bin/env bash
# fetch-icon.sh — Convert the n8n icon SVG to .icns for the .app bundle
# macOS .app bundles require .icns format — a raw SVG/PNG won't work as CFBundleIconFile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[icon]${NC} $*"; }
warn() { echo -e "${YELLOW}[icon]${NC} $*"; }
err()  { echo -e "${RED}[icon]${NC} $*" >&2; }

ICON_BUILD_DIR="${PROJECT_ROOT}/${BUILD_DIR}/icon"
ICNS_OUTPUT="${PROJECT_ROOT}/${BUILD_DIR}/n8n.icns"

# Skip if already built
if [[ -f "$ICNS_OUTPUT" ]]; then
    log "Icon already exists, skipping"
    exit 0
fi

SOURCE_SVG="${PROJECT_ROOT}/icon/icon.svg"

if [[ ! -f "$SOURCE_SVG" ]]; then
    err "Icon SVG not found at icon/icon.svg"
    exit 1
fi

log "Converting icon/icon.svg to .icns..."
rm -rf "$ICON_BUILD_DIR"
mkdir -p "$ICON_BUILD_DIR"

SQUARE="${ICON_BUILD_DIR}/square.png"

# Convert SVG to 1024x1024 PNG
if command -v rsvg-convert &>/dev/null; then
    rsvg-convert -w 1024 -h 1024 "$SOURCE_SVG" -o "$SQUARE"
elif command -v qlmanage &>/dev/null; then
    qlmanage -t -s 1024 -o "$ICON_BUILD_DIR" "$SOURCE_SVG" &>/dev/null
    ql_output="${ICON_BUILD_DIR}/icon.svg.png"
    if [[ -f "$ql_output" ]]; then
        mv "$ql_output" "$SQUARE"
        sips -z 1024 1024 "$SQUARE" >/dev/null 2>&1
    else
        err "Quick Look failed to convert SVG"
        exit 1
    fi
else
    err "No SVG converter found. Install librsvg (brew install librsvg) or use macOS with Quick Look."
    exit 1
fi

# Generate all required iconset sizes
ICONSET_DIR="${ICON_BUILD_DIR}/n8n.iconset"
mkdir -p "$ICONSET_DIR"

sips -z 16 16       "$SQUARE" --out "${ICONSET_DIR}/icon_16x16.png"      >/dev/null
sips -z 32 32       "$SQUARE" --out "${ICONSET_DIR}/icon_16x16@2x.png"   >/dev/null
sips -z 32 32       "$SQUARE" --out "${ICONSET_DIR}/icon_32x32.png"      >/dev/null
sips -z 64 64       "$SQUARE" --out "${ICONSET_DIR}/icon_32x32@2x.png"   >/dev/null
sips -z 128 128     "$SQUARE" --out "${ICONSET_DIR}/icon_128x128.png"    >/dev/null
sips -z 256 256     "$SQUARE" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256     "$SQUARE" --out "${ICONSET_DIR}/icon_256x256.png"    >/dev/null
sips -z 512 512     "$SQUARE" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512     "$SQUARE" --out "${ICONSET_DIR}/icon_512x512.png"    >/dev/null
sips -z 1024 1024   "$SQUARE" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUTPUT"

rm -rf "$ICON_BUILD_DIR"

log "Icon ready: ${ICNS_OUTPUT}"
