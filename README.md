# ⛏️ minecraft-colab — Minecraft server on Google Colab

A private Minecraft (Java Edition) server that runs on a Google Colab machine.
Clone the repo, run **two commands**, and you get a **direct connection address**
you paste straight into Minecraft — no client software, no extra steps.
Exactly like the `colab-setup` pattern for OpenClaw.

```
bash setup.sh     # installs Java 25, Paper server, tunnel + version-compat plugins (one-time per session)
bash start.sh     # starts the server + public tunnel, prints the address to paste into Minecraft
```

## Quick start (on Colab)

1. Open a new notebook → Runtime → Change runtime type → **T4 GPU or CPU** (either works; CPU is fine, GPU is unused).
2. In a cell, clone with your GitHub access token (the repo is **private**):

   ```
   !git clone https://<YOUR-TOKEN>@github.com/Walusimbi-Leon1/minecraft-colab.git
   ```

3. Set up (2–3 min: Java ~50 MB + Paper ~60 MB + plugins ~15 MB):

   ```
   %cd minecraft-colab
   !bash setup.sh
   ```

4. Start the server and get your address:

   ```
   !bash start.sh
   ```

   Wait for `✅ Minecraft server is LIVE!` — it prints the address.

## Joining from your PC

**In Minecraft Java Edition:** Multiplayer → Add Server → Server Address:

```
bore.pub:43829        ← the exact address start.sh prints (port varies per run)
```

Then just click **Join**. That's it — no tunnel software, no batch files, nothing else to install.

## Version compatibility — every Minecraft version works

The server runs the latest PaperMC, plus **ViaVersion + ViaBackwards + ViaRewind**
plugins (installed automatically by `setup.sh`). Any Java Edition client from
**1.7.10 up to the latest** can join, regardless of what version you have installed.

> ⚠️ Bedrock Edition is not supported (this is a Java Edition server over TCP).

> 🛠️ If the server won't start because of a **corrupt world** (e.g. Colab was killed
> mid-save), you'll see `Overworld settings missing` in the log. Fix:
> `rm -rf server/world server/world_nether server/world_the_end` then `bash start.sh`
> (a fresh world generates). Save often with `./save-world.sh`.

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

## Backup tunnel (only if bore.pub is unreachable)

`start.sh` uses **bore** (bore.pub) for the direct address. If bore.pub is ever
down, start.sh automatically falls back to a **Cloudflare quick tunnel** and
prints its URL instead. That one needs cloudflared on your PC:

```
cloudflared access tcp --hostname xxxx.trycloudflare.com --url 127.0.0.1:25565
```

then join `localhost:25565` in Minecraft. (Install cloudflared from
cloudflare.com/cloudflare-one/connections/connect-networks/downloads/ — you'll
only need it in this rare fallback case.)

## Security notes

- The server runs in **offline mode** (`online-mode=false`) so any client can join through the tunnel. **Whitelist your players** to keep strangers out:
  ```
  ./mc.sh whitelist on
  ./mc.sh whitelist add YourName
  ./mc.sh whitelist add FriendName
  ```
- The address/port is random and changes every `start.sh` run — share it only with people you trust.
- Anyone who can read this private repo can run the server — don't share your GitHub token.

## How it works

1. `setup.sh` installs Temurin **JRE 25**, downloads the **PaperMC** server jar (latest stable; falls back to vanilla if the Paper API is down), accepts the EULA, pre-seeds `server.properties`, installs **bore** + **cloudflared**, and drops the **Via\*** plugins into `server/plugins/`.
2. `start.sh` launches the server inside a `screen` session named `mc`, waits until it's fully up (`Done`), then opens a **bore tunnel** — a free, account-less raw-TCP tunnel to `bore.pub`. The client connects to `bore.pub:<port>` **directly**; Minecraft speaks normal TCP, so no client software is needed.
3. If bore.pub is unreachable, start.sh falls back to a **Cloudflare quick tunnel** (`cloudflared tunnel --url tcp://localhost:25565`) and prints it as the backup option.

### Why bore instead of a trycloudflare URL in the Add Server box?

A trycloudflare quick tunnel carries raw TCP only through the `cloudflared`
client — Minecraft cannot connect to it directly (the edge speaks HTTP/WS to the
tunnel client, and Minecraft speaks plain TCP). bore.pub exposes a real
`host:port` TCP endpoint, which is exactly what Minecraft's Add Server field
accepts. It needs no account and no credentials in this repo.

### Why not a named tunnel on one of our Cloudflare accounts?

Named tunnels need a zone/domain to route a stable hostname — our accounts have
**no zones**. bore/quick tunnels need no credentials at all (nothing secret
lands in this repo). If you ever add a domain to Cloudflare, we can switch to a
stable named tunnel easily.

## Colab limitations (expected)

- The VM is **ephemeral**: everything (world, config) is wiped when the session ends / after ~12 h idle / 24 h max uptime. The server files live in the repo dir, so re-running `setup.sh` is quick — but **save your world** (`./save-world.sh`) and copy the tarball somewhere safe (Drive/GitHub) before closing.
- The address changes every start (random bore port). A stable address needs a VPS relay or a Cloudflare domain (see above).
- Java Edition only (TCP). Bedrock/UDP is not supported by this setup.

## Files

```
setup.sh               # one-time install: Java + Paper + bore + Via* plugins + cloudflared + config
start.sh               # start server + direct tunnel, print the Minecraft address
stop.sh                # graceful stop
mc.sh                  # server console helper (commands / log)
save-world.sh          # world backup tarball
server/                # created at runtime (gitignored): jar, world, plugins, logs, config
```
