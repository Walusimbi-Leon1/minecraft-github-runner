#!/usr/bin/env bash
set -euo pipefail

# setup.sh — One-shot Minecraft server setup for GitHub Actions runners
# (mirrors minecraft-colab's setup, adapted for GHA ubuntu-latest)
#
# Installs: Temurin JRE (Java 21 for modern Paper), PaperMC server jar
# (Paper → vanilla fallback), Via* version-compat plugins, bore (direct TCP
# tunnel), cloudflared (wss:// tunnel for Eaglercraft), and persists config
# to server/mc-env so start.sh can use the resolved binary paths.
#
# Usage:     bash setup.sh
# Env:       MC_VERSION=26.2   (Paper version, default 1.21.1 = modern)
#            MC_RAM=2048M      (server heap, used by start.sh)
#            MC_PORT=25565     (server port)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
mkdir -p "$SERVER_DIR" "$SERVER_DIR/plugins"

MC_VERSION="${MC_VERSION:-1.21.1}"
MC_RAM="${MC_RAM:-3G}"
MC_PORT="${MC_PORT:-25565}"

echo "=================================================="
echo "  ⛏️  LA5 GitHub Runner Setup — Minecraft Server"
echo "  $(date)"
echo "=================================================="

# ── 1/6 System prerequisites ──────────────────────────
echo ""
echo "[1/6] System prerequisites (curl, wget, jq, unzip, screen)..."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq >/dev/null 2>&1 || apt-get update -qq >/dev/null 2>&1
  sudo apt-get install -y -qq curl wget jq unzip screen >/dev/null 2>&1 || \
    apt-get install -y -qq curl wget jq unzip screen >/dev/null 2>&1
  echo "  ✅ curl, wget, jq, unzip, screen ready"
else
  echo "  ⚠️  No apt-get found — assuming prerequisites already exist"
fi

# ── 2/6 Java (Temurin JRE 21 for modern Paper, 1.21.1) ──
echo ""
echo "[2/6] Java (Temurin JRE 21 for modern Paper)..."
JAVA_DIR="$HOME/jdk21"
JAVA_BIN="$JAVA_DIR/bin/java"
if [ -x "$JAVA_BIN" ]; then
  echo "  ✅ Java already at $JAVA_DIR"
else
  echo "  ⬇️  Downloading Temurin JRE 21 (~50 MB)..."
  mkdir -p "$JAVA_DIR"
  curl -fsSL -o /tmp/jre.tar.gz \
    "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jre/hotspot/normal/eclipse"
  tar xzf /tmp/jre.tar.gz -C "$JAVA_DIR" --strip-components=1
  rm -f /tmp/jre.tar.gz
  echo "  ✅ Java: $("$JAVA_BIN" -version 2>&1 | head -1)"
fi

# ── 3/6 Minecraft server jar (Paper → vanilla fallback) ─
echo ""
echo "[3/6] Minecraft server jar (Paper $MC_VERSION)..."
if [ -f "$SERVER_DIR/paper.jar" ]; then
  echo "  ✅ Server jar already present ($(du -h "$SERVER_DIR/paper.jar" | cut -f1))"
else
  echo "  ⬇️  Downloading Paper $MC_VERSION (~40-60 MB)..."
  JAR_URL=$(python3 - "$MC_VERSION" <<'PY'
import json, sys, urllib.request
v = sys.argv[1]
try:
    bs = json.load(urllib.request.urlopen(f'https://fill.papermc.io/v3/projects/paper/versions/{v}/builds'))
    stable = [b for b in bs if b.get('channel') == 'STABLE']
    # API returns newest-first; pick the NEWEST stable build.
    b = (stable or bs)[0]
    print(b['downloads']['server:default']['url'])
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
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

# Accept the EULA (required before first start)
echo "eula=true" > "$SERVER_DIR/eula.txt"
echo "  ✅ eula.txt accepted (eula=true)"

# Pre-seed server.properties
cat > "$SERVER_DIR/server.properties" <<EOF
server-port=$MC_PORT
online-mode=false
motd=A LA5 Minecraft Server (GitHub Runner)
max-players=10
view-distance=8
simulation-distance=8
allow-nether=true
spawn-protection=0
allow-flight=false
hardcore=false
enable-command-block=false
pvp=true
gamemode=survival
difficulty=normal
EOF
echo "  ✅ server.properties created (port $MC_PORT, offline-mode)"

# ── 4/6 Version-compat plugins (Via*) ───────────────────
echo ""
echo "[4/6] Plugins: ViaVersion / ViaBackwards / ViaRewind..."
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

# ── 5/6 bore (direct TCP tunnel — address goes into Minecraft Add Server) ──
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
CLOUDFLARED_BIN="$CFBIN"
PORT=$MC_PORT
MC_RAM=$MC_RAM
MC_VERSION=$MC_VERSION
EOF

echo ""
echo "=================================================="
echo "  ✅ Setup complete"
echo "  Next:  bash start.sh"
echo "=================================================="
