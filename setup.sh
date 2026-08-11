#!/usr/bin/env bash
set -euo pipefail

# setup.sh — One-shot Minecraft server setup for Google Colab (ephemeral runtimes)
# Installs:  Temurin JRE 25 → PaperMC server jar (vanilla fallback) → cloudflared
# Usage:     bash setup.sh
# Safe to re-run (idempotent). Colab wipes the VM every session, so run it
# once per fresh runtime.
#
# Env overrides:
#   MC_VERSION=26.2     Paper version to install (default: latest stable Paper)
#   MC_RAM=2048M        Server heap size (default 2048M — used by start.sh)
#   MC_PORT=25565       Server port (default 25565)

START=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
mkdir -p "$SERVER_DIR"

MC_VERSION="${MC_VERSION:-}"
MC_RAM="${MC_RAM:-2048M}"
MC_PORT="${MC_PORT:-25565}"

echo "=================================================="
echo "  ⛏️  LA5 Colab Setup — Minecraft Server"
echo "  $(date)"
echo "=================================================="

# ── 1/4 System prerequisites ───────────────────────────
echo ""
echo "[1/4] System prerequisites (curl, unzip, screen)..."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq >/dev/null 2>&1 || apt-get update -qq >/dev/null 2>&1
  sudo apt-get install -y -qq curl unzip screen >/dev/null 2>&1 || apt-get install -y -qq curl unzip screen >/dev/null 2>&1
  echo "  ✅ curl, unzip, screen ready"
else
  echo "  ⚠️  No apt-get found — assuming prerequisites already exist"
fi

# ── 2/4 Java 25 (Temurin JRE) ──────────────────────────
echo ""
echo "[2/4] Java 25 (Temurin JRE)..."
JAVA_DIR="$HOME/jdk25"
JAVA_BIN="$JAVA_DIR/bin/java"
if [ -x "$JAVA_BIN" ]; then
  echo "  ✅ Java already at $JAVA_DIR"
else
  echo "  ⬇️  Downloading Temurin JRE 25 (~50 MB)..."
  mkdir -p "$JAVA_DIR"
  curl -fsSL -o /tmp/jre25.tar.gz \
    "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jre/hotspot/normal/eclipse"
  tar xzf /tmp/jre25.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm -f /tmp/jre25.tar.gz
  echo "  ✅ Java: $("$JAVA_BIN" -version 2>&1 | head -1)"
fi

# ── 3/4 Minecraft server jar (Paper → vanilla fallback) ─
echo ""
echo "[3/4] Minecraft server jar..."
if [ -z "$MC_VERSION" ]; then
  echo "  🔎 Detecting latest stable Paper version..."
  MC_VERSION=$(python3 - <<'PY'
import json, urllib.request
d = json.load(urllib.request.urlopen('https://fill.papermc.io/v3/projects/paper'))
# versions: { family: [versions...] } — first family is newest, first entry is its stable release
print(next(iter(d['versions'].values()))[0])
PY
)
  echo "  → Paper $MC_VERSION"
fi

JAR_URL=""
if [ -f "$SERVER_DIR/paper.jar" ]; then
  echo "  ✅ Server jar already present ($(du -h "$SERVER_DIR/paper.jar" | cut -f1))"
else
  echo "  ⬇️  Downloading Paper $MC_VERSION (~60 MB)..."
  JAR_URL=$(python3 - "$MC_VERSION" <<'PY'
import json, sys, urllib.request
v = sys.argv[1]
bs = json.load(urllib.request.urlopen(f'https://fill.papermc.io/v3/projects/paper/versions/{v}/builds'))
stable = [b for b in bs if b.get('channel') == 'STABLE']
b = (stable or bs)[-1]
print(b['downloads']['server:default']['url'])
PY
) || true
  if [ -n "$JAR_URL" ]; then
    curl -fsSL -o "$SERVER_DIR/paper.jar" "$JAR_URL" || JAR_URL=""
  fi
  if [ -z "$JAR_URL" ] || [ ! -s "$SERVER_DIR/paper.jar" ]; then
    echo "  ⚠️  Paper download failed — falling back to vanilla (latest release)..."
    read -r MC_VERSION JAR_URL < <(python3 - <<'PY'
import json, urllib.request
m = json.load(urllib.request.urlopen('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'))
rel = m['latest']['release']
vj = json.load(urllib.request.urlopen(next(x['url'] for x in m['versions'] if x['id'] == rel)))
print(rel, vj['downloads']['server']['url'])
PY
)
    curl -fsSL -o "$SERVER_DIR/paper.jar" "$JAR_URL"
    echo "  ✅ Vanilla $MC_VERSION downloaded"
  fi
fi

# Accept the EULA (required before first start; running your own server is allowed)
echo "eula=true" > "$SERVER_DIR/eula.txt"
echo "  ✅ eula.txt accepted (eula=true)"

# Pre-seed server.properties so first start is instant & tunnel-friendly
PROPS="$SERVER_DIR/server.properties"
if [ ! -f "$PROPS" ]; then
  cat > "$PROPS" <<EOF
server-port=$MC_PORT
online-mode=false
motd=A LA5 Minecraft Server (Colab) ⛏️
max-players=10
view-distance=8
white-list=false
enforce-secure-profile=false
EOF
  echo "  ✅ server.properties created"
fi
sed -i "s/^server-port=.*/server-port=$MC_PORT/" "$PROPS"
sed -i "s/^online-mode=.*/online-mode=false/" "$PROPS"
sed -i "s/^white-list=.*/white-list=false/" "$PROPS"
echo "  ✅ server.properties: port $MC_PORT · offline-mode (tunnel-friendly)"

# ── 4/4 cloudflared (tunnel client) ────────────────────
echo ""
echo "[4/4] cloudflared (Cloudflare quick tunnel)..."
if command -v cloudflared >/dev/null 2>&1; then
  echo "  ✅ cloudflared already installed ($(cloudflared --version 2>/dev/null | head -1))"
else
  if [ -w /usr/local/bin ]; then
    CFBIN=/usr/local/bin/cloudflared
  else
    CFBIN="$HOME/bin/cloudflared"
    mkdir -p "$HOME/bin"
  fi
  curl -fsSL -o "$CFBIN" \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  chmod +x "$CFBIN"
  echo "  ✅ cloudflared installed → $CFBIN"
fi

# ── Persist config for start.sh ────────────────────────
cat > "$SERVER_DIR/mc-env" <<EOF
MC_JAR="$SERVER_DIR/paper.jar"
JAVA_BIN="$JAVA_BIN"
PORT=$MC_PORT
MC_RAM=$MC_RAM
MC_VERSION=$MC_VERSION
EOF

echo ""
echo "=================================================="
echo "  ✅ Setup complete in $(( $(date +%s) - START ))s"
echo "  Next:  bash start.sh"
echo "=================================================="
