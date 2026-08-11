#!/usr/bin/env bash
set -euo pipefail

# start.sh — Start the Minecraft server + public tunnels, print BOTH addresses:
#   1. bore.pub:PORT        → paste directly into Minecraft Java (Add Server)
#   2. wss://…trycloudflare → for Eaglercraft browser clients (Add Server)
# Also: restores a saved world from GitHub if present, and can auto-save.
# Usage:    bash start.sh
# Re-runnable: stops any previous server/tunnel from this repo first.
# Env:      MC_RAM=2048M  MC_PORT=25565  AUTOSAVE=15 (minutes, 0=off)

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
ENV_AUTOSAVE="${AUTOSAVE:-}"
. "$ENV_FILE"

PORT="${ENV_PORT:-$PORT}"
RAM="${ENV_RAM:-$MC_RAM}"
AUTOSAVE="${ENV_AUTOSAVE:-15}"

if [ ! -x "$JAVA_BIN" ]; then
  echo "❌ Java not found at $JAVA_BIN — run:  bash setup.sh"
  exit 1
fi
if [ ! -f "$MC_JAR" ]; then
  echo "❌ Server jar not found — run:  bash setup.sh"
  exit 1
fi

# ── World restore from GitHub (world-save release) ────
# If there's no local world yet, try to pull the last saved one from GitHub
# so we continue exactly where we left off on the previous Colab session.
if [ ! -d "$SERVER_DIR/world" ]; then
  echo "🔎 No local world — checking GitHub for a saved world..."
  REMOTE=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)
  TOKEN=""
  if [ -n "${GH_TOKEN:-}" ]; then TOKEN="$GH_TOKEN"; fi
  if [ -z "$TOKEN" ] && [ -f "$SCRIPT_DIR/.token" ]; then TOKEN="$(tr -d ' \r\n' < "$SCRIPT_DIR/.token")"; fi
  if [ -z "$TOKEN" ]; then
    case "$REMOTE" in
      https://*@github.com/*) TOKEN="${REMOTE#https://}"; TOKEN="${TOKEN%%@*}" ;;
    esac
  fi
  REPO=""
  case "${REMOTE:-}" in
    https://*github.com/*) REPO="${REMOTE##*github.com/}" ;;
    git@github.com:*) REPO="${REMOTE##git@github.com:}" ;;
  esac
  REPO="${REPO%.git}"
  if [ -n "$REPO" ] && [ -n "$TOKEN" ]; then
    # Private repos: browser_download_url 404s (signed redirect needs auth).
    # The API octet-stream endpoint always works with the token.
    API="https://api.github.com/repos/$REPO"
    AUTH="Authorization: Bearer $TOKEN"
    ASSET=$(curl -fsS -H "$AUTH" "$API/releases/tags/world-save" 2>/dev/null \
      | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('assets',[]):
    if a['name']=='world.tar.gz':
        print(a['id']); break
" 2>/dev/null || true)
    if [ -n "$ASSET" ]; then
      echo "  ⬇️  Restoring world from GitHub release 'world-save'..."
      if curl -fsSL -H "$AUTH" -H "Accept: application/octet-stream" \
          -o /tmp/world-restore.tar.gz "$API/releases/assets/$ASSET" \
          && tar xzf /tmp/world-restore.tar.gz -C "$SERVER_DIR" \
          && rm -f /tmp/world-restore.tar.gz; then
        echo "  ✅ World restored!"
      else
        echo "  ⚠️  World restore failed — starting fresh"
      fi
    else
      echo "  ℹ️  No saved world found — a new world will be generated."
    fi
  else
    echo "  ℹ️  No GitHub token/repo — a new world will be generated."
  fi
else
  echo "✅ Local world found — using it."
fi

# ── Clean up any previous run ──────────────────────────
# [.] avoids pkill matching this script's own command line.
# NOTE: only the *tcp* cloudflared tunnel is killed — the colab-setup
# OpenClaw gateway tunnel (http://127.0.0.1:18789) is left alone.
pkill -f 'paper[.]jar' 2>/dev/null || true
sleep 2
pkill -9 -f 'paper[.]jar' 2>/dev/null || true
pkill -f "[b]ore local $PORT" 2>/dev/null || true
pkill -f '[c]loudflared tunnel --url tcp' 2>/dev/null || true
pkill -f "[c]loudflared tunnel --url http://localhost:$PORT" 2>/dev/null || true
sleep 1

# ── Start the server (in a screen session named "mc") ──
cd "$SERVER_DIR"
echo "🚀 Starting $MC_VERSION server (heap ${RAM}) on port $PORT..."
# Clear any previous (possibly dead) 'mc' screen socket, or -dmS would fail.
screen -S mc -X quit 2>/dev/null || true
screen -wipe 2>/dev/null || true
# Java 8-era servers (1.12.2) run on JRE 8 (auto-installed for legacy mode)
# — no add-opens needed (that flag is Java 9+). Modern Paper runs on JRE 25.
screen -dmS mc -L -Logfile "$SERVER_DIR/server.log" \
  "$JAVA_BIN" -Xms"$RAM" -Xmx"$RAM" -jar paper.jar

# Only look at log content written AFTER this run started (the log appends
# across runs — old "Done"/errors must not confuse this run's checks):
LOG_POS=$(wc -c < "$SERVER_DIR/server.log" 2>/dev/null || echo 0)
NEWLOG() { tail -c +$((LOG_POS + 1)) "$SERVER_DIR/server.log"; }

UP=0
SEEN=0
for _ in $(seq 1 300); do
  if NEWLOG | grep -q "Done ("; then
    UP=1
    break
  fi
  # A real fatal error (e.g. port already in use) beats a timeout wait:
  if NEWLOG | grep -qiE "Failed to bind|BindException|Failed to start the minecraft server|Fatal exception|Overworld settings missing"; then
    echo "❌ Server failed to start — tail server/server.log"
    echo "   (corrupt world? fix: rm -rf server/world* then re-run)"
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

# ── Direct address for Minecraft Java (bore → bore.pub) ──
ADDR=""
if [ -n "${BORE_BIN:-}" ] && [ -x "$BORE_BIN" ]; then
  echo "🌐 Opening direct tunnel (bore.pub) for Java clients..."
  setsid nohup "$BORE_BIN" local "$PORT" --to bore.pub \
    > bore.log 2>&1 < /dev/null &
  for _ in $(seq 1 30); do
    ADDR=$(grep -oE 'bore\.pub:[0-9]+' bore.log 2>/dev/null | tail -1 || true)
    [ -n "$ADDR" ] && break
    sleep 1
  done
fi

# ── wss:// address for Eaglercraft (cloudflared HTTP tunnel) ──
CF_URL=""
if command -v cloudflared >/dev/null 2>&1; then
  echo "🌐 Opening wss:// tunnel (cloudflared) for Eaglercraft..."
  setsid nohup cloudflared tunnel --url "http://localhost:$PORT" --no-autoupdate \
    > cloudflared.log 2>&1 < /dev/null &
  for _ in $(seq 1 60); do
    CF_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' cloudflared.log 2>/dev/null | head -1 || true)
    [ -n "$CF_URL" ] && break
    sleep 1
  done
fi

echo ""
echo "=================================================="
echo "  ✅ Minecraft server is LIVE!"
echo "=================================================="
echo ""
if [ -n "$ADDR" ]; then
  echo "  🖥️  JAVA EDITION (normal Minecraft client):"
  echo "      Multiplayer → Add Server → Server Address:"
  echo ""
  echo "      $ADDR"
  echo ""
fi
if [ -n "$CF_URL" ]; then
  echo "  🌐 EAGLERCRAFT (browser client, e.g. the offline HTML):"
  echo "      Multiplayer → Add Server → Server Address:"
  echo ""
  echo "      ${CF_URL/https:/wss:}"
  echo ""
  echo "      (that's the same URL with wss:// instead of https://)"
fi
if [ -z "$ADDR" ] && [ -z "$CF_URL" ]; then
  echo "  ❌ No tunnel could be opened. Check internet, then re-run: bash start.sh"
fi
echo "  🎮 Version compatibility: ViaVersion + ViaBackwards + ViaRewind"
echo "     installed — clients from 1.7.10 up to the latest can join."
if [ "${EAGLER_MODE:-0}" = 1 ]; then
  echo "     EaglerXServer active — Eaglercraft 1.5.2 / 1.8 / 1.12.2 supported."
fi
echo ""
echo "  ⚠️  Offline mode (tunnel-friendly). Keep strangers out:"
echo "      ./mc.sh whitelist on"
echo "      ./mc.sh whitelist add <your-username>"
echo ""
echo "  💾 World save:  ./save-world.sh  (uploads to GitHub, survives Colab resets)"
if [ "$AUTOSAVE" -gt 0 ] 2>/dev/null; then
  echo "     Auto-save every ${AUTOSAVE} min is ON (AUTOSAVE=0 disables)."
  ( while true; do sleep $((AUTOSAVE * 60)); bash "$SCRIPT_DIR/save-world.sh" >/dev/null 2>&1; done ) &
  disown
fi
echo ""
echo "  Useful:  ./mc.sh <command>  (server console, e.g. ./mc.sh say hi)"
echo "           ./mc.sh log        (follow server log)"
echo "           ./stop.sh          (stop server + tunnels)"
echo "  Logs:    server/server.log · server/bore.log · server/cloudflared.log"
echo ""
