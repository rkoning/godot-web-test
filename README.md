# Logistics Roguelike — web build

Godot 4 project that exports to the web and publishes to GitHub Pages whenever a
release is published, plus a Cloudflare Worker that hosts the shared state. See
[`one-pager.md`](one-pager.md) for the game design.

The playable piece is the **combat prototype**: one terrain dataset rendered at a
turn-based strategic zoom and a real-time battle zoom, where the ground you
parked your army on *is* your deployment when the fighting starts.

## Layout

```
game/
  export_presets.cfg           the "Web" preset — tracked on purpose, CI needs it
  scenes/game.tscn             main scene; the HUD is built in code
  scripts/sim/                 all rules, no rendering, runs headless
    game_config.gd             every tunable number
    terrain.gd                 the one map: two character grids, derived features
    block.gd                   a unit: geometry, facing arcs, collision
    battle_sim.gd              the real-time battle
    battle_ai.gd               attacker / defender behaviours
    campaign.gd                strategic zoom: A* paths, turns, engagement
    scenarios.gd               the three set-pieces and deployment
  scripts/ui/game_root.gd      rendering, input, HUD, tuning panel
  scripts/net_*.gd             the earlier multiplayer counter demo (scenes/main.tscn)
  tests/run_tests.gd           acceptance checks, run headless in CI
server/                        Cloudflare Worker: one Durable Object = one room
.github/actions/godot-export/  composite action: install Godot, import, export, verify
.github/actions/publish-pages/ pages.sh: publish or remove one directory of the site
.github/workflows/ci.yml       tests + export + Worker config check on push/PR
.github/workflows/pr-preview.yml          playable preview per pull request
.github/workflows/pr-preview-cleanup.yml  deletes it when the PR closes
.github/workflows/release.yml  tests + export → site root, and deploy the Worker
```

## The combat prototype

**One map, two zooms.** `terrain.gd` holds a hand-authored 60×40 biome grid and
height grid as editable character art. Hills, forests, the river, the bridge and
the cliffs are *derived* from those grids by flood fill at load — nothing is
authored twice, and both zooms sample the same data.

**Strategic zoom** is turn-based. Hover anything to see its battle modifiers
before committing; click to path (A* weighted by terrain speed, so roads win
without a "snap to road" rule); End Turn moves armies along their paths. Two
hostile armies within 60 units open a battle on a 300×200 crop of the same map.

**Battle zoom** is real time, 90 seconds, four orders (Move / Attack / Hold /
Withdraw) plus Retreat all. Facing decides everything: front ×1.0, flank ×1.5,
rear ×2.0 damage, with morale draining far faster from the sides and doubled
again when a block is held at the front and hit from behind. Cavalry charges
need a 30-unit run-up, are blunted to a quarter by braced infantry from the
front, and delete routing blocks outright.

Three rules were needed to make terrain matter that the spec implies rather than
states, and they are the difference between a chokepoint and a car park:

- **Engaged blocks stand and fight.** An attack order stops at the first enemy
  it touches instead of walking through. Without this a screening block screens
  nothing, and a covered withdrawal is impossible.
- **Enemies are walls, friendlies give way.** Blocks may touch an enemy but not
  pass through one; same-side blocks are pushed apart by a small separation
  nudge instead. Hard-blocking friendlies too made attacking lines wedge
  themselves solid at a gap and simply never arrive.
- **"One block wide" is enforced, not hoped for.** A bridge cell holds one
  block. Blocks still queue *along* the bridge, one behind the other.

### Running the acceptance checks

```sh
cd game && godot --headless --script tests/run_tests.gd
```

68 checks, gated in CI. They assert the behaviours the prototype exists to
prove — a flank charge routing an engaged block inside 5s, the same charge
failing into a brace, an uncovered withdrawal dying where a screened one lives,
every battle ending inside the clock — and they measure the headline claim
rather than asserting it vaguely:

| Fight | On the good ground | In the open |
| --- | --- | --- |
| The Hill, garrison holds | trade **+40 hp** | −3 hp |
| The Ford, garrison holds | trade **+69 hp** | −37 hp |
| The Ford, played properly | 48s, enemy down to **1 of 6** | 14s, enemy loses **nothing** |

### One known balance gap

The Ford's brief says it "should be winnable by bracing on the bridge and using
cavalry on whatever crosses". At the spec's stat table it is a **near miss**: the
best line I could play destroys five of the six attackers and still loses the
last block, because a defender at a one-wide chokepoint trades about 1 : 1.2 and
four blocks cannot outlast six.

Measured fix, if you want it to be a win: raise **archer ranged dps from 5 to 7**
in the tuning panel (it wins at 7, 9 and 11). Infantry melee dps 8 → 10 also
flips it but is not monotonic, so archers are the cleaner knob. The shipped
numbers are the spec's, and a test records the near miss so changing the table
does not silently move it.

## The multiplayer counter demo

Still in the repo as `scenes/main.tscn` — point `run/main_scene` at it to run the
earlier smoke test.

### How it works

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

## How deploys are laid out

Everything lives on one `gh-pages` branch, which is the whole site:

```
/            the last published release
/pr-12/      a playable preview of pull request 12
/pr-15/      …one per open pull request
```

This is why the release does not use `actions/deploy-pages`: that action replaces
the *entire* site on every deployment, so a pull request preview and the released
build cannot coexist under it. `pages.sh` instead rewrites one directory of the
branch and leaves the rest alone — publishing the root explicitly preserves every
`pr-*` directory.

Godot's web export uses only relative paths, so a build served from `/pr-12/`
works untouched; nothing needs a base-path setting.

## One-time setup

1. **Settings → Pages → Build and deployment → Source: *Deploy from a branch*,
   branch `gh-pages`, folder `/ (root)`.** The branch is created by the first
   deploy, so do this after the first preview or release has run.
That is everything the combat prototype needs: it runs entirely in the browser
with no server, and the workflows push to `gh-pages` with the built-in
`GITHUB_TOKEN`, so Pages needs no secrets.

The counter demo additionally needs:

2. **Deploy the Worker once** (`cd server && npx wrangler deploy`) to find out
   its URL, then set repository **variable** `SERVER_URL` to
   `wss://<worker>.<subdomain>.workers.dev/ws`. The release workflow rewrites
   `net_config.gd` with it before exporting; without it the build ships the
   localhost endpoint and never connects.
3. **Secrets** `CLOUDFLARE_API_TOKEN` (Edit Workers template) and
   `CLOUDFLARE_ACCOUNT_ID`, so releases can redeploy the Worker. Without these
   the `deploy-server` job fails, but it is an independent job — the game still
   publishes.

## Previewing a pull request

Open a pull request and `pr-preview.yml` builds it, runs the acceptance tests,
publishes it to `https://<user>.github.io/<repo>/pr-<number>/`, and comments the
link. Later pushes update that same comment; closing or merging the pull request
deletes the directory.

The tests gate the deploy rather than running alongside it — a preview of a build
that fails its own acceptance checks is a trap.

Two limits worth knowing:

- **Forks cannot get a preview.** The workflow runs on `pull_request`, so a fork's
  token is read-only and cannot publish. It reports this as a notice instead of
  failing. Deliberately *not* `pull_request_target`, which would hand a write
  token to unreviewed code. Push the branch to this repository to get a preview.
- **Each preview is ~38 MB**, nearly all of it `index.wasm`. Git stores that blob
  once per Godot version rather than once per push, so history grows by about
  100 KB per push, but several open previews at once do count against the 1 GB
  Pages site limit.

## Publishing a release

Cut a GitHub release (tag + publish). That fires `release.yml`, which:

1. exports the `Web` preset headlessly with a pinned Godot version,
2. verifies the export actually produced `index.{html,js,wasm,pck}` — Godot can
   exit 0 having written a blank page,
3. runs the acceptance tests,
4. publishes `build/` to the site root, keeping every open preview,
5. attaches `web-<tag>.zip` to the release, so every release is downloadable and
   reproducible independent of Pages.

`workflow_dispatch` runs the same thing manually. Note the site root only exists
once a release (or a manual dispatch) has published; before that only the
`/pr-<number>/` previews are served.

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

The combat prototype needs no server — export and open it. The counter demo
needs the Worker, in two terminals; the client's default endpoint is already the
wrangler dev one.

```sh
# 1. server
cd server && npm install && npm run dev      # ws://127.0.0.1:8787/ws

# 2. client
cd game
godot --headless --import
godot --headless --export-release "Web" ../build/index.html
cd ../build && python3 -m http.server 8000
```

Open `http://127.0.0.1:8000`. With the combat prototype as the main scene that
is the game; with `scenes/main.tscn` as the main scene, open two tabs and they
share a counter.

A deployed build can be pointed at another server without rebuilding:
`https://…/?server=ws://127.0.0.1:8787/ws`.
