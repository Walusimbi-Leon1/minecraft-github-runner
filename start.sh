#!/usr/bin/env bash
set -euo pipefail

# start.sh — Start the Minecraft server + a DIRECT public TCP address,
# then print the connection details you paste straight into Minecraft.
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

# ── Clean up any previous run ──────────────────────────
# [.] avoids pkill matching this script's own command line.
# NOTE: only the *tcp* cloudflared tunnel is killed — the colab-setup
# OpenClaw gateway tunnel (http://127.0.0.1:18789) is left alone.
pkill -f 'paper[.]jar' 2>/dev/null || true
sleep 2
pkill -9 -f 'paper[.]jar' 2>/dev/null || true
pkill -f '[b]ore local' 2>/dev/null || true
pkill -f '[c]loudflared tunnel --url tcp' 2>/dev/null || true
sleep 1

# ── Start the server (in a screen session named "mc") ──
cd "$SERVER_DIR"
echo "🚀 Starting $MC_VERSION server (heap ${RAM}) on port $PORT..."
# Clear any previous (possibly dead) 'mc' screen socket, or -dmS would fail.
screen -S mc -X quit 2>/dev/null || true
screen -wipe 2>/dev/null || true
# screen -L/-Logfile: server output goes to server.log AND stays reachable
# via the console (mc.sh). Without -L the log file would stay empty.
screen -dmS mc -L -Logfile "$SERVER_DIR/server.log" \
  "$JAVA_BIN" -Xms"$RAM" -Xmx"$RAM" -jar paper.jar --nogui

# Only look at log content written AFTER this run started (the log appends
# across runs — old "Done"/errors must not confuse this run's checks):
LOG_POS=$(wc -c < "$SERVER_DIR/server.log" 2>/dev/null || echo 0)
NEWLOG() { tail -c +$((LOG_POS + 1)) "$SERVER_DIR/server.log"; }

UP=0
SEEN=0
for _ in $(seq 1 240); do
  if NEWLOG | grep -q "Done ("; then
    UP=1
    break
  fi
  # A real fatal error (e.g. port already in use) beats a timeout wait:
  if NEWLOG | grep -qiE "Failed to bind|BindException|Failed to start the minecraft server|Fatal exception"; then
    echo "❌ Server failed to start — tail server/server.log"
    exit 1
  fi
  # Only declare "died" once the JVM was actually seen running (avoids the
  # race between cleanup and the new JVM spawning):
  if pgrep -f 'paper[.]jar' >/dev/null 2>&1; then
    SEEN=1
  elif [ "$SEEN" = 1 ]; then
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

# ── Direct public address (bore → bore.pub, no account) ──
# bore gives a raw TCP endpoint like bore.pub:43829 that Minecraft can
# connect to DIRECTLY — no client software, no extra steps.
ADDR=""
if [ -n "${BORE_BIN:-}" ] && [ -x "$BORE_BIN" ]; then
  echo "🌐 Opening direct tunnel via bore.pub (tcp://localhost:$PORT)..."
  setsid nohup "$BORE_BIN" local "$PORT" --to bore.pub \
    > bore.log 2>&1 < /dev/null &
  for _ in $(seq 1 30); do
    ADDR=$(grep -oE 'bore\.pub:[0-9]+' bore.log 2>/dev/null | tail -1 || true)
    [ -n "$ADDR" ] && break
    sleep 1
  done
fi

# ── Backup tunnel (cloudflared, only printed if bore failed) ──
CF_URL=""
if [ -z "$ADDR" ]; then
  echo "⚠️  bore.pub not reachable — falling back to Cloudflare quick tunnel"
  if command -v cloudflared >/dev/null 2>&1; then
    setsid nohup cloudflared tunnel --url "tcp://localhost:$PORT" --no-autoupdate \
      > cloudflared.log 2>&1 < /dev/null &
    for _ in $(seq 1 60); do
      CF_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' cloudflared.log 2>/dev/null | head -1 || true)
      [ -n "$CF_URL" ] && break
      sleep 1
    done
  fi
fi

echo ""
echo "=================================================="
echo "  ✅ Minecraft server is LIVE!"
echo "=================================================="
echo ""
if [ -n "$ADDR" ]; then
  echo "  🌐 DIRECT connection address (no extra software):"
  echo ""
  echo "      $ADDR"
  echo ""
  echo "  ▶ In Minecraft:  Multiplayer → Add Server → Server Address:"
  echo ""
  echo "      $ADDR"
  echo ""
  echo "      ...then just click join. That's it. ✅"
elif [ -n "$CF_URL" ]; then
  HOST="${CF_URL#https://}"
  echo "  ⚠️  Direct tunnel unavailable — using Cloudflare backup:"
  echo "      $CF_URL"
  echo ""
  echo "  ▶ This one needs cloudflared on your PC (see README → 'Backup tunnel'):"
  echo "      cloudflared access tcp --hostname $HOST --url 127.0.0.1:25565"
  echo "      Then in Minecraft:  Multiplayer → Add Server → address  localhost:25565"
else
  echo "  ❌ No tunnel could be opened. Check internet, then re-run: bash start.sh"
fi
echo ""
echo "  🎮 Version compatibility: ViaVersion + ViaBackwards + ViaRewind are"
echo "     installed — clients from 1.7.10 up to the latest can join."
echo ""
echo "  ⚠️  Offline mode (tunnel-friendly). Keep strangers out:"
echo "      ./mc.sh whitelist on"
echo "      ./mc.sh whitelist add <your-username>"
echo ""
echo "  Useful:  ./mc.sh <command>  (server console, e.g. ./mc.sh say hi)"
echo "           ./mc.sh log        (follow server log)"
echo "           ./save-world.sh    (backup world to a tarball)"
echo "           ./stop.sh          (stop server + tunnel)"
echo "  Logs:    server/server.log · server/bore.log · server/cloudflared.log"
echo ""
