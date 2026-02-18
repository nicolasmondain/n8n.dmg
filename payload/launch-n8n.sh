#!/usr/bin/env bash
# launch-n8n.sh — Called by LaunchAgent to start n8n
# This script is installed to ~/.n8n-local/bin/launch-n8n.sh
set -euo pipefail

INSTALL_DIR="${HOME}/.n8n-local"
NODE_BIN="${INSTALL_DIR}/node/bin/node"
N8N_BIN="${INSTALL_DIR}/n8n/node_modules/.bin/n8n"
LOG_DIR="${INSTALL_DIR}/logs"
LOG_FILE="${LOG_DIR}/n8n.log"
LOG_MAX_SIZE_BYTES=$((50 * 1024 * 1024))  # 50MB

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log rotation: if log exceeds 50MB, rotate to .old
if [[ -f "$LOG_FILE" ]]; then
    log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if (( log_size > LOG_MAX_SIZE_BYTES )); then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi
fi

# Verify node binary exists
if [[ ! -x "$NODE_BIN" ]]; then
    echo "ERROR: Node.js binary not found at ${NODE_BIN}" >> "$LOG_FILE"
    exit 1
fi

# Verify n8n exists
if [[ ! -f "$N8N_BIN" ]]; then
    echo "ERROR: n8n not found at ${N8N_BIN}" >> "$LOG_FILE"
    exit 1
fi

# Add bundled node to PATH
export PATH="${INSTALL_DIR}/node/bin:${PATH}"

# n8n environment — critical for local HTTP setup
export N8N_SECURE_COOKIE="${N8N_SECURE_COOKIE:-false}"
export DB_SQLITE_POOL_SIZE="${DB_SQLITE_POOL_SIZE:-4}"
export N8N_USER_FOLDER="${N8N_USER_FOLDER:-${HOME}}"
export EXECUTIONS_DATA_PRUNE="${EXECUTIONS_DATA_PRUNE:-true}"
export EXECUTIONS_DATA_MAX_AGE="${EXECUTIONS_DATA_MAX_AGE:-336}"

# exec replaces this shell so launchd tracks the correct PID
exec "$NODE_BIN" "$N8N_BIN" start >> "$LOG_FILE" 2>&1
