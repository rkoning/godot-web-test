# Logistics Roguelike — web build

Godot 4 project that exports to the web and publishes to GitHub Pages whenever a
release is published, plus a Cloudflare Worker that hosts the shared state. See
[`one-pager.md`](one-pager.md) for the game design.

Right now the game is a smoke test for the whole pipeline: one button, one
counter shared by everyone connected, and a random name per player.

## Layout

```
game/                          Godot project root (project.godot lives here)
  export_presets.cfg           the "Web" preset — tracked on purpose, CI needs it
  scripts/net_client.gd        WebSocket client: socket lifecycle → signals
  scripts/net_config.gd        which server to talk to
server/                        Cloudflare Worker: one Durable Object = one room
.github/actions/godot-export/  composite action: install Godot, import, export, verify
.github/workflows/ci.yml       export + Worker config check on every push/PR
.github/workflows/release.yml  export → Pages, and deploy the Worker
```

## How the multiplayer works

GitHub Pages is static and a Godot web export can never host, so the
authoritative state lives in a Cloudflare Worker. A single Durable Object
(`idFromName("global")` — one global room) holds the counter in its storage and
every connected socket in its hibernation list. The Godot client speaks plain
JSON over one WebSocket; there is no Godot high-level multiplayer involved.

| Direction | Message | Meaning |
| --- | --- | --- |
| server → client | `welcome` | your id + random name, current counter, roster |
| server → client | `counter` | new value, and who clicked |
| server → client | `roster` | somebody joined or left |
| client → server | `click` | increment, please |
| client → server | `ping` | keepalive, auto-answered without waking the object |

The counter is persisted in Durable Object storage, so it survives the object
being evicted and restarts at the value it had. Names are assigned server-side
from two word lists and de-duplicated against the current room.

The client reconnects on its own with exponential backoff (1s → 15s), and the
button stays disabled until the server has sent `welcome`, so a click can never
be dropped into a dead socket.

## One-time setup

1. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
   Without this the `deploy` job fails on the Pages API.
2. **Deploy the Worker once** (`cd server && npx wrangler deploy`) to find out
   its URL, then set repository **variable** `SERVER_URL` to
   `wss://<worker>.<subdomain>.workers.dev/ws`. The release workflow rewrites
   `net_config.gd` with it before exporting; without it the build ships the
   localhost endpoint and never connects.
3. **Secrets** `CLOUDFLARE_API_TOKEN` (Edit Workers template) and
   `CLOUDFLARE_ACCOUNT_ID`, so releases can redeploy the Worker.

Pages itself needs no secrets — `deploy-pages` uses the workflow's OIDC identity
and the release upload uses the built-in `GITHUB_TOKEN`.

## Publishing

Cut a GitHub release (tag + publish). That fires `release.yml`, which:

1. exports the `Web` preset headlessly with a pinned Godot version,
2. verifies the export actually produced `index.{html,js,wasm,pck}` — Godot can
   exit 0 having written a blank page,
3. deploys `build/` to Pages,
4. attaches `web-<tag>.zip` to the release, so every release is downloadable and
   reproducible independent of Pages.

`workflow_dispatch` runs the same thing manually.

## Threads are off, deliberately

Godot's threaded web export requires the `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy` headers. **GitHub Pages cannot set response
headers**, so the preset sets `variant/thread_support=false` and the build runs
single-threaded. For a turn-based strategy game that costs nothing.

If you ever need threads, the options are: ship `coi-serviceworker.js` to
synthesize the headers, or move hosting to something that can set them
(itch.io, Cloudflare Pages, Netlify).

## Upgrading Godot

Bump `GODOT_VERSION` / `GODOT_RELEASE` in both workflows. The action downloads
the matching editor and export templates from `godotengine/godot-builds` and
caches them by version, so the first run after a bump is slower.

Keep the version in `game/project.godot`'s `config/features` in sync.

## Running it locally

Two terminals. The client's default endpoint is already the wrangler dev one, so
no configuration is needed.

```sh
# 1. server
cd server && npm install && npm run dev      # ws://127.0.0.1:8787/ws

# 2. client
cd game
godot --headless --import
godot --headless --export-release "Web" ../build/index.html
cd ../build && python3 -m http.server 8000
```

Open `http://127.0.0.1:8000` in two tabs and they share a counter.

A deployed build can be pointed at another server without rebuilding:
`https://…/?server=ws://127.0.0.1:8787/ws`.
