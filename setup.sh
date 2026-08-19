#!/bin/bash
set -euo pipefail

# --- GitHub Actions setup ---
# ubuntu-latest ships Java 17 (we use it). Installs wget + jq if missing.

command -v wget >/dev/null || apt-get install -y -qq wget
command -v jq >/dev/null || apt-get install -y -qq jq

echo "Java version:"; java -version 2>&1 | head -1

# --- Minecraft server jar ---
# Try PaperMC first via fill.papermc.io/v3 (new API). Fallback to vanilla via Mojang.
echo "[3/6] Downloading Minecraft server jar..."
SERVER_JAR="server/paper.jar"
VANILLA_JAR="server/vanilla.jar"
MC_VERSION=${MC_VERSION:-1.21.1}

# --- Try PaperMC via fill.papermc.io/v3 ---
echo "  Attempting PaperMC $MC_VERSION..."
JAR_URL=""
python3 - "$MC_VERSION" <<'PY' 2>/dev/null || JAR_URL=""
import json, sys, urllib.request
v = sys.argv[1]
# v3 API returns a bare array of build objects (no 'builds' wrapper)
bs = json.load(urllib.request.urlopen(f'https://fill.papermc.io/v3/projects/paper/versions/{v}/builds'))
stable = [b for b in bs if b.get('channel') == 'STABLE']
# pick the newest stable (or newest if no stable flag)
b = (stable or bs)[-1]
print(b['downloads']['server:default']['url'])
PY
if [ -n "$JAR_URL" ]; then
  echo "  PaperMC download URL obtained"
  curl -fsSL -o "$SERVER_JAR" "$JAR_URL" 2>/dev/null || {
    echo "  ⚠️  PaperMC download failed — falling back to vanilla"
    rm -f "$SERVER_JAR"
  }
fi

# --- Fallback: vanilla via Mojang piston-meta ---
if [ ! -s "$SERVER_JAR" ]; then
  echo "  ⬇️  Downloading vanilla $MC_VERSION (via Mojang)..."
  read -r VER JAR_URL < <(python3 - <<'PY'
import json, urllib.request
m = json.load(urllib.request.urlopen('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'))
rel = m['latest']['release']
vj = json.load(urllib.request.urlopen(next(x['url'] for x in m['versions'] if x['id'] == rel)))
print(rel, vj['downloads']['server']['url'])
PY
)
  curl -fsSL -o "$SERVER_JAR" "$JAR_URL" || {
    echo "  ❌ Vanilla download also failed!"
    exit 1
  }
  echo "  ✅ Vanilla $VER downloaded"
fi

echo "  Server jar: $(du -h "$SERVER_JAR" | cut -f1)"

# --- Server directory ---
mkdir -p server

cat > server/eula.txt <<'EULA'
eula=true
EULA

cat > server/server.properties <<'PROPS'
game-mode=survival
level-name=world
level-seed=12345
enable-command-block=false
pvp=true
allow-flight=false
level-type=minecraft:normal
difficulty=normal
hardcore=false
enable-jmx-monitoring=false
force-gamemode=false
snooper-enabled=true
max-players=20
online-mode=false
view-distance=8
simulation-distance=8
allow-nether=true
spawn-protection=0
PROPS

# --- bore.pub relay (raw TCP) ---
echo "Installing bore..."
wget -qO bore https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-linux-amd64
chmod +x bore

echo "=== Minecraft server ready to start ==="
echo "Run: ./start.sh"
echo "Connect to: bore.pub:30176 (after start)"