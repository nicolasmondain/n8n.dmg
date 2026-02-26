#!/usr/bin/env bash
# download-node.sh — Download Node.js binaries for arm64 + x64
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[download-node]${NC} $*"; }
warn() { echo -e "${YELLOW}[download-node]${NC} $*"; }
err()  { echo -e "${RED}[download-node]${NC} $*" >&2; }

download_node() {
    local arch="$1"  # arm64 or x64
    local node_arch

    case "$arch" in
        arm64) node_arch="arm64" ;;
        x64)   node_arch="x64" ;;
        *)     err "Unknown architecture: $arch"; exit 1 ;;
    esac

    local tarball="node-v${NODE_VERSION}-darwin-${node_arch}.tar.gz"
    local url="${NODE_BASE_URL}/${tarball}"
    local shasums_url="${NODE_BASE_URL}/SHASUMS256.txt"
    local dest_dir="${PROJECT_ROOT}/${BUILD_DIR}/node-${arch}"

    if [[ -x "${dest_dir}/bin/node" ]]; then
        local existing_version
        existing_version=$("${dest_dir}/bin/node" --version 2>/dev/null || true)
        if [[ "$existing_version" == "v${NODE_VERSION}" ]]; then
            log "Node.js v${NODE_VERSION} (${arch}) already downloaded, skipping"
            return 0
        fi
    fi

    log "Downloading Node.js v${NODE_VERSION} for ${arch}..."
    mkdir -p "${PROJECT_ROOT}/${BUILD_DIR}"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" RETURN

    # Download tarball and checksums
    curl -fSL --progress-bar -o "${tmp_dir}/${tarball}" "$url"
    curl -fsSL -o "${tmp_dir}/SHASUMS256.txt" "$shasums_url"

    # Verify SHA256
    log "Verifying checksum for ${arch}..."
    local expected_sha
    expected_sha=$(grep -F "${tarball}" "${tmp_dir}/SHASUMS256.txt" | awk '{print $1}')
    if [[ -z "$expected_sha" ]]; then
        err "Could not find checksum for ${tarball}"
        exit 1
    fi

    local actual_sha
    actual_sha=$(shasum -a 256 "${tmp_dir}/${tarball}" | awk '{print $1}')
    if [[ "$expected_sha" != "$actual_sha" ]]; then
        err "Checksum mismatch for ${tarball}"
        err "  Expected: ${expected_sha}"
        err "  Actual:   ${actual_sha}"
        exit 1
    fi
    log "Checksum verified for ${arch}"

    # Extract
    log "Extracting Node.js ${arch}..."
    rm -rf "$dest_dir"
    mkdir -p "$dest_dir"
    tar xzf "${tmp_dir}/${tarball}" -C "$dest_dir" --strip-components=1

    # Strip unnecessary files to reduce size
    rm -rf "${dest_dir}/include" \
           "${dest_dir}/share" \
           "${dest_dir}/CHANGELOG.md" \
           "${dest_dir}/README.md" \
           "${dest_dir}/LICENSE"

    local node_size
    node_size=$(du -sh "$dest_dir" | awk '{print $1}')
    log "Node.js ${arch} ready (${node_size})"
}

# Main
mkdir -p "${PROJECT_ROOT}/${BUILD_DIR}"

log "=== Downloading Node.js v${NODE_VERSION} ==="
download_node "arm64"
download_node "x64"
log "=== All Node.js downloads complete ==="
