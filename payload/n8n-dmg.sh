#!/usr/bin/env bash
# n8n-dmg.sh — CLI helper for managing the local n8n service
# Installed to ~/.n8n-local/bin/n8n-dmg.sh
set -euo pipefail

INSTALL_DIR="${HOME}/.n8n-local"
LAUNCHAGENT_LABEL="com.n8n.local"
LAUNCHAGENT_PLIST="${HOME}/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
GUI_UID=$(id -u)

# Read port from persisted config, fall back to env var, then default
if [[ -f "${INSTALL_DIR}/.port" ]]; then
    N8N_PORT=$(cat "${INSTALL_DIR}/.port")
else
    N8N_PORT="${N8N_PORT:-5678}"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo -e "${CYAN}n8n-dmg${NC} — manage your local n8n service"
    echo ""
    echo "Usage: n8n-dmg {start|stop|restart|status|logs|open|ui}"
    echo ""
    echo "  start    Start n8n service"
    echo "  stop     Stop n8n service"
    echo "  restart  Restart n8n service"
    echo "  status   Show if n8n is running + PID"
    echo "  logs     Tail the n8n logs"
    echo "  open     Open n8n in browser"
    echo "  ui       Open n8n native app"
    echo ""
}

is_loaded() {
    launchctl print "gui/${GUI_UID}/${LAUNCHAGENT_LABEL}" &>/dev/null
}

get_pid() {
    launchctl print "gui/${GUI_UID}/${LAUNCHAGENT_LABEL}" 2>/dev/null \
        | grep -o 'pid = [0-9]*' \
        | awk '{print $3}'
}

cmd_start() {
    if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
        echo -e "${RED}Error:${NC} LaunchAgent plist not found at ${LAUNCHAGENT_PLIST}"
        echo "Is n8n installed? Try reinstalling."
        exit 1
    fi

    if is_loaded; then
        echo -e "${YELLOW}n8n service is already loaded.${NC}"
        cmd_status
        return
    fi

    echo -e "Starting n8n..."
    launchctl bootstrap "gui/${GUI_UID}" "$LAUNCHAGENT_PLIST"
    sleep 2
    cmd_status
}

cmd_stop() {
    if ! is_loaded; then
        echo -e "${YELLOW}n8n service is not running.${NC}"
        return
    fi

    echo -e "Stopping n8n..."
    launchctl bootout "gui/${GUI_UID}/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
    echo -e "${GREEN}n8n stopped.${NC}"
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

cmd_status() {
    if is_loaded; then
        local pid
        pid=$(get_pid)
        if [[ -n "$pid" && "$pid" != "0" ]]; then
            echo -e "${GREEN}n8n is running${NC} (PID: ${pid})"
        else
            echo -e "${YELLOW}n8n service is loaded but process is not running${NC}"
            echo "It may be starting up or has crashed. Check logs:"
            echo "  n8n-dmg logs"
        fi
    else
        echo -e "${RED}n8n is not running${NC}"
    fi

    # Check if port is listening
    if lsof -i ":${N8N_PORT}" -sTCP:LISTEN &>/dev/null; then
        echo -e "Port ${N8N_PORT}: ${GREEN}listening${NC}"
        echo -e "URL: http://localhost:${N8N_PORT}"
    else
        echo -e "Port ${N8N_PORT}: ${RED}not listening${NC}"
    fi
}

cmd_logs() {
    local log_file="${INSTALL_DIR}/logs/n8n.log"
    if [[ ! -f "$log_file" ]]; then
        echo -e "${YELLOW}No log file found at ${log_file}${NC}"
        exit 1
    fi
    echo -e "${CYAN}Tailing ${log_file}${NC} (Ctrl+C to stop)"
    tail -f "$log_file"
}

cmd_open() {
    open "http://localhost:${N8N_PORT}"
}

cmd_ui() {
    local app_path="${INSTALL_DIR}/n8n.app"
    if [[ -d "$app_path" ]]; then
        open "$app_path"
    else
        echo -e "${RED}n8n app not found at ${app_path}${NC}"
        echo "Falling back to browser..."
        cmd_open
    fi
}

# Main
case "${1:-}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_restart ;;
    status)  cmd_status ;;
    logs)    cmd_logs ;;
    open)    cmd_open ;;
    ui)      cmd_ui ;;
    *)       usage; exit 1 ;;
esac
