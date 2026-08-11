# ⛏️ minecraft-colab — Minecraft server on Google Colab

A private Minecraft (Java Edition) server that runs on a Google Colab machine.
Clone the repo, run **two commands**, and you get a public connection address —
exactly like the `colab-setup` pattern for OpenClaw.

```
bash setup.sh     # installs Java 25, the Paper server, cloudflared (one-time per session)
bash start.sh     # starts the server + public Cloudflare tunnel, prints the connection URL
```

## Quick start (on Colab)

1. Open a new notebook → Runtime → Change runtime type → **T4 GPU or CPU** (either works; CPU is fine, GPU is unused).
2. In a cell, clone with your GitHub access token (the repo is **private**):

   ```
   !git clone https://<YOUR-TOKEN>@github.com/Walusimbi-Leon1/minecraft-colab.git
   ```

3. Set up (2–3 min: downloads Java ~50 MB + Paper ~60 MB + cloudflared):

   ```
   %cd minecraft-colab
   !bash setup.sh
   ```

4. Start the server and get your connection URL:

   ```
   !bash start.sh
   ```

   Wait for `✅ Minecraft server is LIVE!` — it prints the tunnel URL.

## Joining from your PC

1. **Open the tunnel** (one command, using the URL printed by `start.sh`):

   - **Windows** (double-click or in cmd):
     ```
     connect-windows.bat https://xxxx.trycloudflare.com
     ```
   - **Mac / Linux**:
     ```
     ./connect-mac.sh https://xxxx.trycloudflare.com
     ```
   - **Manual** (any OS): install [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) and run:
     ```
     cloudflared access tcp --hostname xxxx.trycloudflare.com --url 127.0.0.1:25565
     ```

2. **In Minecraft Java Edition**: Multiplayer → Add Server → address:
   ```
   localhost:25565
   ```

> ⚠️ Your Minecraft client version must **match the server version** (default: latest Paper, e.g. `26.2`).
> Friends can join too — they just need the same one command + URL.

## Options (env vars)

| Var | Default | What it does |
|---|---|---|
| `MC_VERSION` | latest stable | Paper version, e.g. `26.2`, `1.21.4` (set before `setup.sh`) |
| `MC_RAM` | `2048M` | Server heap size (Colab has ~12 GB — `4G` is safe) |
| `MC_PORT` | `25565` | Server port (only change if you know what you're doing) |

Example: `MC_VERSION=1.21.4 MC_RAM=4G bash setup.sh`

## Useful commands

| Command | What it does |
|---|---|
| `./mc.sh <command>` | Send a server console command, e.g. `./mc.sh say hello` |
| `./mc.sh log` | Follow the server log (Ctrl+C to exit) |
| `./mc.sh whitelist add <name>` | Allow a specific player (recommended!) |
| `./save-world.sh` | Back up the world to a tarball (download via Colab Files panel) |
| `./stop.sh` | Gracefully stop server + tunnel |

## Security notes

- The server runs in **offline mode** (`online-mode=false`) so any client can join through the tunnel. **Whitelist your players** to keep strangers out:
  ```
  ./mc.sh whitelist on
  ./mc.sh whitelist add YourName
  ./mc.sh whitelist add FriendName
  ```
- The tunnel URL is random and changes every `start.sh` run — share it only with people you trust.
- Anyone who can read this private repo can run the server — don't share your GitHub token.

## How it works

1. `setup.sh` installs Temurin **JRE 25**, downloads the **PaperMC** server jar (latest stable; falls back to vanilla if the Paper API is down), accepts the EULA, pre-seeds `server.properties`, and installs **cloudflared**.
2. `start.sh` launches the server inside a `screen` session named `mc`, waits until it's fully up (`Done`), then starts a **Cloudflare quick tunnel** (`cloudflared tunnel --url tcp://localhost:25565`).
3. The printed `https://xxxx.trycloudflare.com` is a free public TCP tunnel through Cloudflare's edge — no account, no domain, no firewall config. Your PC connects to it with `cloudflared access tcp`, and Minecraft joins at `localhost:25565`.

### Why not a named tunnel on one of our Cloudflare accounts?

Named tunnels need a zone/domain to route a stable hostname — our accounts have **no zones**. Quick tunnels need no credentials at all (nothing secret lands in this repo), so they're the better fit here. If you ever add a domain to Cloudflare, we can switch to a stable named tunnel easily.

## Colab limitations (expected)

- The VM is **ephemeral**: everything (world, config) is wiped when the session ends / after ~12 h idle / 24 h max uptime. The server files live in the repo dir, so re-running `setup.sh` is quick — but **save your world** (`./save-world.sh`) and copy the tarball somewhere safe (Drive/GitHub) before closing.
- The tunnel URL changes every start. A stable address needs a VPS relay or a Cloudflare domain (see above).
- Java Edition only (TCP). Bedrock/UDP is not supported by this setup.

## Files

```
setup.sh               # one-time install: Java + Paper + cloudflared + config
start.sh               # start server + tunnel, print connection details
stop.sh                # graceful stop
mc.sh                  # server console helper (commands / log)
save-world.sh          # world backup tarball
connect-windows.bat    # PC-side tunnel opener (Windows)
connect-mac.sh         # PC-side tunnel opener (Mac/Linux)
server/                # created at runtime (gitignored): jar, world, logs, config
```
