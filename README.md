# Logistics Roguelike — web build

Godot 4 project that exports to the web and publishes to GitHub Pages whenever a
release is published, plus a Cloudflare Worker that hosts the shared state. See
[`one-pager.md`](one-pager.md) for the game design.

The playable piece is the **combat prototype**: one terrain dataset rendered at a
turn-based strategic zoom and a real-time battle zoom, where the ground you
parked your army on *is* your deployment when the fighting starts.

The build opens on a menu (`scenes/boot.tscn`) with the combat prototype and the
**campaign shell** — the 12-region logistics map, its End Turn pipeline, and a
stack of composable `MapLayer`s that each system draws itself through. On the
web, `?scene=combat` or `?scene=campaign` skips the menu. The campaign's rules
so far are its supply network — see [Logistics](#logistics), and the HUD's
dropdown for the two set-pieces that teach it.

## Layout

```
game/
  export_presets.cfg           "Web" and "Windows Desktop" presets — tracked, CI needs them
  scenes/boot.tscn             main scene: the menu that picks one of the two below
  scenes/game.tscn             the combat prototype; its HUD is built in code
  scenes/campaign.tscn         the campaign shell; its HUD is built in code
  scripts/boot.gd              the menu, and ?scene=combat|campaign on the web
  data/prototype_map.gd        the 12-region logistics map, as data — including the
                               starting armies, so a scenario is a map edit
  scripts/sim/                 all rules, no rendering, runs headless
    game_config.gd             every tunable number
    terrain.gd                 the one map: two character grids, derived features
    block.gd                   a unit: geometry, facing arcs, collision
    battle_sim.gd              the real-time battle
    battle_ai.gd               attacker / defender behaviours
    campaign.gd                strategic zoom: A* paths, turns, engagement
    scenarios.gd               the three set-pieces and deployment
    world/                     the campaign model: world.gd, world_graph.gd, site.gd,
                               edge.gd, region.gd, nation.gd, stack.gd, yields.gd,
                               turn_resolver.gd, world_setup.gd
                               turn_resolver.gd holds the fixed twelve-phase End Turn
                               pipeline; world_setup.gd is its run-start mirror, the
                               hooks World.from_map calls once on a new world
    phases/                    one file per End Turn phase, one owner each —
                               supply_phase.gd, movement_phase.gd and
                               occupation_phase.gd are real since WS-A
    logistics/                 the supply network: supply_rules.gd (Appendix B's
                               arithmetic, pure), pathing.gd (Dijkstra in move
                               points / hops / supply loss), orders.gd (the only
                               writer of Stack.path and order), movement.gd,
                               holdings.gd (who holds a site), scripted_enemy.gd,
                               logistics_setup.gd, logistics_scenarios.gd
    battle/                    the battle bridge: battle_bridge.gd (stack → army,
                               result → regiments and retreat), auto_resolve.gd
                               (the ratio, threshold auto-resolve, the AI stub)
  scripts/ui/game_root.gd      combat prototype: strategic zoom, HUD, tuning; hosts a BattleView
  scripts/ui/battle_view.gd    the battle screen as a component: both shells host it
  scripts/ui/campaign_root.gd  campaign shell: seeded world, HUD, layer registry,
                               the SCENARIOS registry and its picker,
                               side-panel column, set_overlay for the battle view
  scripts/ui/map_view.gd       the campaign map: camera, picking, input, layer stack
  scripts/ui/map_layer.gd      the frozen layer seam: draw / tooltip / pressed /
                               buttons / order / panel
  scripts/ui/layers/           one MapLayer per system: graph_layer.gd,
                               supply_layer.gd (trends, hops, the selected army's
                               supply road), stacks_layer.gd, battle_layer.gd
  scripts/ui/map_camera.gd     pan and zoom, shared by both shells
  scripts/net_*.gd             the earlier multiplayer counter demo (scenes/main.tscn)
  tests/run_tests.gd           discovers tests/test_*.gd; "-- <suite>" runs just one
  tests/harness.gd             the shared check / near / arena / world helpers
  tests/test_combat.gd         the battle and strategic-zoom acceptance checks
  tests/test_world.gd          the campaign world model
  tests/test_campaign_shell.gd the campaign scene builds, seeds, and ends a turn
  tests/test_supply.gd         the supply arithmetic and the phases that apply it
  tests/test_movement.gd       pathing, orders, marching, merging, the scripted enemies
  tests/test_logistics_shell.gd the logistics map layers and the scenario picker
  tests/test_battle_bridge.gd  engagement, the bridge, results, auto-resolve, East Hill
  tests/test_battle_shell.gd   BattleView, the prototype on it, the campaign battle flow
server/                        Cloudflare Worker: one Durable Object = one room
tools/build-windows.ps1        local Windows build: import + export to build/windows/
tools/play-desktop.ps1         play locally in a desktop window, no export (.bat to double-click)
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

**Battle zoom** is real time, 90 seconds, Hold / Withdraw plus drawn routes
and lines plus Retreat all. A block is a line of troops: the long side is its
front, and it moves and fights along the short axis. Two blocks in contact meet
front to front, and the ground each fights from is the ground under its rear
rank. Facing decides everything: front ×1.0, flank ×1.5,
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

**Contact.** Blocks that touch lock together. The attacker is pulled flush
against the face it struck — front to front, both square up; on a flank or the
rear only the attacker turns, so the hit stays a flank hit. The side dealing
more damage through the contact pushes the other back, slowly (up to 6 u/s),
and a loser with a river, a cliff or a friend behind it cannot give ground — a
loser only gives ground when every block winning against it can follow, or the
fight grinds in place. Only a block that is winning can walk out with a Move
(cavalry backing out of a charge does this; `push_smoothing` also sets how
long that hit-and-run window lasts); anyone else leaves by Withdraw, by
routing, or not at all. Blocks turn at a rate (infantry 90°/s) and pivot
before they walk; standing, holding, fighting, attacking and withdrawing
blocks are solid to friends too, but a block on a Move (a drawn route, a
right-click or tap move) passes through them at 0.6× speed and steps to the
nearest free spot if it arrives on top of one. It never stacks onto a fight,
though: it will not walk into a friend that is in contact with the enemy, nor
reach an enemy from inside a friend. It waits behind the friend (it only goes
round if its route does) and takes over when the friend falls. If two marchers
arrive stacked, one takes the fight and the other backs out. Ordering a
flanked block to
attack its flanker starts a **reform**: about two seconds disordered at half
damage, still taking the flank hit, before it faces the new enemy — and
whoever was in front is then on its flank. A reform is cancelled if its target
dies, routs, withdraws or leaves contact, or by the reformer's own Withdraw /
Retreat all / rout. The battle AI keeps attacking whatever is touching its
front and only turns on a flanker once nothing is, so it doesn't reform back
and forth.

### Running the acceptance checks

```sh
cd game && godot --headless --script tests/run_tests.gd             # every suite
cd game && godot --headless --script tests/run_tests.gd -- world    # only test_world.gd
```

Every suite is gated in CI, and the run prints its own total. The **combat
suite's 87 checks** are the stable number to preserve: they assert the
behaviours the prototype exists to prove — a flank charge routing an engaged
block inside 5s, the same charge failing into a brace, an uncovered withdrawal
dying where a screened one lives, every battle ending inside the clock — and
the headline claim is checked as a comparison, never as an exact result: the
same fight goes better on the hill than on the flat, and better at the ford
than in the open. The suite prints the measured trades and block counts for
reading, but no test pins how a battle ends or how long it takes — those move
with every tuning change.

The campaign suites grow as the workstreams land, so their counts are not
quoted here. `test_world.gd` covers the site graph, map validation, the
prototype map's well-formedness (one river crossing, and every nation's depot
still reaching one of its own farms after losing any single site other than the
ford), stacks, relations,
presence, the twelve-phase pipeline and the era boundaries; `test_campaign_shell.gd`
is a smoke test that the campaign scene builds headlessly, seeds itself from map
data, stacks its layers by `order()`, picks, hovers, and ends a turn through
`TurnResolver`.

### The Ford's balance

The Ford's brief says it "should be winnable by bracing on the bridge and using
cavalry on whatever crosses". Whether that line wins or narrowly loses depends
on the tuning (march speed, push values, archer dps); `test_combat.gd` prints
the result of playing it, and only checks that the crossing does better than
the same fight in the open.

## Logistics

The campaign shell's rules are about **feeding armies**, not fighting with them.
Every number lives in `GameConfig.logistics` and every one of them is in the
tuning panel.

**Upkeep is superlinear.** A regiment eats 2 supply a turn; above 8 regiments
the whole stack's bill is ×1.5, above 12 it is ×2. Twelve regiments in one
column eat 36, the same twelve split into four eat 24 — so a big stack is a
liability the moment it leaves its road, and splitting is the answer rather
than a concession.

**Food travels in hops, from a depot with stock.** What the ground under an
army feeds (a farm feeds three regiments, a village one, a feature nobody) is
free; the rest is requested from the nearest depot `Pathing` can reach, and
loses 10% per road hop, 5% per river, 20% per trail, 35% per mountain. Three
road hops deliver 73%. Depots hold stock rather than conjuring food: they open
the run with 60, refill each turn from friendly farms within three hops, and
cap at their capacity. A new depot costs 40 coin, takes two turns to build, and
only one per region is allowed.

**Presence severs.** A hostile stack standing on an interior site is a wall:
routes — supply routes and march orders alike — cannot pass through it, though
they may end on it, which is how an attack is ordered. One raider parked on the
road behind an army can therefore cut its whole delivery without a fight, which
is the game's central trick.

**Hunger costs regiments.** A fed stack's level rises 10 a turn; a short one
falls by 5 × (shortfall ÷ regiments). Crossing 50 is logged once; under 30 a
stack loses a regiment every second turn, and a stack that loses its last one is
gone. Under 10 supply it also moves at half speed.

**Foraging pillages.** An army on hostile ground eats off it and wrecks it: a
farm's yield dies for two turns, a village pays 2 coin and is spoiled for four,
a market pays 10 and is spoiled for three. Your own ground is never pillaged.

**Ground is taken by standing on it.** A stack given **Hold** with no route
garrisons its site, which overrides the region's owner for supply purposes; hold
a majority of a region's sites and the region itself flips. Marching through
takes nothing.

### Reading the map

Each army's disc carries `N rgt · M%` — its size and its supply level. Left of
that, the supply layer draws a **green up or red down arrow** for the direction
its level is moving this turn, and the **hop count** of the route feeding it.
Select an army and a dotted line runs from it back to the depot it is drawing
from; no line means no depot is in reach. Hovering an army gives the whole
ledger in one line — level and delta, upkeep, what the land gave, what the depot
delivered and from how many hops away, and the shortfall if there is one — plus
a line naming the site it is pillaging. Hovering a depot reports its stock, and
says how many turns until it is ready if one is being built.

### The two set-pieces

The HUD's dropdown switches between the open campaign and two scenarios built
from the same map data:

- **The March** — take River East with a single 12-stack and hold it ten turns
  without any stack falling under 50 supply. One column cannot eat there that
  long; splitting to forage and garrison is the lesson.
- **The Siege** — a scripted 14-stack sits on your frontier depot. Fighting it
  loses. Cut its road home with a raider, let it starve and split, then take the
  pieces.

Scenarios are a registry, not a branch in the shell: `CampaignRoot.SCENARIOS`
holds one preload per workstream, each exposing `all()`, `world()` and
`status()`, and the picker lists them in order. `status()` reads progress back
out of the world's own state and log every call, so the HUD line and a headless
test ask the same question.

## Battles on the campaign map

When a march ends on an enemy — or two enemies are still sharing a site from
last turn — End Turn turns it into a battle, one per site per turn:

- **Your fights are played.** The site gets a ⚔ marker with the strength
  ratio; **Fight battle** (or a tap on the marker) opens the real-time battle
  over the map, on a crop of the same ground, with the defender on the site and
  the attacker arriving along the edge it marched in on. A stack fields at most
  8 blocks, one of each role in turn, and the rest wait in reserve. Not ready?
  End the turn and it is offered again — or march away, which is a retreat.
- **Trivial fights are not.** When your stack's effective strength (size ×
  quality × supply) is at least **3×** the enemy's, the fight resolves in your
  favour for 10% attrition, 5 supply and the rest of the move, and the log says
  so with the ratio. About one time in twenty it goes wrong anyway.
- **AI fights** use the same stub: the winner is rolled on strength.

Afterwards, a destroyed block costs a regiment of its role; a block that fled,
routed or withdrew lives. Whoever holds the field wins (nobody: the defender).
The loser falls back one hop — an attacker the way it came, a defender toward
its depot — for 10 supply; a loser with every way out held by the enemy is
lost. Every number is in `GameConfig.battle_bridge` and the tuning panel.

## Playing on a phone

The same build serves desktop and mobile; nothing is forked.

**Scaling.** The project uses `stretch/mode = disabled` and sets the window's
`content_scale_factor` to the device pixel ratio at start-up (physical canvas
width ÷ `window.innerWidth`), so one logical pixel is one CSS pixel on every
device. The earlier `canvas_items` stretch with a 1280×720 base shrank the
whole canvas to fit a phone — on a 390 px screen that is 0.3×, which is why the
buttons were unreadable. Every button is now at least 44 logical px tall and
the HUD rows wrap (`HFlowContainer`) instead of clipping.

**Input**, identical on both zooms:

| | Mouse | Finger |
| --- | --- | --- |
| select | left click anywhere on the block | tap anywhere on the block |
| draw a route (battle) | drag from your block | drag from your block |
| attack at the end of a route | end the drag on an enemy (archers shoot it from there) | end the drag on an enemy (archers shoot it from there) |
| form a line (battle) | select, then drag across the ground | select, then drag across the ground |
| attack (battle) | click an enemy with something selected — archers shoot it, walking into range if needed; others attack it | tap an enemy with something selected — same |
| charge in (battle) | double-click an enemy — everyone selected fights it hand to hand, archers included | double-tap an enemy |
| move (battle) | right click on ground | tap ground with something selected |
| deselect (battle) | click empty ground | tap a selected block again (clears the whole selection) |
| draw a route (map) | left-drag | drag |
| set a route (map) | click a destination | tap a destination |
| box-select | left-drag on ground | drag on ground |
| zoom | wheel | pinch |
| pan | right- or middle-drag | two-finger drag |

**Drawing orders.** In battle you draw rather than click. Drag from one of
your blocks to draw its route — if the block you drag from is selected, the
whole selection follows it, keeping its
shape, and squeezes into a column where the ground is too narrow; end the
stroke on an enemy and they attack it from wherever the route brought them.
Drag across the ground with blocks selected to set a line: infantry on it,
archers a rank behind, cavalry on the wings, everyone facing the enemy. The
battle runs at a quarter speed while you draw. A stroke over the river is
routed over the bridge.

Picking uses the distance to the block's body plus a pad (10 px for a mouse,
24 px for a finger), so a block is hit anywhere on its rectangle rather than
only near its centre. What every block is doing is drawn on the field: a
dashed line to a move point, a red arrow and corner brackets on an attack
target, a spinning clash where two blocks are engaged, streaming dashes from
archers to whoever they are shooting, a white flash on a block that just took
damage, and a tag (MOVING / ATTACKING / FIGHTING / BRACED / ROUTING) over
it. The selection ring is a wide accent glow, the hover outline shows what a
click would pick, and the cursor turns into a hand over your own blocks and a
cross over a target.

Touch is detected with `DisplayServer.is_touchscreen_available()`; append
`?input=touch` or `?input=mouse` to the URL to force either model.

**Drawing a route** samples the stroke every 22 world units and runs A\*
between samples, so a finger dragged straight across the river still produces a
legal route over the bridge. Pathing is `AStarGrid2D` over the terrain grid, with
water and cliffs solid and cell weights set from terrain speed, so roads win
without any snap-to-road rule.

**Portrait battles** turn the 300×200 crop to 200×300 so the field fills the
screen rather than sitting as a strip across the middle; blocks come out about
twice the size. Everything outside the field is dimmed, and a Fit button undoes
any pinch or pan.

Verified in Chromium with a 390×844, 3× touch profile driving real touch events
(including two-finger pinch and pan over CDP) and on a 1280×800 mouse profile.

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

### Windows build

The "Windows Desktop" preset exports one x86_64 exe with the pack embedded,
no code signing and no resource editing, so it needs nothing beyond the
editor and its export templates. Get both once:

1. Godot 4.5-stable editor for Windows from https://godotengine.org/download/windows/
   (the standard build, not .NET), unzipped anywhere.
2. Export templates: in the editor, Editor → Manage Export Templates →
   Download and Install. (Or unzip `Godot_v4.5-stable_export_templates.tpz`
   into `%APPDATA%\Godot\export_templates\4.5.stable\`.)

Then, from a clone of this repo:

```powershell
git clone https://github.com/rkoning/godot-web-test.git
cd godot-web-test
git checkout claude/godot-web-game-cicd-vbk2rt     # until PR #2 is merged

.\tools\build-windows.ps1 -Godot "C:\path\to\Godot_v4.5-stable_win64.exe" -Run
```

`-Godot` can be left out when `godot.exe` is on `PATH` or `$env:GODOT` is
set. `-Debug` exports the debug template with a console window that shows
script errors; `-Run` launches the exe after the build. Double-clicking
`tools\build-windows.bat` does the same with the defaults. The output is
`build\windows\CombatPrototype.exe`, which is git-ignored.

The same preset exports from the command line on any OS, given the Windows
templates: `godot --headless --path game --export-release "Windows Desktop"
build/windows/CombatPrototype.exe` (the output directory must already exist).

There is no CI job for it: the browser build is the deliverable, and the
Windows exe is for running the prototype locally without a web server.
