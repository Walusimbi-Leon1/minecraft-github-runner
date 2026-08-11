#!/usr/bin/env bash
# stop.sh — gracefully stop the Minecraft server + tunnel.
# Falls back to SIGKILL if the JVM ignores the graceful stop.
set -euo pipefail

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
pkill -f '[c]loudflared tunnel --url tcp' 2>/dev/null || true

echo "✅ Server and tunnel stopped."
