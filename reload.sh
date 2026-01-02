#!/bin/bash
# Reload booru sidebar: kill, copy fresh assets, restart
# Usage: ./reload.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/quickshell"
SIDEBAR_DIR="$CONFIG_DIR/sidebar"

echo "=== Booru Sidebar Reload ==="

# 1. Kill running sidebar instance
echo "[1/3] Stopping running instance..."
pkill -f "qs.*-c.*sidebar" 2>/dev/null && echo "  Killed qs sidebar process" || echo "  No running instance found"
sleep 0.5

# 2. Copy fresh assets
echo "[2/3] Copying fresh assets..."

# Ensure directories exist
mkdir -p "$SIDEBAR_DIR"
mkdir -p "$CONFIG_DIR/modules/sidebar/anime"
mkdir -p "$CONFIG_DIR/modules/common/widgets"
mkdir -p "$CONFIG_DIR/modules/common/functions"
mkdir -p "$CONFIG_DIR/modules/common/utils"
mkdir -p "$CONFIG_DIR/services"

# Copy sidebar modules
cp -r "$REPO_DIR/modules/sidebar/"* "$CONFIG_DIR/modules/sidebar/"
echo "  Copied modules/sidebar/"

# Copy common modules (widgets, functions, utils, appearance)
cp -r "$REPO_DIR/modules/common/"* "$CONFIG_DIR/modules/common/"
echo "  Copied modules/common/"

# Copy services
cp -r "$REPO_DIR/services/"* "$CONFIG_DIR/services/"
echo "  Copied services/"

# Copy shell.qml to sidebar directory
cp "$REPO_DIR/shell.qml" "$SIDEBAR_DIR/shell.qml"
echo "  Copied shell.qml"

# Copy config.json if it doesn't exist (don't overwrite user config)
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    cp "$REPO_DIR/config.json" "$CONFIG_DIR/config.json"
    echo "  Copied config.json (new)"
else
    echo "  Skipped config.json (exists)"
fi

# 3. Restart sidebar
echo "[3/3] Starting sidebar..."
nohup qs -c sidebar > /dev/null 2>&1 &
disown
sleep 1

# Verify it's running
if pgrep -f "qs.*-c.*sidebar" > /dev/null; then
    echo "  Sidebar started successfully (PID: $(pgrep -f 'qs.*-c.*sidebar'))"
else
    echo "  Warning: Sidebar may not have started"
fi

echo "=== Done ==="
