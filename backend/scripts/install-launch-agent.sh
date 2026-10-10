#!/usr/bin/env bash
# Builds the server and registers a LaunchAgent so it runs at login and restarts on crash.
set -euo pipefail

LABEL="com.taskwidget.server"
PORT="${TASKWIDGET_PORT:-3220}"
SUPPORT_DIR="$HOME/Library/Application Support/TaskWidget"
BIN_DIR="$SUPPORT_DIR/bin"
LOG_DIR="$HOME/Library/Logs/TaskWidget"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v cargo >/dev/null || { echo "cargo not found — install Rust from https://rustup.rs" >&2; exit 1; }

echo "→ Building release binary"
cargo build --release --manifest-path "$BACKEND_DIR/Cargo.toml"

echo "→ Installing to $BIN_DIR"
mkdir -p "$BIN_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
install -m 0755 "$BACKEND_DIR/target/release/taskwidget-server" "$BIN_DIR/taskwidget-server"

echo "→ Writing $PLIST"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_DIR/taskwidget-server</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>TASKWIDGET_PORT</key><string>$PORT</string>
        <key>RUST_LOG</key><string>info</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>$LOG_DIR/server.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/server.log</string>
</dict>
</plist>
PLIST

echo "→ (Re)loading LaunchAgent"
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
# bootout is asynchronous; bootstrapping before the old job is gone fails with error 5.
for _ in $(seq 1 20); do
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
    sleep 0.25
done
for attempt in 1 2 3; do
    launchctl bootstrap "$DOMAIN" "$PLIST" && break
    [ "$attempt" -eq 3 ] && { echo "✗ launchctl bootstrap failed" >&2; exit 1; }
    sleep 1
done

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
        echo "✓ taskwidget-server is running on http://127.0.0.1:$PORT"
        echo "  logs: $LOG_DIR/server.log"
        exit 0
    fi
    sleep 0.5
done
echo "✗ Server did not respond on port $PORT — check $LOG_DIR/server.log" >&2
exit 1
