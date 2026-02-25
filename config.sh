#!/usr/bin/env bash
# config.sh — Central configuration for n8n DMG installer
# All scripts source this file for shared constants.

NODE_VERSION="22.16.0"
N8N_VERSION="2.7.4"
N8N_PORT=5678
N8N_HOST="localhost"

# Install location on the target machine
INSTALL_DIR="${HOME}/.n8n-local"

# LaunchAgent
LAUNCHAGENT_LABEL="com.n8n.local"
LAUNCHAGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"

# Build directories (relative to project root)
BUILD_DIR="build"
DIST_DIR="dist"

# DMG settings
DMG_VOLUME_NAME="n8n Installer"
DMG_FILENAME="n8n-local-installer.dmg"

# Node.js download base URL
NODE_BASE_URL="https://nodejs.org/dist/v${NODE_VERSION}"

# n8n environment variables
N8N_DIAGNOSTICS_ENABLED="false"
N8N_VERSION_NOTIFICATIONS_ENABLED="false"
N8N_SECURE_COOKIE="false"
DB_SQLITE_POOL_SIZE=4

# Terminal (xterm.js)
XTERM_JS_VERSION="5.5.0"

# Log settings
LOG_DIR="${INSTALL_DIR}/logs"
LOG_MAX_SIZE_MB=50
