#!/bin/bash
set -uo pipefail

# start.sh — launches the PaperMC server + bore.pub relay, prints the address,
# then returns (server keeps running in background). The workflow holds the
# runner for the duration and performs saves / final shutdown.

PORT=${MC_PORT:-25565}
RAM=${MC_RAM:-3G}

cd "$(dirname "$0")"

# --- Start PaperMC server in background ---
# The jar is downloaded into ./server/ by setup.sh
echo "Starting Minecraft server (port $PORT, ram $RAM)..."
nohup java -Xmx$RAM -Xms2G -jar server/paper.jar nogui > server/server.log 2>&1 &
echo $! > server.pid
SERVER_PID=$!

# Give the server a moment to bind
sleep 10
echo "Server PID: $SERVER_PID"

# --- Start bore.pub relay ---
echo "Starting bore.pub relay on port ${MC_BORE_PORT:-30176}..."
nohup bore local tcp://127.0.0.1:$PORT --to bore.pub:${MC_BORE_PORT:-30176} > bore.log 2>&1 &
echo $! > bore.pid
BORE_PID=$!

echo "=== Minecraft server ready ==="
echo "Connect to: bore.pub:${MC_BORE_PORT:-30176}"
echo "(Use 'Java Edition' or EagleCraft browser client)"
echo "Server running in background (PID $SERVER_PID)."
