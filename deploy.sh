#!/bin/bash
# Deploy booru sidebar from repo to quickshell config directory
#
# This script:
#   1. Stops any running booru-sidebar instance
#   2. Copies all source files to ~/.config/quickshell/booru-sidebar/
#   3. Restarts the sidebar
#
# Use this for development: edit files in repo, run ./deploy.sh to test changes.
# Config.json is preserved if it already exists (won't overwrite user settings).
#
# Usage: ./deploy.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/quickshell"
SIDEBAR_DIR="$CONFIG_DIR/booru-sidebar"

echo "=== Booru Sidebar Deploy ==="

# 1. Kill running sidebar instance (both -c booru-sidebar and --path variants)
echo "[1/3] Stopping running instance..."
killed=0
pkill -f "qs.*-c.*booru-sidebar" 2>/dev/null && { echo "  Killed qs -c booru-sidebar"; killed=1; }
pkill -f "qs.*--path.*/quickshell-booru-sidebar" 2>/dev/null && { echo "  Killed qs --path instance"; killed=1; }
pkill -f "qs.*--path \." 2>/dev/null && { echo "  Killed qs --path . instance"; killed=1; }
[ $killed -eq 0 ] && echo "  No running instance found"
sleep 0.5

# 2. Copy fresh assets
echo "[2/3] Copying fresh assets..."

# Ensure directories exist
mkdir -p "$SIDEBAR_DIR/modules/sidebar/anime"
mkdir -p "$SIDEBAR_DIR/modules/common/widgets"
mkdir -p "$SIDEBAR_DIR/modules/common/functions"
mkdir -p "$SIDEBAR_DIR/modules/common/utils"
mkdir -p "$SIDEBAR_DIR/services"

# Copy sidebar modules
cp -r "$REPO_DIR/modules/sidebar/"* "$SIDEBAR_DIR/modules/sidebar/"
echo "  Copied modules/sidebar/"

# Copy common modules (widgets, functions, utils, appearance)
cp -r "$REPO_DIR/modules/common/"* "$SIDEBAR_DIR/modules/common/"
echo "  Copied modules/common/"

# Copy services
cp -r "$REPO_DIR/services/"* "$SIDEBAR_DIR/services/"
echo "  Copied services/"

# Copy shell.qml
cp "$REPO_DIR/shell.qml" "$SIDEBAR_DIR/shell.qml"
echo "  Copied shell.qml"

# Copy config.json if it doesn't exist (don't overwrite user config)
if [ ! -f "$SIDEBAR_DIR/config.json" ]; then
    cp "$REPO_DIR/config.json" "$SIDEBAR_DIR/config.json"
    echo "  Copied config.json (new)"
else
    echo "  Skipped config.json (exists)"
fi

# 3. Restart sidebar
echo "[3/3] Starting sidebar..."
nohup qs -c booru-sidebar > /dev/null 2>&1 &
disown
sleep 1

# Verify it's running
if pgrep -f "qs.*-c.*booru-sidebar" > /dev/null; then
    echo "  Sidebar started successfully (PID: $(pgrep -f 'qs.*-c.*booru-sidebar'))"
else
    echo "  Warning: Sidebar may not have started"
fi

echo "=== Deploy Complete ==="
