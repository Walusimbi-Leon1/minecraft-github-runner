#!/usr/bin/env bash
# connect-mac.sh <trycloudflare-URL> — open the tunnel to your Colab Minecraft server
# Usage:   ./connect-mac.sh https://xxxx.trycloudflare.com
# Then in Minecraft: Multiplayer -> Add Server -> address:  localhost:25565
# Keep this terminal window open while you play.

set -euo pipefail
if [ $# -ne 1 ]; then
  echo "Usage: ./connect-mac.sh https://xxxx.trycloudflare.com"
  exit 1
fi
URL="$1"

ARCH=$(uname -m)
case "$ARCH" in
  arm64) BIN="cloudflared-darwin-arm64" ;;
  *)     BIN="cloudflared-darwin-amd64" ;;
esac

CF="$HOME/.cloudflared/cloudflared"
if [ ! -x "$CF" ]; then
  echo "Downloading cloudflared..."
  mkdir -p "$HOME/.cloudflared"
  curl -fsSL -o "$CF" "https://github.com/cloudflare/cloudflared/releases/latest/download/$BIN"
  chmod +x "$CF"
fi

echo "Keep this window open. In Minecraft, add server:  localhost:25565"
"$CF" access tcp --hostname "$URL" --url 127.0.0.1:25565
