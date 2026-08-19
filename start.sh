#!/bin/bash
set -uo pipefail

# start.sh — launches the PaperMC server inside a `screen` session (name: mc)
# plus the bore.pub TCP relay, prints the public address, then returns. The
# workflow holds the runner for the duration and calls save-world.sh (which
# sends save-all into the screen session) and finally stops the server.
#
# IMPORTANT: PaperMC resolves eula.txt / server.properties / world / logs
# relative to its WORKING DIRECTORY. We therefore run java from inside the
# `server/` directory so those files (written there by setup.sh) are found.

PORT=${MC_PORT:-25565}
RAM=${MC_RAM:-3G}
BORE_PORT=${MC_BORE_PORT:-30176}

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$REPO_ROOT/server"
cd "$SERVER_DIR"

# --- Start PaperMC server in a screen session (cwd = server/) ---
# -L -Logfile captures stdout/stderr to $SERVER_DIR/server.log for diagnostics.
echo "Starting Minecraft server (port $PORT, ram $RAM)..."
screen -dmS mc -L -Logfile "$SERVER_DIR/server.log" java -Xmx$RAM -Xms2G -jar paper.jar nogui
echo "Server screen 'mc' started."

# Give the server a moment to bind
sleep 10
echo "Server status:"
screen -ls mc || echo "  (no screen session — server may have crashed; see server/server.log)"

# --- Start bore.pub relay (from repo root so ./bore resolves) ---
echo "Starting bore.pub relay on port $BORE_PORT..."
nohup "$REPO_ROOT/bore" local tcp://127.0.0.1:$PORT --to bore.pub:$BORE_PORT > "$REPO_ROOT/bore.log" 2>&1 &
echo $! > "$REPO_ROOT/bore.pid"
BORE_PID=$!

# Read the assigned public address from bore.log
sleep 3
echo "=== Minecraft server ready ==="
grep -oE 'bore\.pub:[0-9]+' "$REPO_ROOT/bore.log" | head -1 | sed 's/^/Connect to: /' || echo "Connect to: bore.pub:$BORE_PORT"
echo "(Use 'Java Edition' or EagleCraft browser client)"
echo "Server is running in screen session 'mc'."
