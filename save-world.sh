#!/usr/bin/env bash
set -euo pipefail

# save-world.sh — Save the Minecraft world to GitHub (release asset), so it
# survives Colab's ephemeral VMs. start.sh automatically restores it next run.
# Usage:    bash save-world.sh
# Works whether or not the server is currently running.
#
# Where it goes:
#   A GitHub Release named "world-save" in THIS repository (the one you cloned
#   from), as an asset "world.tar.gz". Re-running replaces the asset.
#
# Auth (picks the first that works):
#   1. $GH_TOKEN / $GITHUB_TOKEN env var
#   2. A file named .token in this repo folder
#   3. The token embedded in the clone URL (https://TOKEN@github.com/...)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"

echo "=================================================="
echo "  💾 LA5 Colab World Save"
echo "  $(date)"
echo "=================================================="

# ── Resolve GitHub token ──────────────────────────────
TOKEN=""
if [ -n "${GH_TOKEN:-}" ]; then TOKEN="$GH_TOKEN"; fi
if [ -z "$TOKEN" ] && [ -n "${GITHUB_TOKEN:-}" ]; then TOKEN="$GITHUB_TOKEN"; fi
if [ -z "$TOKEN" ] && [ -n "${GH_PAT:-}" ]; then TOKEN="$GH_PAT"; fi
if [ -z "$TOKEN" ] && [ -f "$SCRIPT_DIR/.token" ]; then TOKEN="$(tr -d ' \r\n' < "$SCRIPT_DIR/.token")"; fi
if [ -z "$TOKEN" ]; then
  REMOTE=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)
  case "$REMOTE" in
    https://*@github.com/*) TOKEN="${REMOTE#https://}"; TOKEN="${TOKEN%%@*}" ;;
  esac
fi
if [ -z "$TOKEN" ]; then
  echo "❌ No GitHub token found. Set GH_TOKEN, add a .token file, or clone with"
  echo "   https://<token>@github.com/...  (see README)"
  exit 1
fi

# ── Resolve repo (owner/name) ─────────────────────────
REPO=""
REMOTE=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)
case "$REMOTE" in
  https://*github.com/*) REPO="${REMOTE##*github.com/}" ;;
  git@github.com:*) REPO="${REMOTE##git@github.com:}" ;;
esac
REPO="${REPO%.git}"
if [ -z "$REPO" ]; then
  echo "❌ Could not determine the GitHub repo from: $REMOTE"
  exit 1
fi
echo "  Repo: $REPO"

# ── Flush the server's world to disk ──────────────────
if screen -ls mc >/dev/null 2>&1; then
  echo "  💤 Asking server to save-all..."
  screen -S mc -X stuff 'save-all'$'\r'
  sleep 4
fi

# ── Tar the world ─────────────────────────────────────
TARBALL="/tmp/world-backup.tar.gz"
WORLDS=()
[ -d "$SERVER_DIR/world" ] && WORLDS+=("world")
[ -d "$SERVER_DIR/world_nether" ] && WORLDS+=("world_nether")
[ -d "$SERVER_DIR/world_the_end" ] && WORLDS+=("world_the_end")
if [ ${#WORLDS[@]} -eq 0 ]; then
  echo "❌ No world found in $SERVER_DIR — nothing to save."
  exit 1
fi
rm -f "$TARBALL"
# exclude session.lock (the running server holds it) — it would only cause
# "session lock already held" warnings on restore.
tar czf "$TARBALL" -C "$SERVER_DIR" \
  --exclude='*/session.lock' "${WORLDS[@]}"
SIZE=$(du -h "$TARBALL" | cut -f1)
echo "  📦 World packed: ${WORLDS[*]} → $TARBALL ($SIZE)"

# ── Upload to GitHub release "world-save" ─────────────
API="https://api.github.com/repos/$REPO"
AUTH="Authorization: Bearer $TOKEN"
ACCEPT="Accept: application/vnd.github+json"

echo "  ☁️  Uploading to GitHub ($REPO, release 'world-save')..."
# Get or create the release
RELEASE=$(curl -fsS -H "$AUTH" -H "$ACCEPT" "$API/releases/tags/world-save" 2>/dev/null || true)
if [ -z "$RELEASE" ]; then
  echo "  ...creating release 'world-save'"
  RELEASE=$(curl -fsS -X POST -H "$AUTH" -H "$ACCEPT" "$API/releases" \
    -d '{"tag_name":"world-save","name":"World Save","body":"Latest world backup (auto-uploaded by save-world.sh)","draft":false,"prerelease":false}')
fi
RELEASE_ID=$(printf '%s' "$RELEASE" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)
if [ -z "$RELEASE_ID" ]; then
  echo "❌ Could not create/get the world-save release. Check the token has repo access."
  exit 1
fi

# Delete the previous asset if present
OLD_ID=$(printf '%s' "$RELEASE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('assets',[]):
    if a['name']=='world.tar.gz':
        print(a['id']); break
" 2>/dev/null || true)
if [ -n "$OLD_ID" ]; then
  echo "  ...replacing previous world.tar.gz (asset $OLD_ID)"
  curl -fsS -X DELETE -H "$AUTH" -H "$ACCEPT" "$API/releases/assets/$OLD_ID" >/dev/null || true
fi

# Upload the new asset (uploads.github.com — the api.github.com path 404s)
UPLOAD=$(curl -fsSL -X POST -H "$AUTH" -H "Content-Type: application/gzip" \
  --data-binary @"$TARBALL" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=world.tar.gz" 2>/dev/null || true)
UP_SIZE=$(printf '%s' "$UPLOAD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('size','?'))" 2>/dev/null || echo '?')
if [ -n "$UPLOAD" ]; then
  echo ""
  echo "  ✅ World saved to GitHub!"
  echo "     https://github.com/$REPO/releases/tag/world-save  ($UP_SIZE bytes)"
  echo ""
  echo "  Next time you run start.sh, this world will be loaded automatically."
else
  echo "  ⚠️  Upload failed — check the token/network and retry: bash save-world.sh"
  exit 1
fi
