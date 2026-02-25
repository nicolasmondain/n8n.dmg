# Makefile — n8n macOS DMG Installer build orchestrator
.PHONY: all check-deps download-node bundle-n8n fetch-icon app-bundle terminal-assets manager-app dmg clean

SHELL := /bin/bash

all: dmg

# ─── Dependency check ─────────────────────────────────────────────────────────

check-deps:
	@echo "Checking build dependencies..."
	@command -v curl    >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
	@command -v rsync   >/dev/null 2>&1 || { echo "rsync is required"; exit 1; }
	@command -v hdiutil >/dev/null 2>&1 || { echo "hdiutil is required (macOS only)"; exit 1; }
	@command -v shasum  >/dev/null 2>&1 || { echo "shasum is required"; exit 1; }
	@command -v swiftc  >/dev/null 2>&1 || { echo "swiftc is required (install Xcode Command Line Tools)"; exit 1; }
	@echo "All dependencies found."

# ─── Build stages ─────────────────────────────────────────────────────────────

download-node: check-deps
	@bash scripts/download-node.sh

bundle-n8n: download-node
	@bash scripts/bundle-n8n.sh

fetch-icon: check-deps
	@bash scripts/fetch-icon.sh

app-bundle: check-deps fetch-icon
	@bash scripts/create-app-bundle.sh

terminal-assets: check-deps
	@bash scripts/build-terminal-assets.sh

manager-app: check-deps fetch-icon terminal-assets
	@bash scripts/build-manager-app.sh

dmg: bundle-n8n app-bundle manager-app
	@bash scripts/build-dmg.sh

# ─── Clean ────────────────────────────────────────────────────────────────────

clean:
	@echo "Cleaning build artifacts..."
	rm -rf build/ dist/
	@echo "Clean complete."
