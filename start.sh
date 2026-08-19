#!/bin/bash
set -uo pipefail

# start.sh — launches the PaperMC server inside a `screen` session (name: mc)
# plus the bore.pub TCP relay, prints the public address, then returns. The
# workflow holds the runner for the duration and calls save-world.sh (which
# sends save-all into the screen session) and finally stops the server.

PORT=${MC_PORT:-25565}
RAM=${MC_RAM:-3G}
BORE_PORT=${MC_BORE_PORT:-30176}

cd "$(dirname "$0")"

# --- Start PaperMC server in a screen session ---
# The jar is downloaded into ./server/ by setup.sh
echo "Starting Minecraft server (port $PORT, ram $RAM)..."
screen -dmS mc java -Xmx$RAM -Xms2G -jar server/paper.jar nogui
echo "Server screen 'mc' started."

# Give the server a moment to bind
sleep 10
echo "Server status:"
screen -ls mc || echo "  (no screen session — server may have crashed; see server/server.log)"

# --- Start bore.pub relay ---
echo "Starting bore.pub relay on port $BORE_PORT..."
nohup ./bore local tcp://127.0.0.1:$PORT --to bore.pub:$BORE_PORT > bore.log 2>&1 &
echo $! > bore.pid
BORE_PID=$!

# Read the assigned public address from bore.log (it prints a line like:
# "bore.pub:30176 (...)" or "listening on ... bore.pub:NNNNN")
sleep 3
echo "=== Minecraft server ready ==="
grep -oE 'bore\.pub:[0-9]+' bore.log | head -1 | sed 's/^/Connect to: /' || echo "Connect to: bore.pub:$BORE_PORT"
echo "(Use 'Java Edition' or EagleCraft browser client)"
echo "Server is running in screen session 'mc' (PID $(pgrep -f 'server/paper.jar' | head -1))."
