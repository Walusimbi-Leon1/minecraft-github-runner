#!/usr/bin/env bash
# mc.sh — talk to the running Minecraft server console (screen session "mc").
# Usage:
#   ./mc.sh <command>       send a command, e.g.  ./mc.sh say hello
#   ./mc.sh log             follow the server log (Ctrl+C to exit)
#   ./mc.sh tail            last 50 log lines

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/server/server.log"

if [ $# -eq 0 ]; then
  echo "usage: ./mc.sh <server command> | log | tail"
  exit 1
fi

case "$1" in
  log)
    exec tail -f "$LOG"
    ;;
  tail)
    exec tail -50 "$LOG"
    ;;
  *)
    if ! screen -ls mc >/dev/null 2>&1; then
      echo "❌ Server not running — start it with: bash start.sh"
      exit 1
    fi
    screen -S mc -X stuff "$*"$'\r'
    echo "✅ sent: $*"
    ;;
esac
