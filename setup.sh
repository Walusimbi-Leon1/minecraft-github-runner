#!/bin/bash
set -euo pipefail

# --- GitHub Actions setup ---
# ubuntu-latest = Ubuntu 22.04/24.04 with Java 17 already.
# We install Java 25 (newer) + wget + jq if missing.

if ! command -v java &>/dev/null; then
  echo "Installing Java 25 (Temurin)..."
  curl -s https://api.adoptium.net/v3/binary/latest/25/ga/linux/hotspot.tar.gz | tar -xz -C /tmp/
  export JAVA_HOME=/tmp/jdk-25*
  ln -sf /tmp/jdk-25*/bin/java /usr/local/bin/java
fi
echo "Java version:"; java -version 2>&1 | head -1

# Install wget and jq if missing
command -v wget >/dev/null || apt-get install -y -qq wget
command -v jq >/dev/null || apt-get install -y -qq jq

# --- PaperMC setup ---
# Use papermc.io API v2 (fill.papermc.io/v3 format)
PAPERMC_VERSION=$(curl -s https://api.papermc.io/v2/projects/paper | jq -r '.versions[-1]')
PAPERMC_BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$PAPERMC_VERSION/builds" | jq -r '.builds[-1].build')
echo "Installing PaperMC paper:$PAPERMC_VERSION-$PAPERMC_BUILD..."
wget -qO paper.jar "https://api.papermc.io/v2/projects/paper/versions/$PAPERMC_VERSION/builds/$PAPERMC_BUILD/downloads/paper-$PAPERMC_VERSION-$PAPERMC_BUILD.jar"
echo "PaperMC jar: $(du -h paper.jar | cut -f1)"

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

# --- Print connection address ---
echo "=== Minecraft server ready to start ==="
echo "Run: ./start.sh"
echo "Connect to: bore.pub:30176 (after start)"
