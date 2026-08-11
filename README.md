# ⛏️ LA5 Minecraft Server — Google Colab Edition

A Minecraft Java server that runs on a free Google Colab machine and supports
**every client**: normal Minecraft **Java** clients (1.7.10 → latest, via
ViaVersion) and **Eaglercraft browser** clients (1.5.2 / 1.8 / 1.12.2, via
EaglerXServer) — including the offline WASM Eaglercraft HTML file.

Colab VMs are ephemeral (wiped when closed), so the world can be **saved to
GitHub** and **auto-restored** on the next run.

---

## Quick start (fresh Colab)

Open a Google Colab notebook → Runtime → **Run all** (or a terminal cell) and run:

```bash
# 1. Clone this repo (use your GitHub token in the URL so save/restore works)
git clone https://<YOUR_GITHUB_TOKEN>@github.com/Walusimbi-Leon1/minecraft-colab.git
cd minecraft-colab

# 2. Install everything (Java, Paper 1.12.2, plugins, tunnels) — ~1 min
bash setup.sh

# 3. Start the server + tunnels
bash start.sh
```

`start.sh` prints **both** addresses:

```
  🖥️  JAVA EDITION (normal Minecraft client):
      Server Address:  bore.pub:30175

  🌐 EAGLERCRAFT (browser client, e.g. the offline HTML):
      Server Address:  wss://ram-hardly-oct-baking.trycloudflare.com
```

- **Java client** → Multiplayer → Add Server → paste the `bore.pub:PORT` address → Join.
- **Eaglercraft** (the WASM offline HTML, or any Eaglercraft client) → Multiplayer →
  Add Server → paste the `wss://…trycloudflare.com` address → Join.

> Browsers cannot open raw TCP connections, which is why Eaglercraft gets its
> own `wss://` WebSocket tunnel (cloudflared) while Java clients use the
> direct TCP tunnel (bore.pub). Both run automatically.

---

## 💾 Saving & restoring your world (survives Colab resets)

### Save

```bash
./save-world.sh
```

This packs your world and uploads it to a GitHub Release called
**`world-save`** in this repository (asset `world.tar.gz`). Re-running
replaces the previous save. Requires the GitHub token (env `GH_TOKEN`, a
`.token` file, or the token in your clone URL).

Optional auto-save: `AUTOSAVE=15 bash start.sh` saves every 15 minutes
(default is on at 15 min; `AUTOSAVE=0` disables).

### Restore

On the next fresh Colab session:

```bash
bash setup.sh     # installs everything again (Colab wiped it)
bash start.sh     # detects the saved world on GitHub → downloads & loads it
```

`start.sh` checks for a local `server/world` folder first; if absent, it
looks for the `world-save` GitHub Release and restores it automatically.
No world saved yet → a fresh new world is generated.

---

## Commands

| Command | What it does |
|---|---|
| `bash setup.sh` | Install everything (Java, Paper, plugins, tunnels). Idempotent. |
| `bash start.sh` | Start server + both tunnels, print addresses, restore world. |
| `./save-world.sh` | Upload world to GitHub release `world-save`. |
| `./mc.sh <cmd>` | Send a server command, e.g. `./mc.sh say hello`, `./mc.sh whitelist add <name>` |
| `./mc.sh log` / `./mc.sh tail` | Follow / tail the server log. |
| `./stop.sh` | Stop server + tunnels. |

---

## How it works

| Piece | What / why |
|---|---|
| **Paper 1.12.2** (default) | Eaglercraft plugins require old Bukkit APIs — 1.12.2 is the newest version they support. |
| **Java 8 + Java 17 (Temurin)** | Paper 1.12.2's paperclip can only *patch* on Java 8 (done once at setup); the server then runs on Java 17, which EaglerXServer and Via* 5.x require. |
| **EaglerXServer + EaglerXRewind** | Speaks the Eaglercraft protocol on the server side; the wss:// tunnel reaches it. |
| **ViaVersion / ViaBackwards / ViaRewind** | Any normal Java client 1.7.10 → latest can join the 1.12.2 server. |
| **bore.pub tunnel** | Free, account-less raw-TCP tunnel → `bore.pub:PORT` goes straight into Minecraft's Add Server. |
| **cloudflared tunnel** | WebSocket (wss://) tunnel for Eaglercraft browser clients. |
| **save-world.sh + start.sh** | World ⇄ GitHub Release (`world-save`), so Colab resets don't lose progress. |

### Switching to a modern server (no Eaglercraft)

Set `MC_VERSION=26.2 bash setup.sh` to run the latest Paper (Java 25,
Eagler plugins skipped automatically). Java clients still work through
Via*; Eaglercraft clients won't (they need the 1.12.2 stack).

---

## Notes & gotchas

- **Offline mode** is on (needed for tunnels). Keep strangers out:
  `./mc.sh whitelist on` then `./mc.sh whitelist add <your-username>`.
- Colab disconnects kill the VM after ~90 min idle — the world is safe
  once saved (`./save-world.sh` or autosave).
- World format is tied to the server version: a 26.2 world can't be loaded
  by the 1.12.2 stack and vice versa. Save/restore assumes a consistent
  `MC_VERSION`.
- bore.pub ports are random per run (fine — the address is printed every
  start; your client just needs re-adding if the port changed).
- The trycloudflare URL also changes per run.

## Repo layout

```
setup.sh        one-time install (Java, Paper, plugins, tunnels)
start.sh        start server + tunnels, restore world, print addresses
save-world.sh   upload world to GitHub release "world-save"
stop.sh         stop server + tunnels
mc.sh           server console helper
server/         runtime (created by setup.sh: jar, plugins, world, logs)
```
