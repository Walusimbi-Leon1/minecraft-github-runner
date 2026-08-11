#!/usr/bin/env bash
# save-world.sh — back up the world(s) into a tarball you can download
# from the Colab Files panel (or push to GitHub/Drive) before the session dies.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/server"

if screen -ls mc >/dev/null 2>&1; then
  echo "💾 save-all..."
  screen -S mc -X stuff 'save-all'$'\r'
  sleep 3
fi

TS=$(date +%Y%m%d-%H%M%S)
OUT="$SCRIPT_DIR/world-backup-$TS.tar.gz"
if [ -d world_nether ] || [ -d world_the_end ]; then
  tar czf "$OUT" world world_nether world_the_end 2>/dev/null || tar czf "$OUT" world
else
  tar czf "$OUT" world 2>/dev/null || { echo "❌ No world found yet."; exit 1; }
fi
echo "✅ Backup: $(ls -lh "$OUT" | awk '{print $5, $9}')"
echo "   Download it: Colab Files panel → $(basename "$OUT")"
