#!/usr/bin/env bash
# install.sh — n8n local installer (runs on the target machine from the DMG)
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

N8N_PORT=5678
N8N_HOST="localhost"
INSTALL_DIR="${HOME}/.n8n-local"
LAUNCHAGENT_LABEL="com.n8n.local"
LAUNCHAGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
GUI_UID=$(id -u)
POLL_TIMEOUT=30

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --port=*) N8N_PORT="${arg#*=}" ;;
    esac
done

# Resolve the DMG mount point (install.sh lives in .payload/)
DMG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────────────────────

log()     { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
info()    { echo -e "    $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
err()     { echo -e "${RED}✖${NC}  $*" >&2; }
success() { echo -e "${GREEN}✔${NC}  $*"; }

# ─── Cleanup on failure ──────────────────────────────────────────────────────

CLEANUP_NEEDED=false

cleanup() {
    if $CLEANUP_NEEDED; then
        err "Installation failed. Cleaning up partial install..."
        # Stop service if it was started
        launchctl bootout "gui/${GUI_UID}/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
        rm -f "$LAUNCHAGENT_PLIST"
        rm -rf "$INSTALL_DIR"
        err "Cleanup complete. Please try again."
    fi
}

trap cleanup EXIT
trap 'CLEANUP_NEEDED=true; exit 1' INT TERM

# ─── Pre-flight checks ───────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║       n8n Local Installer            ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    arm64)
        ARCH_LABEL="Apple Silicon (arm64)"
        NODE_SRC=".node-arm64"
        N8N_SRC=".n8n-arm64"
        ;;
    x86_64)
        ARCH_LABEL="Intel (x64)"
        NODE_SRC=".node-x64"
        N8N_SRC=".n8n-x64"
        ;;
    *)
        err "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

log "Detected: ${ARCH_LABEL}"

# Verify DMG contents
for required in "${DMG_ROOT}/${NODE_SRC}/bin/node" "${DMG_ROOT}/${N8N_SRC}/node_modules/.bin/n8n"; do
    if [[ ! -e "$required" ]]; then
        err "Missing required file: $required"
        err "The DMG appears to be incomplete or corrupted."
        exit 1
    fi
done

# ─── Port selection ───────────────────────────────────────────────────────────

# On upgrade, default to previously configured port
if [[ -f "${INSTALL_DIR}/.port" ]]; then
    EXISTING_PORT=$(cat "${INSTALL_DIR}/.port")
fi

# Only prompt if --port was not passed via CLI
PROMPTED_PORT=false
if [[ "$N8N_PORT" == "5678" && -z "${EXISTING_PORT:-}" ]]; then
    echo ""
    read -rp "    Port for n8n [${N8N_PORT}]: " user_port
    if [[ -n "$user_port" ]]; then
        N8N_PORT="$user_port"
        PROMPTED_PORT=true
    fi
elif [[ "$N8N_PORT" == "5678" && -n "${EXISTING_PORT:-}" ]]; then
    N8N_PORT="$EXISTING_PORT"
fi

# Validate port
if ! [[ "$N8N_PORT" =~ ^[0-9]+$ ]] || (( N8N_PORT < 1 || N8N_PORT > 65535 )); then
    err "Invalid port: ${N8N_PORT}"
    exit 1
fi

info "n8n will run on port ${CYAN}${N8N_PORT}${NC}"

# ─── Handle existing installation ────────────────────────────────────────────

UPGRADING=false

if [[ -d "$INSTALL_DIR" ]]; then
    if [[ -f "${INSTALL_DIR}/.version" ]]; then
        EXISTING_VERSION=$(cat "${INSTALL_DIR}/.version")
        warn "Existing n8n installation found (${EXISTING_VERSION})"
    else
        warn "Existing n8n installation found"
    fi

    echo ""
    echo -e "    This will ${BOLD}upgrade${NC} the installation."
    echo -e "    Your workflow data in ${CYAN}~/.n8n/${NC} will ${GREEN}not${NC} be touched."
    echo ""
    read -rp "    Continue? [Y/n] " response
    case "${response:-Y}" in
        [yY]|[yY][eE][sS]|"")
            UPGRADING=true
            ;;
        *)
            info "Installation cancelled."
            exit 0
            ;;
    esac

    # Stop existing service
    log "Stopping existing n8n service..."
    launchctl bootout "gui/${GUI_UID}/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
    sleep 1
fi

# ─── Install ─────────────────────────────────────────────────────────────────

CLEANUP_NEEDED=true

log "Installing to ${INSTALL_DIR}..."

# Create directory structure
mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/logs"
mkdir -p "${INSTALL_DIR}/node"
mkdir -p "${INSTALL_DIR}/n8n"

# Copy Node.js
log "Copying Node.js..."
rsync -a --delete "${DMG_ROOT}/${NODE_SRC}/" "${INSTALL_DIR}/node/"
success "Node.js installed"

# Copy n8n
log "Copying n8n..."
rsync -a --delete "${DMG_ROOT}/${N8N_SRC}/" "${INSTALL_DIR}/n8n/"
success "n8n installed"

# Copy scripts
log "Installing helper scripts..."
cp "${DMG_ROOT}/.payload/launch-n8n.sh" "${INSTALL_DIR}/bin/"
cp "${DMG_ROOT}/.payload/n8n-dmg.sh"    "${INSTALL_DIR}/bin/"
cp "${DMG_ROOT}/.payload/uninstall.sh"   "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/bin/"*.sh
chmod +x "${INSTALL_DIR}/uninstall.sh"

# Copy native n8n app
if [[ -d "${DMG_ROOT}/.payload/n8n.app" ]]; then
    cp -R "${DMG_ROOT}/.payload/n8n.app" "${INSTALL_DIR}/n8n.app"
    xattr -cr "${INSTALL_DIR}/n8n.app" 2>/dev/null || true
    # Symlink to ~/Applications for Spotlight discovery
    mkdir -p "${HOME}/Applications"
    ln -sf "${INSTALL_DIR}/n8n.app" "${HOME}/Applications/n8n.app"
    success "n8n app installed"
fi

success "Scripts installed"

# Write version and port files
N8N_INSTALLED_VERSION=$("${INSTALL_DIR}/node/bin/node" "${INSTALL_DIR}/n8n/node_modules/.bin/n8n" --version 2>/dev/null || echo "unknown")
echo "$N8N_INSTALLED_VERSION" > "${INSTALL_DIR}/.version"
echo "$N8N_PORT" > "${INSTALL_DIR}/.port"

# ─── LaunchAgent ──────────────────────────────────────────────────────────────

log "Configuring LaunchAgent..."
mkdir -p "${HOME}/Library/LaunchAgents"

sed \
    -e "s|__INSTALL_DIR__|${INSTALL_DIR}|g" \
    -e "s|__LAUNCHAGENT_LABEL__|${LAUNCHAGENT_LABEL}|g" \
    -e "s|__N8N_PORT__|${N8N_PORT}|g" \
    -e "s|__N8N_HOST__|${N8N_HOST}|g" \
    -e "s|__HOME__|${HOME}|g" \
    "${DMG_ROOT}/.payload/com.n8n.local.plist.template" \
    > "$LAUNCHAGENT_PLIST"

success "LaunchAgent configured"

# ─── Start n8n ────────────────────────────────────────────────────────────────

log "Starting n8n..."
launchctl bootstrap "gui/${GUI_UID}" "$LAUNCHAGENT_PLIST"

# Poll for n8n to be ready
info "Waiting for n8n to start..."
SECONDS_WAITED=0
while (( SECONDS_WAITED < POLL_TIMEOUT )); do
    if curl -sf "http://localhost:${N8N_PORT}/healthz" -o /dev/null 2>/dev/null; then
        break
    fi
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
    printf "."
done
echo ""

if curl -sf "http://localhost:${N8N_PORT}/healthz" -o /dev/null 2>/dev/null; then
    success "n8n is running on http://localhost:${N8N_PORT}"
else
    warn "n8n did not respond within ${POLL_TIMEOUT}s"
    warn "It may still be starting. Check logs with: n8n-dmg logs"
fi

# ─── Shell alias ──────────────────────────────────────────────────────────────

ALIAS_LINE="alias n8n-dmg=\"${INSTALL_DIR}/bin/n8n-dmg.sh\""
ZSHRC="${HOME}/.zshrc"

if [[ -f "$ZSHRC" ]] && grep -qF "alias n8n-dmg=" "$ZSHRC"; then
    # Update existing alias
    sed -i '' "s|alias n8n-dmg=.*|${ALIAS_LINE}|" "$ZSHRC"
else
    echo "" >> "$ZSHRC"
    echo "# n8n local — CLI helper" >> "$ZSHRC"
    echo "$ALIAS_LINE" >> "$ZSHRC"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

CLEANUP_NEEDED=false

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║       Installation complete!         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""
info "n8n is running at: ${CYAN}http://localhost:${N8N_PORT}${NC}"
info ""
info "Commands (open a new terminal or run: source ~/.zshrc):"
info "  ${BOLD}n8n-dmg start${NC}    Start n8n"
info "  ${BOLD}n8n-dmg stop${NC}     Stop n8n"
info "  ${BOLD}n8n-dmg restart${NC}  Restart n8n"
info "  ${BOLD}n8n-dmg status${NC}   Show status"
info "  ${BOLD}n8n-dmg logs${NC}     View logs"
info "  ${BOLD}n8n-dmg open${NC}     Open in browser"
info "  ${BOLD}n8n-dmg ui${NC}       Open n8n native app"
info ""
info "To uninstall: ${YELLOW}~/.n8n-local/uninstall.sh${NC}"
echo ""

# Open native n8n app (or fall back to browser)
if [[ -d "${INSTALL_DIR}/n8n.app" ]]; then
    open "${INSTALL_DIR}/n8n.app"
else
    open "http://localhost:${N8N_PORT}"
fi

# Show success dialog
if $UPGRADING; then
    DIALOG_MSG="n8n has been upgraded to ${N8N_INSTALLED_VERSION}.\n\nRunning at http://localhost:${N8N_PORT}"
else
    DIALOG_MSG="n8n has been installed successfully!\n\nRunning at http://localhost:${N8N_PORT}\n\nUse 'n8n-dmg' to manage the service."
fi

osascript -e "display dialog \"${DIALOG_MSG}\" with title \"n8n Installer\" buttons {\"OK\"} default button \"OK\"" &>/dev/null &
