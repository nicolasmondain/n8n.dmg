#!/usr/bin/env bash
# bundle-n8n.sh — Install n8n per architecture using the corresponding Node.js binary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[bundle-n8n]${NC} $*"; }
warn() { echo -e "${YELLOW}[bundle-n8n]${NC} $*"; }
err()  { echo -e "${RED}[bundle-n8n]${NC} $*" >&2; }

bundle_n8n() {
    local arch="$1"
    local node_dir="${PROJECT_ROOT}/${BUILD_DIR}/node-${arch}"
    local n8n_dir="${PROJECT_ROOT}/${BUILD_DIR}/n8n-${arch}"
    local node_bin="${node_dir}/bin/node"
    local npm_bin="${node_dir}/bin/npm"

    if [[ ! -x "$node_bin" ]]; then
        err "Node.js binary not found for ${arch} at ${node_bin}"
        err "Run download-node.sh first"
        exit 1
    fi

    # Check if already bundled with correct version
    if [[ -d "$n8n_dir" ]]; then
        local existing_version
        existing_version=$("$node_bin" "${n8n_dir}/node_modules/.bin/n8n" --version 2>/dev/null || true)
        if [[ "$existing_version" == "$N8N_VERSION" ]]; then
            log "n8n ${N8N_VERSION} (${arch}) already bundled, skipping"
            return 0
        fi
    fi

    log "Installing n8n@${N8N_VERSION} for ${arch}..."
    rm -rf "$n8n_dir"
    mkdir -p "$n8n_dir"

    # Use the arch-specific node/npm to install n8n
    # This ensures native modules are compiled for the correct architecture
    local env_prefix=""
    local host_arch
    host_arch=$(uname -m)

    # If we're on arm64 and building for x64, use Rosetta
    if [[ "$host_arch" == "arm64" && "$arch" == "x64" ]]; then
        env_prefix="arch -x86_64"
    elif [[ "$host_arch" == "x86_64" && "$arch" == "arm64" ]]; then
        err "Cannot build arm64 binaries on x64 host"
        err "Build must run on Apple Silicon Mac"
        exit 1
    fi

    $env_prefix "$node_bin" "$npm_bin" install \
        --prefix "$n8n_dir" \
        "n8n@${N8N_VERSION}" \
        --no-fund \
        --no-audit \
        --loglevel=warn

    # Verify installation
    log "Verifying n8n ${arch}..."
    local installed_version
    installed_version=$($env_prefix "$node_bin" "${n8n_dir}/node_modules/.bin/n8n" --version 2>/dev/null || true)

    if [[ -z "$installed_version" ]]; then
        err "n8n verification failed for ${arch} — could not get version"
        exit 1
    fi

    log "n8n ${installed_version} (${arch}) verified"

    local n8n_size
    n8n_size=$(du -sh "$n8n_dir" | awk '{print $1}')
    log "n8n ${arch} bundle ready (${n8n_size})"
}

# Main
log "=== Bundling n8n v${N8N_VERSION} ==="
bundle_n8n "arm64"
bundle_n8n "x64"
log "=== All n8n bundles complete ==="
