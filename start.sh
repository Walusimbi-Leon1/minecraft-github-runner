#!/bin/bash
set -euo pipefail

# start.sh — GitHub Actions edition (no screen)
# Starts the PaperMC server, relays via bore.pub, and provides save-loop hooks.

PORT=${MC_PORT:-25565}
RAM=${MC_RAM:-3G}

cd "$(dirname "$0")"

# --- restore last saved world if present ---
RESTORE="/tmp/world-restore.tar.gz"
if [ -f "$RESTORE" ]; then
  echo "⚠️  Restoring previous world save..."
  tar xzf "$RESTORE" -C server/ || echo "⚠️  Restore failed — starting fresh"
fi

# --- Start PaperMC server in background ---
echo "Starting Minecraft server (port $PORT, ram $RAM)..."
java -Xmx$RAM -Xms2G -jar paper.jar nogui &
echo $! > server.pid
SERVER_PID=$!

# Give the server a moment to bind
sleep 2
echo "Server PID: $SERVER_PID"

# --- Start bore.pub relay ---
echo "Starting bore.pub relay on port ${MC_BORE_PORT:-30176}..."
bore local tcp://127.0.0.1:$PORT --to bore.pub:${MC_BORE_PORT:-30176} &> bore.log &
echo $! > bore.pid
BORE_PID=$!

echo "=== Minecraft server ready ==="
echo "Connect to: bore.pub:${MC_BORE_PORT:-30176}"
echo "(Use 'Java Edition' or EagleCraft browser client)"

# --- Wait / keep alive until killed ---
wait $SERVER_PID || true
