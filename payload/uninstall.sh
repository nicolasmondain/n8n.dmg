#!/usr/bin/env bash
# uninstall.sh — Remove n8n local installation
set -euo pipefail

INSTALL_DIR="${HOME}/.n8n-local"
LAUNCHAGENT_LABEL="com.n8n.local"
LAUNCHAGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
GUI_UID=$(id -u)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
info()    { echo -e "    $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
success() { echo -e "${GREEN}✔${NC}  $*"; }

echo ""
echo -e "${CYAN}${BOLD}n8n Local — Uninstaller${NC}"
echo ""

# ─── Stop service ─────────────────────────────────────────────────────────────

log "Stopping n8n service..."
if launchctl print "gui/${GUI_UID}/${LAUNCHAGENT_LABEL}" &>/dev/null; then
    launchctl bootout "gui/${GUI_UID}/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
    success "Service stopped"
else
    info "Service was not running"
fi

# ─── Remove LaunchAgent plist ─────────────────────────────────────────────────

if [[ -f "$LAUNCHAGENT_PLIST" ]]; then
    rm -f "$LAUNCHAGENT_PLIST"
    success "LaunchAgent removed"
fi

# ─── Remove native app from ~/Applications ──────────────────────────────────

if [[ -L "${HOME}/Applications/n8n.app" ]] || [[ -d "${HOME}/Applications/n8n.app" ]]; then
    rm -rf "${HOME}/Applications/n8n.app"
    success "n8n app removed from ~/Applications"
fi

# ─── Remove installation directory ───────────────────────────────────────────

if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    success "Installation directory removed (${INSTALL_DIR})"
fi

# ─── Remove shell alias ──────────────────────────────────────────────────────

ZSHRC="${HOME}/.zshrc"
if [[ -f "$ZSHRC" ]] && grep -qF "alias n8n-dmg=" "$ZSHRC"; then
    # Remove the alias line and the comment above it
    sed -i '' '/# n8n local — CLI helper/d' "$ZSHRC"
    sed -i '' '/alias n8n-dmg=/d' "$ZSHRC"
    success "Shell alias removed from ~/.zshrc"
fi

# ─── Ask about user data ─────────────────────────────────────────────────────

N8N_DATA_DIR="${HOME}/.n8n"
if [[ -d "$N8N_DATA_DIR" ]]; then
    echo ""
    warn "Your n8n data directory exists at ${CYAN}~/.n8n/${NC}"
    info "This contains your workflows, credentials, and settings."
    echo ""
    read -rp "    Delete user data too? [y/N] " response
    case "$response" in
        [yY]|[yY][eE][sS])
            rm -rf "$N8N_DATA_DIR"
            success "User data removed (${N8N_DATA_DIR})"
            ;;
        *)
            info "User data preserved at ${N8N_DATA_DIR}"
            ;;
    esac
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
success "n8n has been completely uninstalled."
echo ""
