#!/usr/bin/env bash
set -euo pipefail

# setup.sh — One-shot Minecraft server setup for Google Colab (ephemeral runtimes)
#
# Installs (for the default EAGLER stack — Paper 1.12.2):
#   Temurin JRE 17 → PaperMC 1.12.2 → Via* version-compat plugins →
#   EaglerXServer + EaglerXRewind (browser/Eaglercraft support) →
#   bore (direct TCP tunnel) + cloudflared (wss backup tunnel)
#
# Usage:     bash setup.sh
# Safe to re-run (idempotent). Colab wipes the VM every session, so run it
# once per fresh runtime.
#
# Env overrides:
#   MC_VERSION=1.12.2     Paper version. Default 1.12.2 = Eagler-compatible
#                         (Eaglercraft browser clients + Via* covers every
#                         other version). Set e.g. 26.2 for latest-Paper mode
#                         (Eagler plugins are skipped — they need old Bukkit).
#   MC_RAM=2048M          Server heap size (default 2048M — used by start.sh)
#   MC_PORT=25565         Server port (default 25565)

START=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
mkdir -p "$SERVER_DIR" "$SERVER_DIR/plugins"

MC_VERSION="${MC_VERSION:-1.12.2}"
MC_RAM="${MC_RAM:-2048M}"
MC_PORT="${MC_PORT:-25565}"

# Legacy Paper (<=1.16, e.g. 1.12.2 Eagler stack) needs Java 8: its
# paperclip bootstrapper can't patch on modern JVMs. Modern needs 21+.
MAJOR="${MC_VERSION%%.*}"
MINOR="${MC_VERSION#*.}"; MINOR="${MINOR%%.*}"
EAGLER_MODE=0
JAVA_MAJOR=25
if [ "$MAJOR" = 1 ] && [ "${MINOR:-0}" -le 16 ]; then
  EAGLER_MODE=1
  JAVA_MAJOR=8
fi

echo "=================================================="
echo "  ⛏️  LA5 Colab Setup — Minecraft Server"
echo "  $(date)"
echo "=================================================="

# ── 1/6 System prerequisites ──────────────────────────
echo ""
echo "[1/6] System prerequisites (curl, unzip, screen)..."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq >/dev/null 2>&1 || apt-get update -qq >/dev/null 2>&1
  sudo apt-get install -y -qq curl unzip screen >/dev/null 2>&1 || apt-get install -y -qq curl unzip screen >/dev/null 2>&1
  echo "  ✅ curl, unzip, screen ready"
else
  echo "  ⚠️  No apt-get found — assuming prerequisites already exist"
fi

# ── 2/6 Java (Temurin JRE, version auto-picked) ───────
echo ""
echo "[2/6] Java $JAVA_MAJOR (Temurin JRE)..."
JAVA_DIR="$HOME/jdk$JAVA_MAJOR"
JAVA_BIN="$JAVA_DIR/bin/java"
if [ -x "$JAVA_BIN" ]; then
  echo "  ✅ Java already at $JAVA_DIR"
else
  echo "  ⬇️  Downloading Temurin JRE $JAVA_MAJOR (~50 MB)..."
  mkdir -p "$JAVA_DIR"
  curl -fsSL -o /tmp/jre.tar.gz \
    "https://api.adoptium.net/v3/binary/latest/$JAVA_MAJOR/ga/linux/x64/jre/hotspot/normal/eclipse"
  tar xzf /tmp/jre.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm -f /tmp/jre.tar.gz
  echo "  ✅ Java: $("$JAVA_BIN" -version 2>&1 | head -1)"
fi

# ── 3/6 Minecraft server jar (Paper → vanilla fallback) ─
echo ""
echo "[3/6] Minecraft server jar (Paper $MC_VERSION)..."
JAR_URL=""
if [ -f "$SERVER_DIR/paper.jar" ]; then
  echo "  ✅ Server jar already present ($(du -h "$SERVER_DIR/paper.jar" | cut -f1))"
else
  echo "  ⬇️  Downloading Paper $MC_VERSION (~40-60 MB)..."
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

# Legacy Paper ships as a "paperclip" wrapper that downloads the vanilla jar
# from an old S3 URL that is now DEAD (404). Pre-seed its cache from
# piston-meta so it never needs that URL.
if [ "$EAGLER_MODE" = 1 ] && [ ! -s "$SERVER_DIR/cache/mojang_$MC_VERSION.jar" ]; then
  echo "  ⬇️  Seeding paperclip vanilla-jar cache (piston-meta)..."
  mkdir -p "$SERVER_DIR/cache"
  VURL=$(python3 - "$MC_VERSION" <<'PY2'
import json, sys, urllib.request
v = sys.argv[1]
m = json.load(urllib.request.urlopen('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'))
entry = next((x for x in m['versions'] if x['id'] == v), None)
if entry:
    vj = json.load(urllib.request.urlopen(entry['url']))
    print(vj['downloads']['server']['url'])
PY2
) || true
  if [ -n "$VURL" ]; then
    curl -fsSL -o "$SERVER_DIR/cache/mojang_$MC_VERSION.jar" "$VURL" && \
      echo "  ✅ vanilla jar cached" || echo "  ⚠️  vanilla cache seed failed (server may fail to patch)"
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
view-distance=6
white-list=false
EOF
  echo "  ✅ server.properties created"
fi
sed -i "s/^server-port=.*/server-port=$MC_PORT/" "$PROPS"
sed -i "s/^online-mode=.*/online-mode=false/" "$PROPS"
sed -i "s/^white-list=.*/white-list=false/" "$PROPS"
echo "  ✅ server.properties: port $MC_PORT · offline-mode (tunnel-friendly)"

# ── 4/6 Version-compat + Eaglercraft plugins ───────────
echo ""
echo "[4/6] Plugins: Via* (all versions) + EaglerXServer (browser clients)..."
# ViaVersion/ViaBackwards/ViaRewind — any Java client 1.7.10 → latest joins
for PLUGIN in viaversion viabackwards viarewind; do
  JAR="$SERVER_DIR/plugins/$PLUGIN.jar"
  if [ -s "$JAR" ]; then
    echo "  ✅ $PLUGIN already present ($(du -h "$JAR" | cut -f1))"
    continue
  fi
  echo "  ⬇️  Downloading $PLUGIN (latest stable)..."
  DL=$(python3 - "$PLUGIN" <<'PY'
import json, sys, urllib.request, urllib.parse
pid = sys.argv[1]
try:
    q = urllib.parse.urlencode({'loaders': '["paper","spigot"]', 'limit': 10})
    d = json.load(urllib.request.urlopen(f'https://api.modrinth.com/v2/project/{pid}/version?{q}'))
except Exception:
    d = json.load(urllib.request.urlopen(f'https://api.modrinth.com/v2/project/{pid}/version?limit=10'))
v = next((x for x in d if 'SNAPSHOT' not in x['version_number']), d[0])
f = v['files'][0]
print(f['url'])
print(f['hashes'].get('sha1', ''))
PY
) || true
  URL=$(echo "$DL" | sed -n 1p)
  SHA1=$(echo "$DL" | sed -n 2p)
  if [ -z "$URL" ]; then
    echo "  ⚠️  Could not resolve $PLUGIN download URL (offline?)"
    continue
  fi
  curl -fsSL -o "$JAR" "$URL" || { echo "  ⚠️  Download failed for $PLUGIN"; continue; }
  if [ -n "$SHA1" ] && command -v sha1sum >/dev/null 2>&1; then
    if [ "$(sha1sum "$JAR" | cut -d' ' -f1)" != "$SHA1" ]; then
      echo "  ⚠️  sha1 mismatch for $PLUGIN"
    fi
  fi
  echo "  ✅ $PLUGIN installed"
done

# EaglerXServer + EaglerXRewind — Eaglercraft browser clients (1.5/1.8/1.12)
# Only for the legacy/Eagler server stack (they need old Bukkit APIs).
if [ "$EAGLER_MODE" = 1 ]; then
  for PLUGIN in EaglerXServer EaglerXRewind; do
    JAR="$SERVER_DIR/plugins/$PLUGIN.jar"
    if [ -s "$JAR" ]; then
      echo "  ✅ $PLUGIN already present ($(du -h "$JAR" | cut -f1))"
      continue
    fi
    echo "  ⬇️  Downloading $PLUGIN v1.1.1..."
    curl -fsSL -o "$JAR" \
      "https://github.com/lax1dude/eaglerxserver/releases/download/v1.1.1/$PLUGIN.jar" \
      || { echo "  ⚠️  Download failed for $PLUGIN"; continue; }
    echo "  ✅ $PLUGIN installed"
  done
  echo "  ✅ Eaglercraft support ready — browser clients (wss://) can join"
else
  echo "  ⏭️  Eagler plugins skipped (MC_VERSION $MC_VERSION is too new for Eaglercraft)"
fi

# ── 5/6 bore (direct TCP tunnel — address goes straight into Minecraft) ──
echo ""
echo "[5/6] bore (direct TCP tunnel via bore.pub, no account needed)..."
BORE_BIN=""
if command -v bore >/dev/null 2>&1; then
  BORE_BIN="$(command -v bore)"
  echo "  ✅ bore already on PATH ($(bore --version 2>/dev/null | head -1))"
elif [ -x "$SERVER_DIR/bore" ]; then
  BORE_BIN="$SERVER_DIR/bore"
  echo "  ✅ bore already at $BORE_BIN"
else
  echo "  ⬇️  Downloading bore v0.6.0 (~3 MB)..."
  curl -fsSL -o /tmp/bore.tar.gz \
    "https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-v0.6.0-x86_64-unknown-linux-musl.tar.gz"
  tar xzf /tmp/bore.tar.gz -C "$SERVER_DIR"
  rm -f /tmp/bore.tar.gz
  chmod +x "$SERVER_DIR/bore"
  BORE_BIN="$SERVER_DIR/bore"
  echo "  ✅ bore installed → $BORE_BIN"
fi

# ── 6/6 cloudflared (wss:// tunnel for Eaglercraft + backup) ──
echo ""
echo "[6/6] cloudflared (wss:// tunnel for Eaglercraft + backup)..."
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

# ── Persist config for start.sh ───────────────────────
cat > "$SERVER_DIR/mc-env" <<EOF
MC_JAR="$SERVER_DIR/paper.jar"
JAVA_BIN="$JAVA_BIN"
BORE_BIN="$BORE_BIN"
PORT=$MC_PORT
MC_RAM=$MC_RAM
MC_VERSION=$MC_VERSION
EAGLER_MODE=$EAGLER_MODE
EOF

echo ""
echo "=================================================="
echo "  ✅ Setup complete in $(( $(date +%s) - START ))s"
echo "  Next:  bash start.sh"
echo "=================================================="
