#!/usr/bin/env bash
# stop.sh — gracefully stop the Minecraft server + tunnel.
# Falls back to SIGKILL if the JVM ignores the graceful stop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve this instance's port (from mc-env if present, else default)
PORT=25565
if [ -f "$SCRIPT_DIR/server/mc-env" ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/server/mc-env" 2>/dev/null || true
fi

if screen -ls mc >/dev/null 2>&1; then
  echo "🛑 Sending 'stop' to the server..."
  screen -S mc -X stuff 'stop'$'\r'
fi

# TERM first (graceful save), then KILL if it lingers.
# [.] avoids pkill matching this script's own command line.
pkill -f 'paper[.]jar' 2>/dev/null || true
for _ in $(seq 1 10); do
  pgrep -f 'paper[.]jar' >/dev/null 2>&1 || break
  sleep 1
done
pkill -9 -f 'paper[.]jar' 2>/dev/null || true
pkill -f "[b]ore local $PORT" 2>/dev/null || true
pkill -f '[c]loudflared tunnel --url tcp' 2>/dev/null || true
pkill -f "[c]loudflared tunnel --url http://localhost:$PORT" 2>/dev/null || true
# Kill the tunnel processes we started
[ -f "$SCRIPT_DIR/bore.pid" ] && kill "$(cat "$SCRIPT_DIR/bore.pid")" 2>/dev/null || true
pkill -f '[c]loudflared tunnel --url http://localhost:' 2>/dev/null || true
sleep 3

echo "✅ Server and tunnels stopped."
