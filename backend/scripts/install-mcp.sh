#!/usr/bin/env bash
# Connects AI assistants to TaskWidget over MCP so they can create tasks from a chat.
# Registers `taskwidget-server mcp` with Claude Desktop and Claude Code (whichever is installed).
# Run install-launch-agent.sh first: it installs the binary this points at.
set -euo pipefail

NAME="taskwidget"
BIN="$HOME/Library/Application Support/TaskWidget/bin/taskwidget-server"
DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

[ -x "$BIN" ] || { echo "✗ $BIN not found — run ./scripts/install-launch-agent.sh first" >&2; exit 1; }

# Sanity check: the server answers an MCP initialize.
reply="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
    | "$BIN" mcp 2>/dev/null | head -1)"
case "$reply" in
    *'"serverInfo"'*) echo "✓ MCP server responds" ;;
    *) echo "✗ $BIN mcp did not answer — is it an old build? Re-run install-launch-agent.sh" >&2; exit 1 ;;
esac

registered=0

if [ -d "$(dirname "$DESKTOP_CONFIG")" ]; then
    echo "→ Claude Desktop: adding \"$NAME\" to $DESKTOP_CONFIG"
    [ -f "$DESKTOP_CONFIG" ] && cp "$DESKTOP_CONFIG" "$DESKTOP_CONFIG.bak"
    /usr/bin/python3 - "$DESKTOP_CONFIG" "$NAME" "$BIN" <<'PY'
import json, os, sys
path, name, binary = sys.argv[1:4]
config = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        config = json.load(f)
config.setdefault("mcpServers", {})[name] = {"command": binary, "args": ["mcp"]}
with open(path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY
    echo "  restart Claude Desktop to load it (backup: $DESKTOP_CONFIG.bak)"
    registered=1
fi

if command -v claude >/dev/null 2>&1; then
    echo "→ Claude Code: registering \"$NAME\" for all projects"
    claude mcp remove --scope user "$NAME" >/dev/null 2>&1 || true
    claude mcp add --scope user "$NAME" -- "$BIN" mcp
    registered=1
fi

if [ "$registered" -eq 0 ]; then
    echo "No Claude Desktop or Claude Code found. For any other MCP client, add a stdio server:"
fi
cat <<EOF

Manual config for other MCP clients (Cursor, LM Studio, …):
  command: $BIN
  args:    ["mcp"]

Try it: ask your assistant "add a task to finish the report tomorrow, due Friday, high priority".
EOF
