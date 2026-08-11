#!/usr/bin/env bash
set -euo pipefail

# start.sh — Start the Minecraft server + a public Cloudflare quick tunnel,
# then print the connection details you need to join from your PC.
# Usage:    bash start.sh
# Re-runnable: stops any previous server/tunnel from this repo first.
# Env:      MC_RAM=2048M  MC_PORT=25565  (optional overrides)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
ENV_FILE="$SERVER_DIR/mc-env"

echo "=================================================="
echo "  ⛏️  LA5 Colab Start — Minecraft Server"
echo "  $(date)"
echo "=================================================="

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Not set up yet — run:  bash setup.sh"
  exit 1
fi

# Capture per-run overrides BEFORE sourcing mc-env (which would clobber them)
ENV_PORT="${MC_PORT:-}"
ENV_RAM="${MC_RAM:-}"
. "$ENV_FILE"

PORT="${ENV_PORT:-$PORT}"
RAM="${ENV_RAM:-$MC_RAM}"

if [ ! -x "$JAVA_BIN" ]; then
  echo "❌ Java not found at $JAVA_BIN — run:  bash setup.sh"
  exit 1
fi
if [ ! -f "$MC_JAR" ]; then
  echo "❌ Server jar not found — run:  bash setup.sh"
  exit 1
fi
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "❌ cloudflared not found — run:  bash setup.sh"
  exit 1
fi

# ── Clean up any previous run ──────────────────────────
# [.] avoids pkill matching this script's own command line
pkill -f 'paper[.]jar' 2>/dev/null || true
sleep 2
pkill -9 -f 'paper[.]jar' 2>/dev/null || true
pkill -f '[c]loudflared tunnel --url tcp' 2>/dev/null || true
sleep 1

# ── Start the server (in a screen session named "mc") ──
cd "$SERVER_DIR"
echo "🚀 Starting $MC_VERSION server (heap ${RAM}) on port $PORT..."
# screen -L/-Logfile: server output goes to server.log AND stays reachable
# via the console (mc.sh). Without -L the log file would stay empty.
screen -dmS mc -L -Logfile "$SERVER_DIR/server.log" \
  "$JAVA_BIN" -Xms"$RAM" -Xmx"$RAM" -jar paper.jar --nogui

UP=0
for _ in $(seq 1 240); do
  if grep -q "Done (" server.log 2>/dev/null; then
    UP=1
    break
  fi
  if ! pgrep -f 'paper[.]jar' >/dev/null 2>&1; then
    echo "❌ Server process died — tail server/server.log for errors"
    exit 1
  fi
  sleep 1
done
if [ "$UP" = 0 ]; then
  echo "⚠️  Server still starting (not 'Done' yet) — tail server/server.log"
else
  echo "✅ Server fully running on 127.0.0.1:$PORT (screen session 'mc')"
fi

# ── Public tunnel (Cloudflare quick tunnel, no account needed) ──
echo "🌐 Starting Cloudflare quick tunnel (tcp://localhost:$PORT)..."
setsid nohup cloudflared tunnel --url "tcp://localhost:$PORT" --no-autoupdate \
  > cloudflared.log 2>&1 < /dev/null &

URL=""
for _ in $(seq 1 60); do
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' cloudflared.log 2>/dev/null | head -1 || true)
  [ -n "$URL" ] && break
  sleep 1
done

echo ""
echo "=================================================="
echo "  ✅ Minecraft server is LIVE!"
echo "=================================================="
echo ""
if [ -z "$URL" ]; then
  echo "  ⚠️  Tunnel URL not ready yet — tail server/cloudflared.log"
else
  HOST="${URL#https://}"
  echo "  🌐 Public tunnel:  $URL"
  echo ""
  echo "  ▶ ON YOUR PC — open the tunnel (one command):"
  echo ""
  echo "      Windows:   connect-windows.bat $URL"
  echo "      Mac/Linux: ./connect-mac.sh $URL"
  echo "      (or manually: cloudflared access tcp --hostname $HOST --url 127.0.0.1:25565)"
  echo ""
  echo "  ▶ In Minecraft:  Multiplayer → Add Server → address:"
  echo ""
  echo "      localhost:25565"
  echo ""
  echo "  ⚠️  Server runs in OFFLINE mode (tunnel-friendly). Whitelist players:"
  echo "      ./mc.sh whitelist add <your-username>"
  echo ""
  echo "  📌 Your Minecraft client version must match the server: $MC_VERSION"
fi
echo ""
echo "  Useful:  ./mc.sh <command>  (server console, e.g. ./mc.sh say hi)"
echo "           ./mc.sh log        (follow server log)"
echo "           ./save-world.sh    (backup world to a tarball)"
echo "           ./stop.sh          (stop server + tunnel)"
echo "  Logs:    server/server.log · server/cloudflared.log"
echo ""
