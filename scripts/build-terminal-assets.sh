#!/usr/bin/env bash
# build-terminal-assets.sh — Download xterm.js and stage terminal resources into build/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[terminal-assets]${NC} $*"; }
warn() { echo -e "${YELLOW}[terminal-assets]${NC} $*"; }

DEST="${PROJECT_ROOT}/${BUILD_DIR}/terminal-resources"
XTERM_DIR="${DEST}/xterm"

# Skip if already built
if [[ -f "${XTERM_DIR}/xterm.js" && -f "${XTERM_DIR}/xterm.css" && -f "${XTERM_DIR}/xterm-addon-fit.js" ]]; then
    log "Terminal assets already staged, skipping"
    exit 0
fi

log "Downloading xterm.js v${XTERM_JS_VERSION}..."

mkdir -p "$XTERM_DIR"

CDN_BASE="https://cdn.jsdelivr.net/npm"
# addon-fit uses a different version scheme than @xterm/xterm
XTERM_ADDON_FIT_VERSION="0.11.0"

curl -sfL "${CDN_BASE}/@xterm/xterm@${XTERM_JS_VERSION}/lib/xterm.js" \
    -o "${XTERM_DIR}/xterm.js"
log "  Downloaded xterm.js"

curl -sfL "${CDN_BASE}/@xterm/xterm@${XTERM_JS_VERSION}/css/xterm.css" \
    -o "${XTERM_DIR}/xterm.css"
log "  Downloaded xterm.css"

curl -sfL "${CDN_BASE}/@xterm/addon-fit@${XTERM_ADDON_FIT_VERSION}/lib/addon-fit.js" \
    -o "${XTERM_DIR}/xterm-addon-fit.js"
log "  Downloaded xterm-addon-fit.js"

# Copy terminal HTML
cp "${PROJECT_ROOT}/terminal/terminal.html" "${DEST}/terminal.html"
log "  Copied terminal.html"

log "Terminal assets staged: ${DEST}"
