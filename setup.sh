#!/bin/bash
set -euo pipefail

# --- GitHub Actions setup ---
# ubuntu-latest ships Java 17 (we use it). Installs wget + jq if missing.

command -v wget >/dev/null || apt-get install -y -qq wget
command -v jq >/dev/null || apt-get install -y -qq jq

echo "Java version:"; java -version 2>&1 | head -1

MC_VERSION=${MC_VERSION:-1.21.1}

# --- PaperMC setup via fill.papermc.io/v3 (v2 API is SUNSET) ---
echo "[3/6] Minecraft server jar (Paper $MC_VERSION)..."
JAR_URL=""
if [ -f paper.jar ]; then
  echo "  ✅ Server jar already present ($(du -h paper.jar | cut -f1))"
else
  echo "  ⬇️  Downloading Paper $MC_VERSION (~40-60 MB)..."
  JAR_URL=$(python3 - "$MC_VERSION" <<'PY'
import json, sys, urllib.request
v = sys.argv[1]
bs = json.load(urllib.request.urlopen(f'https://fill.papermc.io/v3/projects/paper/versions/{v}/builds'))
stable = [b for b in bs if b.get('channel') == 'STABLE']
b = (stable or bs)[0]
print(b['downloads']['server:default']['url'])
PY
) || true
  if [ -n "$JAR_URL" ]; then
    curl -fsSL -o paper.jar "$JAR_URL" || JAR_URL=""
  fi
  if [ -z "$JAR_URL" ] || [ ! -s paper.jar ]; then
    echo "  ⚠️  Paper download failed — falling back to vanilla..."
    read -r MC_VERSION JAR_URL < <(python3 - <<'PY'
import json, urllib.request
m = json.load(urllib.request.urlopen('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'))
rel = m['latest']['release']
vj = json.load(urllib.request.urlopen(next(x['url'] for x in m['versions'] if x['id'] == rel)))
print(rel, vj['downloads']['server']['url'])
PY
)
    curl -fsSL -o paper.jar "$JAR_URL"
    echo "  ✅ Vanilla $MC_VERSION downloaded"
  fi
fi

# --- Server directory + files ---
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
