#!/bin/bash
set -euo pipefail

# --- GitHub Actions setup ---
# Install Temurin JRE 25 (Adoptium API)
echo "Installing Temurin JRE 25..."; curl -s https://api.adoptium.net/v3/binary/latest/25/lts/hotspot | jq -r '.installer.url' | wget -qO - | tar -xz --strip-components=1
export JAVA_HOME=$(pwd)

# --- PaperMC setup ---
# Use fill.papermc.io/v3 (v2 API is SUNSET)
PAPERMC_VERSION=$(curl -s https://papermc.io/api/v2/projects/paper/versions | jq -r '.versions[0]')
echo "Installing PaperMC $PAPERMC_VERSION...";
wget -qO paper.jar "https://papermc.io/api/v2/projects/paper/versions/$PAPERMC_VERSION/builds/$(curl -s "https://papermc.io/api/v2/projects/paper/versions/$PAPERMC_VERSION/builds" | jq -r '.builds[0].build")"

# --- Server files ---
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
view-distance=10
simulation-distance=10

# --- bore.pub relay (raw TCP) ---
# Install bore (ekzhang/bore v0.6.0)
echo "Installing bore...";
wget -qO bore https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-linux-amd64
chmod +x bore

# --- Startup script ---
cat > start.sh <<'START'
#!/bin/bash
set -euo pipefail

# --- Start PaperMC server ---
echo "Starting Minecraft server...";
java -Xmx2G -Xms1G -jar paper.jar nogui &
SERVER_PID=$!

# --- Start bore.pub relay ---
echo "Starting bore.pub relay...";
PORT=30175
bore local tcp://127.0.0.1:$PORT --to bore.pub:$PORT &> bore.log &
BORE_PID=$!

# --- Auto-save loop ---
echo "Starting auto-save loop (every 15 mins)...";
while kill -0 $SERVER_PID 2>/dev/null; do
  sleep 900
  echo "Auto-save triggered at $(date)";
  kill -USR1 $SERVER_PID
  sleep 10
  echo "World saved."
done

# --- Final save on shutdown ---
echo "Waiting for server to stop...";
wait $SERVER_PID
kill -USR1 $SERVER_PID 2>/dev/null || true
sleep 10
echo "Final save complete."

# --- Cleanup ---
echo "Shutting down...";
kill $BORE_PID 2>/dev/null || true
START

chmod +x start.sh

# --- Print connection address ---
echo "=== Minecraft server ready ==="
echo "Connect to: bore.pub:30175"
echo "World: server/world"
echo "Logs: server/logs/latest.log"
