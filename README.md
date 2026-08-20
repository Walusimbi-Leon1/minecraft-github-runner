# ⛏️ LA5 Minecraft Server — GitHub Runner Edition

A Minecraft Java server that runs on a **GitHub Actions** runner and supports
**every client**: normal Minecraft **Java** clients (1.7.10 → latest, via
ViaVersion) and **Eaglercraft browser** clients (via cloudflared wss:// tunnel).

The server jar, plugins, and config are installed by `setup.sh` and the world
can be **saved to GitHub** and **auto-restored** on the next run, so progress
survives ephemeral runners.

---

## How it works (workflow)

The [`.github/workflows/run.yml`](./.github/workflows/run.yml) workflow:

1. Checks out the repo
2. Sets up Java 21 (Temurin)
3. Runs `./setup.sh` — installs the server + plugins + tunnels
4. Runs `./start.sh` — starts the server, waits for "Done", opens tunnels,
   prints the real `bore.pub:PORT` address
5. Holds the runner for the specified duration (default 3 hours)
6. Auto-saves the world every 15 min via `save-world.sh` + GitHub Releases
7. Saves the final world and shuts down gracefully

### Manual usage (SSH into any Linux machine)

```bash
bash setup.sh
bash start.sh
```

`start.sh` prints **both** tunnel addresses:

```
  🖥️  JAVA EDITION (normal Minecraft client):
      Server Address:  bore.pub:30175

  🌐 EAGLERCRAFT (browser client):
      Server Address:  wss://ram-hardly-oct-baking.trycloudflare.com
```

- **Java client** → Multiplayer → Add Server → paste the `bore.pub:PORT` address → Join.
- **Eaglercraft** → Multiplayer → Add Server → paste the `wss://…trycloudflare.com` address → Join.

---

## 💾 Saving & restoring your world

### Save

```bash
./save-world.sh
```

This packs your world and uploads it to a GitHub Release called
**`world-save`** in this repository (asset `world.tar.gz`). Re-running
replaces the previous save. Requires the GitHub token (`GH_TOKEN`, `GH_PAT`,
a `.token` file, or the token in your clone URL).

Optional auto-save: `AUTOSAVE=15 bash start.sh` saves every 15 minutes
(default is on at 15 min; `AUTOSAVE=0` disables).

### Restore

On the next run, `start.sh` checks for a local `server/world` folder first;
if absent, it looks for the `world-save` GitHub Release and restores it
automatically. No world saved yet → a fresh new world is generated.

---

## Commands

| Command | What it does |
|---|---|
| `bash setup.sh` | Install everything (Java, Paper, plugins, tunnels). Idempotent. |
| `bash start.sh` | Start server + tunnels, restore world, print addresses. |
| `./save-world.sh` | Upload world to GitHub release `world-save`. |
| `./mc.sh <cmd>` | Send a server command, e.g. `./mc.sh say hello`, `./mc.sh whitelist add <name>` |
| `./mc.sh log` / `./mc.sh tail` | Follow / tail the server log. |
| `./stop.sh` | Stop server + tunnels. |

---

## How it works

| Piece | What / why |
|---|---|
| **Paper 1.21.1** (default) | Modern Paper server. Set `MC_VERSION=26.2` for latest. |
| **Java 21 (Temurin)** | Required for modern Paper (1.21.1+). Installed by setup.sh. |
| **ViaVersion / ViaBackwards / ViaRewind** | Any normal Java client 1.7.10 → latest can join. |
| **bore.pub tunnel** | Free, account-less raw-TCP tunnel → `bore.pub:PORT` goes straight into Minecraft's Add Server. |
| **cloudflared tunnel** | WebSocket (wss://) tunnel for Eaglercraft browser clients. |
| **save-world.sh + start.sh** | World ⇄ GitHub Release (`world-save`), so runner resets don't lose progress. |

---

## Notes & gotchas

- **Offline mode** is on (needed for tunnels). Keep strangers out:
  `./mc.sh whitelist on` then `./mc.sh whitelist add <your-username>`.
- The bore.pub port is random per run (fine — the address is printed every
  start; your client just needs re-adding if the port changed).
- The trycloudflare URL also changes per run.

## Repo layout

```
setup.sh            one-time install (Java, Paper, plugins, tunnels)
start.sh            start server + tunnels, restore world, print addresses
save-world.sh       upload world to GitHub release "world-save"
mc.sh               server console helper
stop.sh             stop server + tunnels
.github/workflows/run.yml   the GitHub Actions workflow
server/             runtime (created by setup.sh: jar, plugins, world, logs)
```
