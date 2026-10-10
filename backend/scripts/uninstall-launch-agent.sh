#!/usr/bin/env bash
# Stops the server and removes the LaunchAgent and binary. Your database is kept.
set -euo pipefail

LABEL="com.taskwidget.server"
SUPPORT_DIR="$HOME/Library/Application Support/TaskWidget"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$SUPPORT_DIR/bin/taskwidget-server"
echo "✓ LaunchAgent removed. Database kept at: $SUPPORT_DIR/tasks.db"
