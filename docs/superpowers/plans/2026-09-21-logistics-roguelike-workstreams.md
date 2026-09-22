# Logistics Roguelike — Implementation Plan by Workstream

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Phase 0 is written at step level and must land first.** Every later workstream is written at task level with its file ownership, interface contract, and tests; expand a workstream into its own step-level plan (superpowers:writing-plans) when it is picked up.

**Goal:** Turn the shipped combat prototype into the full game described in `game-design-doc.md` v1.0, by building the campaign world once (Phase 0) and then developing logistics, trade, battle integration, nation AI, diplomacy, society, characters, crises, government, and map content as independent, parallel workstreams that only touch their own files.

**Architecture:** One headless-first simulation in `game/scripts/sim/` (pure GDScript `RefCounted`, no rendering, deterministic seeded RNG) with a fixed turn pipeline of phase functions, each owned by one workstream. The campaign world is a **site graph** (sites hold resources, edges are roads/rivers/trails/mountains, regions are containers) whose sites carry positions on the existing `Terrain`, so the combat prototype's "crop of the same map" battle works unchanged. Presentation is a `MapView` that composes per-workstream `MapLayer`s. Tests are one file per workstream, auto-discovered.

**Tech Stack:** Godot 4.5 (GL Compatibility, web + Windows export), GDScript, headless `SceneTree` test runner in CI (`.github/workflows/ci.yml`), existing Cloudflare Worker untouched.

## Global Constraints

- Every tunable number lives in `game/scripts/sim/game_config.gd` as a `static var` dictionary; logic never hardcodes a number (spec: "All numbers live in one config").
- All simulation code is `RefCounted`, rendering-free, and runs under `godot --headless`. The AI layer must run at **≥ 200 turns/second for 8 nations** on the prototype map, and **8 nations × 100 turns in under 5 seconds** (Appendix C).
- Determinism: all randomness goes through `World.rng` (seeded). Same seed + same orders = same world.
- No fog of war. No hidden information for the AI ("Everything the AI reads is the same world state the player sees").
- No auto-resolve of non-trivial fights; threshold auto-resolve only, with the ratio visible.
- The one map, two zooms rule: everything that affects a battle is visible at strategic zoom.
- Battle stays 60–90 s, 4–8 blocks a side, four orders. The combat prototype's 87 checks in `game/tests/` must keep passing on every PR.
- Mobile parity is required for the shipped game (design doc: "the map is hover-driven; mobile needs a tap equivalent"), and every HUD button is ≥ 44 logical px.
- Git: never commit or push from an agent session; leave staged work and a suggested message (user's global CLAUDE.md).
- Run tests with `cd game && godot --headless --script tests/run_tests.gd` (CI) or with `$env:GODOT` pointing at the 4.5-stable editor locally (see `tools/build-windows.ps1`).

---

## 0. What exists today (do not rebuild)

| Area | File | State |
| --- | --- | --- |
| Terrain, features, LOS, speed | `game/scripts/sim/terrain.gd` | Done. 60×40 char-art grids, 1200×800 world units, derived features. |
| Battle sim, blocks, facing, charges, routing, withdraw, archers | `game/scripts/sim/battle_sim.gd`, `block.gd` | Done. Appendix A rules incl. bridge lane, brace, pursuit. |
| Battle AI (attacker / defender) | `game/scripts/sim/battle_ai.gd` | Done. |
| Free-movement strategic layer (A* on the grid), engagement range | `game/scripts/sim/campaign.gd`, `army.gd` | Done for the three combat scenarios. **Stays as the combat prototype's campaign; the real game uses the site graph below.** |
| Scenarios + deployment + `start_battle` | `game/scripts/sim/scenarios.gd` | Done. `start_battle(terrain, Army, Army, crop)` is the entry point WS-C reuses. |
| Config | `game/scripts/sim/game_config.gd` | `units`, `combat`, `terrain_mods`, `strategic`, `supply_multiplier(0..1)`. |
| UI shell (both zooms, mouse + touch, tuning panel) | `game/scripts/ui/game_root.gd` (~1300 lines), `map_camera.gd`, `theme_colors.gd` | Done for the combat prototype. Not extended; the campaign gets its own shell. |
| Tests | `game/tests/run_tests.gd` | 87 checks in one file. Phase 0 splits it. |
| CI / Pages / Windows export | `.github/`, `tools/` | Done. |

Gaps versus the design doc: everything in sections 2 (regions, sites, culture, religion), 3 (economy, supply network, trade, raiding, detachments, clocks), 5 (eras, Influence, shop, traditions, government, client states), 6 (characters), 7 (crises), 8 (world map, nations), 9 (nation AI), plus Appendix B and Appendix C in full, plus the threshold auto-resolve and regiment↔block bridge from section 4.

---

## 1. Workstream map and dependency graph

```
Phase 0  FOUNDATION (serial, blocks everything)
         world graph · nations · stacks · turn pipeline · test discovery · campaign shell · 12-region map

Phase 1  (parallel, each consumes only Phase 0)
  WS-A  Logistics core      supply rules, movement, depots, detach/merge, occupation, pillage   (App B M2–M3)
  WS-B  Trade & raiding      routes, caravans, access tags, capture, escort, cut routes         (App B M4–M5)
  WS-C  Battle bridge        stack→blocks, engagement on the graph, result→losses, threshold
                             auto-resolve, battle stub, battle_view extraction               (Design §4)
  WS-E  Influence & diplomacy income, actions, embargo, shop tiers, use-it-or-lose-it           (Design §5)
  WS-F  Society              posture yields, culture, religion spread, unrest                   (Design §2, §3)
  WS-G  Characters           roster, slots, traits, pick-3, forced traits, ageing, family       (Design §6)
  WS-J  Map content          the 40–60 region authored map, 6–8 nations, nodes, wild zones,
                             terrain loaded from data files                                    (Design §8)
  WS-D  Nation AI (part 1)   threat map, edge/region value, Dijkstra, strategic goals,
                             headless sim harness — `proj` lands once WS-A task 1 merges       (App C M1–M3)

Phase 2  (parallel; arrows are the only cross-stream inputs)
  WS-D  Nation AI (part 2)   planner Mass/Forage, tactical tree, raider variant, stubs          (App C M3–M5)  ← A, C
  WS-H  Crises & eras        crisis object, tier-1 catalogue, clocks, relic picks/traditions    (Design §5, §7) ← E, G, K
  WS-I  Government           government types, succession, client states, revolution trigger   (Design §5)     ← G, F, E
  WS-K  Crisis brain + tuning weight override, forced goal, absorb, hill-climb, beat predicates  (App C M6–M7)  ← D, H
  WS-L  Player automation    Forage here / Escort / Mass at, threat overlay, intent tells       (App C)         ← D
  WS-M  Decision density     region→province consolidation, auto-resolve UI, per-turn audit    (Design §1)     ← A, C

Phase 3  INTEGRATION: run structure (3 eras, finale), nation archetypes and unlocks, tier-2/3
         crises, mobile pass on the campaign shell, balance via headless sim.
```

**Why this split is independent.** Every workstream owns a directory under `game/scripts/sim/`, one or more phase files under `game/scripts/sim/phases/`, one test file, and one map layer. Shared classes (`Site`, `Edge`, `Region`, `Nation`, `Stack`, `World`) are frozen by Phase 0 except for the **field additions listed per workstream in §3**; no two workstreams add the same field. Edits to `game_config.gd` and the layer registry are one-line additive hunks.

**Ownership rule (put in every task prompt):** a workstream may create files only under its directories, may edit only its own phase stub, its own test file, and may append (never modify) entries in `game_config.gd`, `WorldSetup.hooks()`, and `CampaignRoot.LAYERS`. `TurnResolver.phases()` is fixed. Anything else is a seam change: stop and raise it.

Specifically, in `game/scripts/ui/`:

| File | Owner after Phase 0 |
| --- | --- |
| `map_layer.gd`, `map_view.gd`, `campaign_root.gd` | **shared Phase 0 files.** An edit here is a seam change: stop and raise it. |
| `layers/graph_layer.gd`, `layers/stacks_layer.gd` | **WS-A** owns both after Phase 0. |
| `layers/<your>_layer.gd` | the workstream that created it. |

Two carve-outs from that table:
- **WS-C** may edit `campaign_root.gd` only to call `set_overlay` / `clear_overlay` for the battle view. Nothing else in that file.
- **WS-J** supplies `Region.polygon` in map **data** and does not edit any layer; `graph_layer.gd` already prefers an authored polygon over the derived hull.

---

## 2. Phase 0 — Foundation (step level)

**Files:**
- Create: `game/tests/harness.gd`, `game/tests/test_combat.gd`, `game/tests/test_world.gd`
- Modify: `game/tests/run_tests.gd` (becomes a discoverer)
- Create: `game/scripts/sim/world/site.gd`, `edge.gd`, `region.gd`, `world_graph.gd`, `nation.gd`, `stack.gd`, `world.gd`, `world_setup.gd`, `turn_resolver.gd`, `yields.gd`
- Create: `game/scripts/sim/phases/ai_phase.gd`, `movement_phase.gd`, `engagement_phase.gd`, `occupation_phase.gd`, `supply_phase.gd`, `trade_phase.gd`, `economy_phase.gd`, `character_phase.gd`, `influence_phase.gd`, `government_phase.gd`, `crisis_phase.gd`, `era_phase.gd`
- Create: `game/data/prototype_map.gd`
- Create: `game/scripts/ui/map_layer.gd`, `map_view.gd`, `campaign_root.gd`, `layers/graph_layer.gd`, `layers/stacks_layer.gd`, `game/scenes/campaign.tscn`, `game/scripts/boot.gd`, `game/scenes/boot.tscn`
- Modify: `game/scripts/sim/game_config.gd` (add `run`, `sites`), `game/project.godot` (main scene → boot), `README.md`

### Task 0.1: Test discovery and harness

Splits the single test file so every workstream gets its own `test_<stream>.gd` and never edits anyone else's.

- [ ] **Step 1: Create the harness**

`game/tests/harness.gd`:
```gdscript
class_name TestHarness
extends RefCounted

## Shared by every tests/test_*.gd suite. A suite is a RefCounted with
## `func run(t: TestHarness) -> void` and calls t.check(...) for each assertion.

const DT := 1.0 / 60.0

var checks := 0
var failures := 0

func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func near(label: String, actual: float, expected: float, tol: float) -> void:
	check(label, absf(actual - expected) <= tol, "got %.3f, wanted %.3f ± %.3f" % [actual, expected, tol])

## A battle arena on the prototype terrain, both sides player-controlled.
func arena(terrain: Terrain = null) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(terrain if terrain != null else Terrain.new(), Rect2(500, 300, 300, 200))
	sim.supply[GameConfig.Side.PLAYER] = 1.0
	sim.supply[GameConfig.Side.ENEMY] = 1.0
	sim.behavior[GameConfig.Side.PLAYER] = ""
	sim.behavior[GameConfig.Side.ENEMY] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	return sim

func run_for(sim: BattleSim, seconds: float) -> void:
	for i in int(seconds / DT):
		sim.step(DT)

## A campaign world on the 12-region prototype map with a fixed seed.
func world(seed := 1) -> World:
	return World.new(WorldGraph.from_data(PrototypeMap.data()), seed)
```

Task 0.4 replaces that last function with `World.from_map(PrototypeMap.data(), seed)`
and adds a second one beside it, which your suite will probably want:
```gdscript
## The prototype world exactly as the shell seeds it, the map's two starting
## field armies included.
func world(seed := 1) -> World:
	return World.from_map(PrototypeMap.data(), seed)

## The same world with the map's starting armies left out. A test that places
## its own stacks, or that counts stacks at a site, wants this one — otherwise
## it is counting the shell's two field armies as well.
func bare_world(seed := 1) -> World:
	var data := PrototypeMap.data()
	data.erase("stacks")
	return World.from_map(data, seed)
```

- [ ] **Step 2: Rewrite the runner as a discoverer**

`game/tests/run_tests.gd`:
```gdscript
extends SceneTree

## Headless test runner. Discovers every tests/test_*.gd, runs it, exits non-zero
## on any failure.
##
##   godot --headless --script tests/run_tests.gd            # everything
##   godot --headless --script tests/run_tests.gd -- supply  # only test_supply.gd

func _init() -> void:
	var t := TestHarness.new()
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]

	var dir := DirAccess.open("res://tests")
	var names: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			if only == "" or f == "test_%s.gd" % only:
				names.append(f)
	names.sort()

	for f in names:
		print("\n== %s" % f)
		var suite = load("res://tests/" + f).new()
		suite.run(t)

	print("\n%d checks, %d failed (%d suites)" % [t.checks, t.failures, names.size()])
	quit(1 if t.failures > 0 else 0)
```
The shipped runner hardens this sketch, and must stay hardened: suites start
from `_process` (the campaign shell needs a root window in the tree), and every
way discovery can go wrong is a **failed check** rather than a silent pass — an
unopenable `res://tests`, a suite that will not `load`, a suite with no `run`, a
suite that asserted nothing, and a `-- <suite>` filter that matched nothing. A
green run that tested nothing is the one result a test runner must never give.

- [ ] **Step 3: Move the existing combat tests**

Create `game/tests/test_combat.gd` with the body of the old `run_tests.gd` from `_test_terrain_loads` onwards, wrapped as:
```gdscript
extends RefCounted

## The combat prototype's acceptance checks (Appendix A). Moved verbatim from
## the old single-file runner; only the harness calls changed.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_terrain_loads()
	_test_block_geometry()
	_test_pathing()
	_test_flank_charge_routs()
	_test_braced_front_charge_fails()
	_test_hill_advantage()
	_test_bridge_has_no_flanks()
	_test_uncovered_withdrawal_is_a_disaster()
	_test_covered_withdrawal_survives()
	_test_battles_end_within_the_clock()
	_test_scenarios_build_and_run()
	_test_supply_scales_damage()
	_test_position_decides_the_battle()
	_test_the_ford_is_winnable()

func check(label: String, condition: bool, detail := "") -> void:
	t.check(label, condition, detail)

func arena(terrain: Terrain = null) -> BattleSim:
	return t.arena(terrain)

func run_for(sim: BattleSim, seconds: float) -> void:
	t.run_for(sim, seconds)
```
Keep the `const DT` line in the file (some helpers use it). Delete `_failures`, `_checks`, and the old `_init`.

- [ ] **Step 4: Run and verify the count is unchanged**

Run: `cd game && godot --headless --script tests/run_tests.gd`
Expected: last line `87 checks, 0 failed (1 suites)`.

- [ ] **Step 5: Stage**

```bash
git add game/tests
```
Suggested message: `Split the test runner into discovered suites`

### Task 0.2: The world graph (sites, edges, regions)

**Interfaces produced (frozen):**
- `Site { id, region_id, kind: Site.Kind, pos: Vector2, name, stock: float, node_tag: String, garrison_nation: int, pillaged_until: int }`
- `Edge { id, a, b, kind: Edge.Kind; other(site_id) -> int }`
- `Region { id, name, owner: int, posture: Region.Posture, sites: Array[int], polygon: PackedVector2Array }`
  - `polygon` is an optional authored outline (WS-J supplies it in map data); empty means the graph layer derives a padded convex hull. WS-J ships borders without editing a layer.
- `WorldGraph.from_data(Dictionary) -> WorldGraph; site(id), region(id), region_of(site_id), edges_of(site_id) -> Array, neighbors(site_id) -> Array[int], edge_between(a, b) -> Edge, sites_in(region_id, kind := -1) -> Array[Site]`
  - `edges_of` returns the **live adjacency array, read-only** — the graph's own storage, not a copy. Filter or sort into your own array.
- `WorldGraph.validate(data: Dictionary) -> PackedStringArray` — every way a hand-authored map can be malformed, as lines naming the offending id: region ids not 0..n-1 in order, site ids not in order, a site's `region` out of range, an edge endpoint out of range, an edge with `a == b`, a duplicate undirected edge. `from_data` calls it first and, on any problem, `push_error`s each line and returns an **empty graph** rather than a half-built one. WS-J's authored map runs through this.

- [ ] **Step 1: Write the failing test**

`game/tests/test_world.gd`:
```gdscript
extends RefCounted

## Phase 0: the campaign world model. Every workstream builds on these shapes.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_graph_loads()
	_test_graph_queries()
	_test_prototype_map_is_well_formed()
	_test_world_stacks_and_relations()
	_test_presence_severs()
	_test_turn_pipeline_runs_every_phase()
	_test_era_edges_fire()

func _test_graph_loads() -> void:
	var g := WorldGraph.from_data({
		"regions": [{"id": 0, "name": "Home", "owner": 0}, {"id": 1, "name": "Away", "owner": 1, "posture": "military"}],
		"sites": [
			{"id": 0, "region": 0, "kind": "farm", "pos": [100, 100]},
			{"id": 1, "region": 0, "kind": "depot", "pos": [140, 100]},
			{"id": 2, "region": 1, "kind": "node", "pos": [200, 100], "tag": "iron"},
		],
		"edges": [{"a": 0, "b": 1}, {"a": 1, "b": 2, "kind": "trail"}],
	})
	t.check("two regions", g.regions.size() == 2)
	t.check("three sites", g.sites.size() == 3)
	t.check("site kind parsed", g.site(0).kind == Site.Kind.FARM)
	t.check("node tag parsed", g.site(2).node_tag == "iron")
	t.check("posture parsed", g.region(1).posture == Region.Posture.MILITARY)
	t.check("default posture economic", g.region(0).posture == Region.Posture.ECONOMIC)
	t.check("edge kind parsed", g.edges[1].kind == Edge.Kind.TRAIL)
	t.check("default edge kind road", g.edges[0].kind == Edge.Kind.ROAD)
	t.check("region lists its sites", g.region(0).sites == [0, 1] as Array[int])

func _test_graph_queries() -> void:
	var g := WorldGraph.from_data(PrototypeMap.data())
	var s := g.site(0)
	t.check("region_of", g.region_of(0).id == s.region_id)
	t.check("neighbors are symmetric",
		g.neighbors(g.neighbors(0)[0]).has(0))
	var n: int = g.neighbors(0)[0]
	t.check("edge_between finds the edge", g.edge_between(0, n) != null)
	t.check("edge_between is symmetric", g.edge_between(n, 0) == g.edge_between(0, n))
	t.check("edge_between misses", g.edge_between(0, 0) == null)
	t.check("sites_in filters by kind",
		g.sites_in(s.region_id, Site.Kind.FARM).all(func(x): return x.kind == Site.Kind.FARM))
```
(The remaining `_test_*` bodies are written in Tasks 0.3–0.5; add them as you reach those tasks. Until then, make them `pass`.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && godot --headless --script tests/run_tests.gd -- world`
Expected: parse error, `WorldGraph` not found.

- [ ] **Step 3: Implement the four classes**

`game/scripts/sim/world/site.gd`:
```gdscript
class_name Site
extends RefCounted

## A point on the map where a resource lives. Every resource in the game is on
## a site; regions are only containers. FEATURE sites hold nothing and exist so
## a hill or a ford is somewhere an army can stand.

enum Kind { FARM, VILLAGE, MINE, MARKET, DEPOT, NODE, FEATURE }

var id := -1
var region_id := -1
var kind := Kind.FEATURE
var pos := Vector2.ZERO           # world units on the Terrain
var name := ""
var stock := 0.0                  # depot stock (WS-A); farms keep nothing here
var node_tag := ""                # NODE only: horses | iron | grain | salt | timber | dye
var garrison_nation := -1         # who holds this site (WS-A occupation), -1 = nobody
var pillaged_until := 0           # yields suppressed while world.turn < this (WS-A)

static func from_dict(d: Dictionary) -> Site:
	var s := Site.new()
	s.id = int(d["id"])
	s.region_id = int(d["region"])
	s.kind = Kind[str(d["kind"]).to_upper()]
	s.pos = Vector2(d["pos"][0], d["pos"][1])
	s.name = str(d.get("name", "%s %d" % [str(d["kind"]).capitalize(), s.id]))
	s.node_tag = str(d.get("tag", ""))
	return s
```

`game/scripts/sim/world/edge.gd`:
```gdscript
class_name Edge
extends RefCounted

## A road, river, trail or mountain pass between two sites. Edges cross region
## borders freely; movement, supply and caravans all travel along them.

enum Kind { ROAD, RIVER, TRAIL, MOUNTAIN }

var id := -1
var a := -1
var b := -1
var kind := Kind.ROAD

func other(site_id: int) -> int:
	return b if site_id == a else a

static func from_dict(d: Dictionary, p_id: int) -> Edge:
	var e := Edge.new()
	e.id = p_id
	e.a = int(d["a"])
	e.b = int(d["b"])
	e.kind = Kind[str(d.get("kind", "road")).to_upper()]
	return e
```

`game/scripts/sim/world/region.gd`:
```gdscript
class_name Region
extends RefCounted

## A container for ownership, posture and 3–6 sites. Nothing is produced here;
## see Site. WS-F adds culture, faith and unrest fields.

enum Posture { MILITARY, ECONOMIC, SOCIAL }

var id := -1
var name := ""
var owner := -1                   # nation id, -1 = unowned / wild
var posture := Posture.ECONOMIC
var sites: Array[int] = []
```

`game/scripts/sim/world/world_graph.gd`:
```gdscript
class_name WorldGraph
extends RefCounted

## The site graph: the campaign map as data. Ids are array indices, checked at
## load, so lookups are O(1) and the AI can index arrays by id.

var sites: Array[Site] = []
var edges: Array[Edge] = []
var regions: Array[Region] = []
var _adj := {}                    # site id -> Array of Edge

static func from_data(data: Dictionary) -> WorldGraph:
	var g := WorldGraph.new()
	for rd in data["regions"]:
		var r := Region.new()
		r.id = int(rd["id"])
		assert(r.id == g.regions.size(), "region ids must be 0..n-1 in order")
		r.name = str(rd.get("name", "Region %d" % r.id))
		r.owner = int(rd.get("owner", -1))
		r.posture = Region.Posture[str(rd.get("posture", "economic")).to_upper()]
		g.regions.append(r)
	for sd in data["sites"]:
		var s := Site.from_dict(sd)
		assert(s.id == g.sites.size(), "site ids must be 0..n-1 in order")
		g.sites.append(s)
		g.regions[s.region_id].sites.append(s.id)
	for i in data["edges"].size():
		var e := Edge.from_dict(data["edges"][i], i)
		g.edges.append(e)
		g._adj.get_or_add(e.a, []).append(e)
		g._adj.get_or_add(e.b, []).append(e)
	return g

func site(id: int) -> Site:
	return sites[id]

func region(id: int) -> Region:
	return regions[id]

func region_of(site_id: int) -> Region:
	return regions[sites[site_id].region_id]

func edges_of(site_id: int) -> Array:
	return _adj.get(site_id, [])

func neighbors(site_id: int) -> Array[int]:
	var out: Array[int] = []
	for e in edges_of(site_id):
		out.append(e.other(site_id))
	return out

func edge_between(a: int, b: int) -> Edge:
	if a == b:
		return null
	for e in edges_of(a):
		if e.other(a) == b:
			return e
	return null

func sites_in(region_id: int, kind := -1) -> Array[Site]:
	var out: Array[Site] = []
	for sid in regions[region_id].sites:
		if kind < 0 or sites[sid].kind == kind:
			out.append(sites[sid])
	return out
```

- [ ] **Step 4: Run the first two tests**

Run: `cd game && godot --headless --script tests/run_tests.gd -- world`
Expected: `_test_graph_loads` passes; `_test_graph_queries` fails on `PrototypeMap` until Task 0.3.

- [ ] **Step 5: Stage** — `git add game/scripts/sim/world game/tests/test_world.gd`. Message: `Add the campaign site graph`

### Task 0.3: The 12-region prototype map (data)

This is Appendix B's map, placed on the existing 1200×800 terrain so battle crops land on real hills, the bridge, and the forests.

**The map is a network, not a tree.** Each side gets lateral edges so that a raider taking one site reroutes a supply line instead of ending it, and the invariant the tests hold is: **for every site except "The Ford", removing it leaves each nation's depot still able to reach at least one of that nation's own farms.** (A weaker market-to-depot version is also asserted, but it passes trivially — both are joined by a direct edge — so it is a guard, not the thing that keeps the laterals in place.) The ford stays the only crossing, and a test asserts both that and its converse: removing the ford *does* separate the two nations. WS-J's authored map must satisfy the same two claims.

- [ ] **Step 1: Add the well-formedness test**

In `test_world.gd`:
```gdscript
func _test_prototype_map_is_well_formed() -> void:
	var g := WorldGraph.from_data(PrototypeMap.data())
	var terrain := Terrain.new()
	t.check("12 regions", g.regions.size() == 12, str(g.regions.size()))
	var kinds := {}
	for r in g.regions:
		t.check("%s has 3–6 sites" % r.name, r.sites.size() >= 3 and r.sites.size() <= 6, str(r.sites.size()))
	for s in g.sites:
		kinds[s.kind] = true
		t.check("%s on land" % s.name, not terrain.is_blocked(s.pos, GameConfig.Role.INFANTRY) or s.kind == Site.Kind.FEATURE)
		t.check("%s is connected" % s.name, g.neighbors(s.id).size() > 0)
	for k in Site.Kind.values():
		t.check("map has a %s" % Site.Kind.keys()[k], kinds.has(k))
	var edge_kinds := {}
	for e in g.edges:
		edge_kinds[e.kind] = true
		t.check("edge %d joins distinct sites" % e.id, e.a != e.b)
	t.check("all four edge kinds used", edge_kinds.size() == 4)
	var owners := {}
	for r in g.regions:
		owners[r.owner] = true
	t.check("two nations own regions", owners.has(0) and owners.has(1))
	t.check("nations listed", PrototypeMap.data()["nations"].size() == 2)
```

- [ ] **Step 2: Author the map**

`game/data/prototype_map.gd` — the shape is fixed; author 12 regions. Two of the twelve are shown; the rest follow the same shape and must satisfy the test above (3–6 sites each; at least one farm, village, mine, market, depot, node and feature overall; roads, a river along the terrain's water column at x≈600, at least one trail and one mountain edge near the cliffs at the top-right; nations 0 = player "Empire", 1 = "Warlord"; sites on non-water, non-cliff cells; the bridge feature at `(590, 390)` and the two hill features at `(300, 190)` and `(940, 490)`).
```gdscript
class_name PrototypeMap
extends RefCounted

## The 12-region logistics prototype map (Appendix B), laid over the combat
## prototype's terrain so battles crop real ground. Sites are numbered in
## order; ids are array indices.

static func data() -> Dictionary:
	return {
		"nations": [
			{"id": 0, "name": "Empire", "color": "4a90d9", "player": true, "coin": 60},
			{"id": 1, "name": "Warlord", "color": "d9534f", "player": false, "coin": 60},
		],
		"relations": [{"a": 0, "b": 1, "state": "war"}],
		"regions": [
			{"id": 0, "name": "Capital Plain", "owner": 0, "posture": "economic"},
			{"id": 1, "name": "West Farmland", "owner": 0, "posture": "military"},
			# ... regions 2–11
		],
		"sites": [
			{"id": 0, "region": 0, "kind": "market", "pos": [180, 450], "name": "Capital"},
			{"id": 1, "region": 0, "kind": "depot", "pos": [230, 470], "name": "Capital depot"},
			{"id": 2, "region": 0, "kind": "farm", "pos": [130, 520]},
			{"id": 3, "region": 0, "kind": "village", "pos": [250, 400]},
			{"id": 4, "region": 1, "kind": "farm", "pos": [80, 300]},
			{"id": 5, "region": 1, "kind": "farm", "pos": [140, 260]},
			{"id": 6, "region": 1, "kind": "village", "pos": [60, 380]},
			{"id": 7, "region": 1, "kind": "feature", "pos": [300, 190], "name": "West Hill"},
			# ... sites for regions 2–11, including
			#   {"kind": "feature", "pos": [590, 390], "name": "The Ford"}   on the bridge
			#   {"kind": "feature", "pos": [940, 490], "name": "East Hill"}
			#   {"kind": "node", "tag": "iron", ...}, {"kind": "node", "tag": "horses", ...}
			#   {"kind": "mine", ...}
		],
		"edges": [
			{"a": 0, "b": 1}, {"a": 0, "b": 2}, {"a": 0, "b": 3},
			{"a": 3, "b": 7, "kind": "trail"}, {"a": 2, "b": 4}, {"a": 4, "b": 5}, {"a": 5, "b": 6},
			# ... roads along Terrain.ROADS, a "river" chain down the water column,
			#     "mountain" edges into the cliff corner, the ford edge crossing at site "The Ford"
		],
	}
```

- [ ] **Step 3: Run** — `godot --headless --script tests/run_tests.gd -- world`. Expected: every map check passes.

- [ ] **Step 4: Stage** — `git add game/data`. Message: `Author the 12-region prototype map`

### Task 0.4: Nations, stacks, the world, relations, presence

**Interfaces produced (frozen):**
- `Nation { id, name, color, is_player, coin, influence, alive, weights: Dictionary, access_tags: Dictionary }`
- `Stack { id, nation_id, site_id, regiments: Array[int], supply: float (0..100), leader_id, quality, path: Array[int], order: String, order_target: int, hold_separate, label, moved_this_turn, supply_report: Dictionary; size() -> int; strength() -> float }`
- `World { const WAR, const PEACE; graph, nations, stacks, routes: Array, characters: Array, crises: Array, pending_battles: Array, provinces: Array, turn, rng, events, era_listeners: Array[Callable]; player(), nation(id), add_stack(nation_id, site_id, regiments, supply := 100.0) -> Stack, remove_stack(s), stacks_at(site_id), stacks_of(nation_id), relation(a, b) -> String, set_relation(a, b, state), hostile(a, b) -> bool, hostile_presence(site_id, nation_id) -> bool, is_severed(edge, nation_id) -> bool, static era_of(turn) -> int, era() -> int, record(text) }`
  - `WAR` / `PEACE` are the only two relation states; compare against the constants, never a `"war"` literal (a typo reads as peace).
  - `pending_battles` (WS-C) and `provinces` (WS-M) are pre-declared so neither stream has to edit `world.gd` to land its first task.
  - `era_of(turn)` is static and holds the only copy of the era formula; `era()` is `era_of(turn)`. The final era does not roll over (turn 1000 is still era 3) and `turns_per_era` is floored at 1, so the tuning panel cannot divide by zero.
- `World.from_map(data: Dictionary, seed := 1) -> World` — graph, nations, relations, then the map's optional `"stacks"` array, then every `WorldSetup` hook. The only way a world is born.
  - `"stacks"`: `[{"nation": 0, "site": "<site name>", "regiments": ["infantry", "cavalry", ...] or [ints], "supply": 100}]`. Sites are resolved by name (an unknown name is a `push_error` and a skipped stack); role strings map to `GameConfig.Role` upper-cased. A scenario is a map edit, not a change to the shell.
- `WorldSetup.hooks() -> Array[Callable]` (`world/world_setup.gd`) — the run-start mirror of `TurnResolver.phases()`. `from_map` calls each hook once with the finished world; a hook may append to `world.era_listeners`. One line per workstream: characters (WS-G), shop stock (WS-E), culture/faith defaults (WS-F), crisis catalogue (WS-H). WS-M has no setup slot by design.

- [ ] **Step 1: Write the failing tests**

In `test_world.gd`:
```gdscript
func _test_world_stacks_and_relations() -> void:
	var w := t.bare_world()
	t.check("player nation is 0", w.player().id == 0)
	t.check("nations loaded", w.nations.size() == 2)
	t.check("prototype nations at war", w.hostile(0, 1))
	t.check("a nation is not hostile to itself", not w.hostile(0, 0))
	w.set_relation(0, 1, World.PEACE)
	t.check("relations are symmetric", w.relation(1, 0) == World.PEACE)
	var s := w.add_stack(0, 1, [GameConfig.Role.INFANTRY, GameConfig.Role.INFANTRY, GameConfig.Role.CAVALRY])
	t.check("stack sized by roster", s.size() == 3)
	t.check("stack has a unique id", w.add_stack(0, 1, [GameConfig.Role.INFANTRY]).id != s.id)
	t.check("stacks_at", w.stacks_at(1).size() == 2)
	t.check("stacks_of", w.stacks_of(0).size() == 2 and w.stacks_of(1).is_empty())
	t.near("strength at full supply", s.strength(), 3.0, 0.001)
	s.supply = 0.0
	t.near("strength at zero supply is half", s.strength(), 1.5, 0.001)
	w.remove_stack(s)
	t.check("remove_stack", w.stacks_at(1).size() == 1)
	t.check("deterministic rng", t.world(7).rng.randi() == t.world(7).rng.randi())

func _test_presence_severs() -> void:
	var w := t.bare_world()
	var e: Edge = w.graph.edges[0]
	t.check("no presence, not severed", not w.is_severed(e, 0))
	w.add_stack(1, e.a, [GameConfig.Role.CAVALRY])
	t.check("hostile stack on an endpoint severs it for the other nation", w.is_severed(e, 0))
	t.check("but not for its own nation", not w.is_severed(e, 1))
	w.set_relation(0, 1, World.PEACE)
	t.check("at peace, presence does not sever", not w.is_severed(e, 0))
```

- [ ] **Step 2: Run to verify it fails** — `-- world`. Expected: `Nation`/`World` not found.

- [ ] **Step 3: Implement**

`game/scripts/sim/world/nation.gd`:
```gdscript
class_name Nation
extends RefCounted

## One faction. Player and AI nations are the same class; `is_player` only
## decides who issues the orders.

var id := -1
var name := ""
var color := Color.WHITE
var is_player := false
var coin := 0.0
var influence := 0.0
var alive := true
var weights := {}                 # AI personality (WS-D)
var access_tags := {}             # node tag -> turn it expires (WS-B)

static func from_dict(d: Dictionary) -> Nation:
	var n := Nation.new()
	n.id = int(d["id"])
	n.name = str(d["name"])
	n.color = Color(str(d.get("color", "ffffff")))
	n.is_player = bool(d.get("player", false))
	n.coin = float(d.get("coin", 0))
	n.influence = float(d.get("influence", 0))
	return n
```

`game/scripts/sim/world/stack.gd`:
```gdscript
class_name Stack
extends RefCounted

## A campaign army: regiments standing on one site. For the 90 seconds of a
## battle it becomes the combat prototype's Army (WS-C bridges the two).

var id := -1
var nation_id := -1
var site_id := -1
var regiments: Array[int] = []    # GameConfig.Role per regiment
var supply := 100.0               # 0..100 (Appendix B scale)
var leader_id := -1               # Character id (WS-G), -1 = none
var quality := 1.0                # leader multiplier; WS-G replaces the stub
var path: Array[int] = []         # site ids still to walk (WS-A)
var order := ""                   # "" | "hold" | "escort" | "raid" (WS-A/B/D)
var order_target := -1            # site, route or edge id the order refers to
var hold_separate := false
var label := ""
var moved_this_turn := false
var supply_report := {}           # written by SupplyPhase (WS-A), read by UI and AI

func size() -> int:
	return regiments.size()

func strength() -> float:
	return float(size()) * quality * GameConfig.supply_multiplier(supply / 100.0)
```

`game/scripts/sim/world/world.gd`:
```gdscript
class_name World
extends RefCounted

## Everything the campaign simulates, and the only place randomness comes from.
## Headless by construction: no nodes, no signals, no rendering.

var graph: WorldGraph
var nations: Array[Nation] = []
var stacks: Array[Stack] = []
var routes: Array = []            # TradeRoute (WS-B)
var characters: Array = []        # Character (WS-G)
var crises: Array = []            # Crisis (WS-H)
var pending_battles: Array = []   # {attacker, defender, site_id, from_site} (WS-C)
var provinces: Array = []         # Province (WS-M)
var turn := 1
var rng := RandomNumberGenerator.new()
var events: PackedStringArray = []
var era_listeners: Array[Callable] = []   # called (world, new_era) by EraPhase

## The two relation states. Compare against these, never a literal.
const WAR := "war"
const PEACE := "peace"

var _next_stack_id := 1
var _relations := {}              # "lo:hi" -> WAR | PEACE

func _init(p_graph: WorldGraph, seed := 1) -> void:
	graph = p_graph
	rng.seed = seed

## The only way a world is born: graph, nations, relations, the map's starting
## stacks, then every WorldSetup hook. The shell, a test and the headless AI
## harness all get the same world from the same data.
static func from_map(data: Dictionary, seed := 1) -> World:
	var w := World.new(WorldGraph.from_data(data), seed)
	for nd in data.get("nations", []):
		var n := Nation.from_dict(nd)
		assert(n.id == w.nations.size(), "nation ids must be 0..n-1 in order")
		w.nations.append(n)
	for rd in data.get("relations", []):
		var state := str(rd["state"])
		if state != WAR and state != PEACE:
			push_error("map relation %d:%d has unknown state '%s'" % [int(rd["a"]), int(rd["b"]), state])
			continue
		w.set_relation(int(rd["a"]), int(rd["b"]), state)
	for sd in data.get("stacks", []):
		w._add_map_stack(sd)          # site by name, roles by name or int
	for hook in WorldSetup.hooks():
		hook.call(w)
	return w

func player() -> Nation:
	for n in nations:
		if n.is_player:
			return n
	return null

func nation(id: int) -> Nation:
	return nations[id]

func add_stack(nation_id: int, site_id: int, regiments: Array, supply := 100.0) -> Stack:
	var s := Stack.new()
	s.id = _next_stack_id
	_next_stack_id += 1
	s.nation_id = nation_id
	s.site_id = site_id
	for r in regiments:
		s.regiments.append(int(r))
	s.supply = supply
	s.label = "%s stack %d" % [nation(nation_id).name, s.id]
	stacks.append(s)
	return s

func remove_stack(s: Stack) -> void:
	stacks.erase(s)

func stacks_at(site_id: int) -> Array[Stack]:
	var out: Array[Stack] = []
	for s in stacks:
		if s.site_id == site_id:
			out.append(s)
	return out

func stacks_of(nation_id: int) -> Array[Stack]:
	var out: Array[Stack] = []
	for s in stacks:
		if s.nation_id == nation_id:
			out.append(s)
	return out

func _rel_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

func relation(a: int, b: int) -> String:
	return _relations.get(_rel_key(a, b), PEACE)

func set_relation(a: int, b: int, state: String) -> void:
	_relations[_rel_key(a, b)] = state

func hostile(a: int, b: int) -> bool:
	return a != b and relation(a, b) == WAR

## Walks `stacks` rather than calling `stacks_at`: the hottest query in the game
## (per site per hop per nation per turn) must not allocate to answer yes/no.
func hostile_presence(site_id: int, nation_id: int) -> bool:
	for s in stacks:
		if s.site_id == site_id and hostile(s.nation_id, nation_id):
			return true
	return false

## Presence severs: an edge is cut for `nation_id` while a hostile stack stands
## on either end. Repair is free the turn the stack leaves. Pathing and supply
## (WS-A) refuse to pass *through* a site with hostile presence; this query is
## what the map draws dashed red and what edge value (WS-D) reads.
func is_severed(e: Edge, nation_id: int) -> bool:
	return hostile_presence(e.a, nation_id) or hostile_presence(e.b, nation_id)

## The one copy of the era formula. The last era does not roll over (Phase 3
## decides what ends a run), and `turns_per_era` is floored at 1 so a tuning
## spinner dragged to zero cannot divide by zero mid-frame.
static func era_of(t: int) -> int:
	var per: int = maxi(1, int(GameConfig.run["turns_per_era"]))
	return mini(int((t - 1) / per) + 1, int(GameConfig.run["eras"]))

func era() -> int:
	return era_of(turn)

func record(text: String) -> void:
	events.append("T%d %s" % [turn, text])
```

Add to `game_config.gd` (append after `strategic`):
```gdscript
## Run structure. Three eras; the crisis occupies the last third of each.
static var run := {
	"turns_per_era": 24,
	"eras": 3,
}

## Base per-turn yields and capacities per site kind (Appendix B table).
## WS-F multiplies by posture/culture/unrest; WS-A reads capacities.
static var sites := {
	"farm_supply": 6.0,
	"farm_forage_regiments": 3,
	"village_levy_every_turns": 2,
	"village_forage_regiments": 1,
	"mine_coin": 4.0,
	"market_coin": 3.0,
	"market_forage_regiments": 2,
	"market_trade_multiplier": 1.5,
	"node_coin": 2.0,
	"depot_max_stock": 120.0,
}
```

`game/scripts/sim/world/yields.gd` (base yields; WS-F owns extending it):
```gdscript
class_name Yields
extends RefCounted

## Per-turn base yields by site kind. WS-F layers posture, culture and unrest
## on top by editing these functions; everyone else calls them and never
## reads GameConfig.sites directly.

static func supply(site: Site, _region: Region, world: World) -> float:
	if site.kind != Site.Kind.FARM or world.turn < site.pillaged_until:
		return 0.0
	return GameConfig.sites["farm_supply"]

static func coin(site: Site, _region: Region, world: World) -> float:
	if world.turn < site.pillaged_until:
		return 0.0
	match site.kind:
		Site.Kind.MINE: return GameConfig.sites["mine_coin"]
		Site.Kind.MARKET: return GameConfig.sites["market_coin"]
		Site.Kind.NODE: return GameConfig.sites["node_coin"]
	return 0.0

## Region and world are in the signature though the base rule ignores them:
## WS-F scales this by posture, culture and unrest, and a caller that had to
## find out whether they mattered would be reading the tables it must not touch.
static func forage_regiments(site: Site, _region: Region, _world: World) -> int:
	match site.kind:
		Site.Kind.FARM: return GameConfig.sites["farm_forage_regiments"]
		Site.Kind.VILLAGE: return GameConfig.sites["village_forage_regiments"]
		Site.Kind.MARKET: return GameConfig.sites["market_forage_regiments"]
	return 0

## The one place depot capacity is read — WS-A can make it depend on the site,
## WS-F on the region, and no caller learns about it. The map's depot fill bar
## goes through here too, never through `GameConfig.sites` directly.
static func depot_capacity(_site: Site, _world: World) -> float:
	return GameConfig.sites["depot_max_stock"]
```
Update `TestHarness.world()` to `return World.from_map(PrototypeMap.data(), seed)`.

- [ ] **Step 4: Run** — `-- world`. Expected: stacks/relations/presence checks pass.
- [ ] **Step 5: Stage** — message: `Add nations, stacks and the world`

### Task 0.5: The turn pipeline and phase stubs

**Interface produced (frozen):** `TurnResolver.end_turn(world)`; **twelve** phase classes each with `static func run(world: World) -> void`. Order is fixed below. A workstream implements its phase in place; nobody reorders.

**WS-M (provinces) has no per-turn slot by design** — consolidation is an action, not a phase.

- [ ] **Step 1: Write the failing tests**

```gdscript
func _test_turn_pipeline_runs_every_phase() -> void:
	var w := t.world()
	var s := w.add_stack(0, 0, [GameConfig.Role.INFANTRY])
	s.moved_this_turn = true
	TurnResolver.end_turn(w)
	t.check("turn advanced", w.turn == 2)
	t.check("moved flag reset before phases", not s.moved_this_turn)
	t.check("phase list has twelve slots", TurnResolver.phases().size() == 12)
	# Every slot is a live callable a fresh world survives, and no phase
	# advances the turn itself — that is `end_turn`'s job alone.
	var fresh := t.world()
	for phase in TurnResolver.phases():
		phase.call(fresh)
	t.check("no phase advances the turn on its own", fresh.turn == 1)

func _test_era_edges_fire() -> void:
	var w := t.world()
	var fired: Array = []
	w.era_listeners.append(func(_w: World, era: int): fired.append(era))
	for i in int(GameConfig.run["turns_per_era"]) - 1:
		TurnResolver.end_turn(w)
	t.check("no era edge before the boundary", fired.is_empty())
	TurnResolver.end_turn(w)
	t.check("era 2 announced on the boundary", fired == [2])
	t.check("world reports era 2", w.era() == 2)
```

- [ ] **Step 2: Run** — `-- world`. Expected: `TurnResolver` not found.

- [ ] **Step 3: Implement the resolver and the eleven stubs**

`game/scripts/sim/world/turn_resolver.gd`:
```gdscript
class_name TurnResolver
extends RefCounted

## End Turn runs every phase in this fixed order. Each phase is one static
## function in its own file under sim/phases/, owned by one workstream, so a
## system can be built without touching anyone else's. The order is the seam:
## do not reorder without telling every owner.
##
## WS-M (provinces) has no per-turn slot by design; consolidation is an action,
## not a phase.

static func phases() -> Array[Callable]:
	return [
		AiPhase.run,           # WS-D  AI nations issue orders (the player already did)
		MovementPhase.run,     # WS-A  walk paths along edges; merge on arrival
		EngagementPhase.run,   # WS-C  hostile stacks on one site → battle / stub
		OccupationPhase.run,   # WS-A  who holds each site and region
		SupplyPhase.run,       # WS-A  depots refill, upkeep, levels, pillage
		TradePhase.run,        # WS-B  dispatch, move, arrive, capture caravans
		EconomyPhase.run,      # WS-F  coin, levies, unrest, culture/faith drift
		CharacterPhase.run,    # WS-G  leaders act, history accrues, quality resolves
		InfluencePhase.run,    # WS-E  Influence income, AI diplomacy and shop
		GovernmentPhase.run,   # WS-I  constituencies, client drift, tribute
		CrisisPhase.run,       # WS-H  eligibility, announcements, clocks, resolution
		EraPhase.run,          # P0    era boundaries
	]

static func end_turn(world: World) -> void:
	for s in world.stacks:
		s.moved_this_turn = false
	for phase in phases():
		phase.call(world)
	world.turn += 1
```

Eleven stubs, identical shape, e.g. `game/scripts/sim/phases/movement_phase.gd`:
```gdscript
class_name MovementPhase
extends RefCounted

## WS-A owns this file. Stub until then.

static func run(_world: World) -> void:
	pass
```
Create `AiPhase`, `MovementPhase`, `EngagementPhase`, `OccupationPhase`, `SupplyPhase`, `TradePhase`, `EconomyPhase`, `CharacterPhase`, `InfluencePhase`, `GovernmentPhase`, `CrisisPhase` this way, each header naming its owner (D, A, C, A, A, B, F, G, E, I, H).

`game/scripts/sim/phases/era_phase.gd` (real). The formula lives once, in
`World.era_of`; this phase only compares this turn with the next:
```gdscript
class_name EraPhase
extends RefCounted

## Announces era boundaries. Runs last, so listeners see the finished turn.
## The turn counter has not advanced yet, so compare this turn with the next
## through `World.era_of`, which is the only copy of the formula.

static func run(world: World) -> void:
	var next := World.era_of(world.turn + 1)
	if next == world.era():
		return
	world.record("Era %d begins" % next)
	for l in world.era_listeners:
		l.call(world, next)
```

- [ ] **Step 4: Run everything** — `godot --headless --script tests/run_tests.gd`. Expected: `87 + N checks, 0 failed (2 suites)`.
- [ ] **Step 5: Stage** — message: `Add the turn pipeline with one phase per system`

### Task 0.6: Campaign shell and map layers

**Interface produced (frozen):**
```gdscript
class_name MapLayer            # game/scripts/ui/map_layer.gd
extends RefCounted
var view: MapView
func draw(_canvas: CanvasItem) -> void: pass                 # world→screen via view.w2s
func tooltip(_world_pos: Vector2) -> String: return ""      # first non-empty wins, top layer first
func pressed(_world_pos: Vector2) -> bool: return false     # true = consumed
func buttons() -> Array[Dictionary]: return []              # [{label, action: Callable, enabled: Callable}]
func order() -> int: return 0                               # draw order and input priority
func panel() -> Control: return null                        # optional side panel, same instance each call
```
- `order()` — lower draws first and answers input last. `StacksLayer` is **100** and stays on top; `GraphLayer` is **0**; workstreams use **10–90**. `CampaignRoot` sorts by this (stably), so appending to `LAYERS` in any position still lands the layer where it means to and no two streams conflict over a line of that array.
- `panel()` — an optional `Control` `CampaignRoot` hosts in a right-hand scrolling column, hidden while no layer wants it. Return the **same instance** each call; the layer keeps ownership.
- `buttons()` — `enabled` is optional and defaults to always-enabled; a spec with no `action` is skipped with a `push_warning`.

`MapView` (a `Control`): `world: World`, `terrain: Terrain`, `camera: MapCamera`, `selected: Stack`, `layers: Array[MapLayer]`, `hover_world: Vector2` (`Vector2.INF` until the pointer moves), `w2s(p)`, `s2w(p)`, `site_at(world_pos, radius := 18.0) -> Site`, `stack_at(world_pos, radius := 24.0) -> Stack` (both return null for a non-finite point). Draws the terrain texture (copy `_build_terrain_texture` from `game_root.gd`), then each layer in order. The terrain's extent is read off the **instance** (`terrain.SIZE`, `terrain.COLS`…), never the class, because WS-J turns those constants into instance members.

`CampaignRoot` (the scene root) builds the HUD (End Turn, Reset, status line, tooltip line, tuning toggle), registers layers from `const LAYERS` sorted by `order()`, hosts every non-null `panel()`, and on End Turn calls `TurnResolver.end_turn(world)` then `queue_redraw()`. It also owns the overlay seam:
```gdscript
func set_overlay(control: Control) -> void   # hide the MapView, show `control` full-rect
func clear_overlay() -> void                 # unparent it (caller keeps ownership) and show the map
```
WS-C switches to its battle view through these two and touches nothing else in `campaign_root.gd`.

- [ ] **Step 1: Create `map_layer.gd`, `map_view.gd`, `campaign_root.gd`, `campaign.tscn`** with mouse input (hover → tooltip, click → `pressed`, wheel zoom, right-drag pan via `MapCamera`). Copy pointer handling from `game_root.gd` lines 539–700 only for mouse; touch parity is Phase 3.

- [ ] **Step 2: `layers/graph_layer.gd`**: draws regions as translucent convex hulls of their sites tinted by owner color, edges as lines styled by kind (road solid, river blue thick, trail dotted, mountain grey dashed), severed edges (any `world.is_severed(e, player.id)`) dashed red, sites as a glyph per kind with the site name on hover. Tooltip: `"%s — %s. Owner: %s. Posture: %s"` plus supply/coin yields from `Yields`.

- [ ] **Step 3: `layers/stacks_layer.gd`**: draws each stack as a disc at its site (offset if several), colored by nation, labelled `"%d rgt · %d%%" % [size, supply]`. Click selects; click on a site with a stack selected sets `stack.path = [site]` if adjacent (WS-A replaces with real pathing). Tooltip: label, regiments by role, supply, `supply_report` if present.

- [ ] **Step 4: `boot.gd` / `boot.tscn`** — two buttons: "Combat prototype" → `game.tscn`, "Campaign" → `campaign.tscn`; on web, `?scene=campaign|combat` skips the menu (reuse `NetConfig._query_param` by copying it into a `Query` helper in `boot.gd`). Set `run/main_scene="res://scenes/boot.tscn"` in `project.godot`.

- [ ] **Step 5: `campaign_root.gd`** seeds the world with `World.from_map(PrototypeMap.data(), SEED)` and **nothing else** — the 12-regiment player stack on the Capital Depot and the 6-regiment Warlord stack on the Warcamp Depot are entries in the map's `"stacks"` array, so a scenario is a map edit rather than a change to the shell, and the headless AI harness seeds the same world. Its tuning panel is generic: it iterates every `static var` dictionary in `GameConfig` (`units`, `combat`, `terrain_mods`, `strategic`, `run`, `sites`, and whatever workstreams append) and builds one row per numeric key, reusing `_tuning_row` from `game_root.gd`. Workstreams then get tuning for free by appending a dictionary.

- [ ] **Step 6: Verify** — export runs in CI (`ci.yml` already exports); locally `tools/build-windows.ps1 -Run` opens the boot menu; the campaign shows 12 tinted regions, edges, glyphs, two stacks, End Turn increments the turn in the status line. Update `README.md` layout section with the new directories and the `-- suite` runner flag.

- [ ] **Step 7: Stage** — message: `Add the campaign shell with composable map layers`

**Phase 0 exit criteria:** tests green (3 suites), CI exports, campaign scene renders the prototype map, every phase file exists with a named owner, and **the suite has run once on Godot 4.5-stable (the CI job) before fan-out** — the local editor is 4.7, and a seam that only parses on 4.7 would break every workstream at once. Now fan out.

---

## 3. Phase 1 & 2 workstreams (task level)

Each workstream below is written so a fresh agent can start from Phase 0 with only this section, the design doc, and the ownership rule. "Adds to shared classes" is the *only* permitted edit to Phase 0 classes.

### WS-A — Logistics core (Appendix B, milestones 2–3)

**Owns:** `game/scripts/sim/logistics/` (`supply_rules.gd`, `pathing.gd`, `orders.gd`), `phases/movement_phase.gd`, `phases/occupation_phase.gd`, `phases/supply_phase.gd`, `ui/layers/supply_layer.gd`, `tests/test_supply.gd`, `tests/test_movement.gd`.
**Adds to shared classes:** `Site.depot_ready_turn: int` (construction), `GameConfig.logistics` dict (all numbers from the App B tables: upkeep per regiment 2, ×1.5 > 8, ×2 > 12; hop loss road 0.10 / river 0.05 / trail 0.20 / mountain 0.35; movement cost road 1 / river 1 / trail 2 / mountain 3; move points 4, 3 above 8 regiments, 2 above 12, raider 5; depot cost 40, build 2 turns, max stock 120, farm reach 3 hops; desertion below 30 every 2 turns; movement halved below 10; level +10 / −(shortfall/regiments)×5; pillage table).
**Consumes:** Phase 0 only (`World`, `WorldGraph`, `Yields`, `GameConfig.sites`).
**Produces (contract for D, B, C):**
```gdscript
SupplyRules.upkeep(regiments: int) -> float
SupplyRules.local_feed(world, site: Site, regiments: int) -> float        # min(forage cap, regiments) × 2
SupplyRules.hop_loss(kind: Edge.Kind) -> float
SupplyRules.delivered(requested: float, edges: Array) -> float           # requested × Π(1 − loss)
SupplyRules.level_delta(shortfall: float, regiments: int) -> float
SupplyRules.report(world, stack) -> Dictionary  # {upkeep, local, depot, delivered, shortfall, hops, depot_id, delta}
Pathing.shortest(world, from_site, to_site, nation_id, cost := "movement") -> Array[int]   # sites, [] if unreachable; never passes through hostile presence
Pathing.nearest_depot(world, site_id, nation_id) -> Dictionary            # {site_id, hops, edges} or {}
Movement.points_for(stack) -> int
Orders.move(world, stack, to_site) -> bool
Orders.detach(world, stack, n: int, to_site) -> Stack
Orders.hold(world, stack) -> void            # garrison: order = "hold"
Orders.build_depot(world, nation, site) -> bool
```
**Tasks:**
1. `SupplyRules` pure functions + worked-example test: the 12-stack on an enemy farm 3 road hops from a depot with stock 80 gives upkeep 36, local 6, delivered ≈ 21.9, shortfall ≈ 8.1, delta ≈ −3.4; the two 6-stacks give delta ≈ −1.3 each. **Land this task first; WS-D's `proj` waits on it.**
2. `Pathing.shortest` (Dijkstra over edges by movement cost; hostile-presence interior sites excluded) and `nearest_depot` (hop count by loss-weighted cost). Tests: road preferred over trail; a raider on the only road makes the depot unreachable; peace removes the block.
3. `MovementPhase`: walk `stack.path` with `points_for`; stop on entering a site with hostile presence (leave the encounter to WS-C); auto-merge friendly stacks on the same site unless `hold_separate`; merged stack keeps the larger `supply` weighted by size. Tests: 4 points walks 4 road edges or 2 trail edges; stacks above 8 walk 3.
4. `SupplyPhase`: farms feed nearest depot within 3 hops (`Yields.supply`), depot cap; per-stack report in App B order; depot drain; desertion; pillage (`Site.pillaged_until` and the per-kind effects) when foraging a hostile site. Tests: "a 12-stack foraging one farm visibly starves; the same regiments split across four farms hold steady" (acceptance); depot dry in 3 turns in the worked example; raider on the road raises the shortfall the same turn.
5. `OccupationPhase`: site `garrison_nation` = holding stack's nation when `order == "hold"`; region owner = majority of villages + market. Tests: passing through changes nothing; garrisoning 2 of 3 villages flips the region.
6. `Orders`: detach (one click + count), build depot (40 Coin, 2 turns, 1 per region), hold. Tests for each.
7. `supply_layer.gd`: stack marker gets `supply%`, rising/falling arrow, hops; hover breakdown text from `supply_report`; buttons Detach (count + target), Hold, Build depot. Depot fill bars and severed-edge dashes already live in `graph_layer.gd`, **which you own after Phase 0** — extend it in place rather than duplicating either into a second layer, and read capacity through `Yields.depot_capacity`. Scenario "The March" (App B #1) as a `PrototypeMap` variant with a `scenario` key.
8. `logistics/scripted_enemy.gd`: App B's two minimal enemy behaviours, run from `AiPhase` for any nation whose `weights` has `"scripted": "marcher" | "raider"` (WS-D's real AI ignores those nations). **Marcher**: one 10–14 stack follows the road toward the player's depot, forages along the way, splits in two when supply < 40. **Raider**: a 3-regiment cavalry stack targets the edge between the player's depot and largest stack, or the nearest caravan (`world.routes` if WS-B has merged), whichever is closer; flees any stack > 3. Scenario "The Siege" (App B #3). Tests: the marcher splits at < 40; the raider leaves when a 4-stack approaches.
**Acceptance:** App B acceptance bullets 1–3, 5 and 6.

### WS-B — Trade & raiding (Appendix B, milestones 4–5)

**Owns:** `game/scripts/sim/trade/` (`trade_route.gd`, `caravan.gd`, `trade_rules.gd`), `phases/trade_phase.gd`, `ui/layers/trade_layer.gd`, `tests/test_trade.gd`.
**Adds to shared classes:** `World.routes` is already declared (typed `Array` of `TradeRoute`); `GameConfig.trade` (dispatch every 2 turns, max 6 routes / 10 for trading nation, route length ≤ 8, base 12 Coin, ×1.5 lacking good, ×1.5 market end, access 4 turns, capture delay 2 turns, caravan speed road 2 / river 3 / trail 1 / mountain 0, escort threshold 2 regiments).
**Consumes:** Phase 0 (`World.is_severed`, `hostile_presence`, `Nation.access_tags`). Uses `Pathing.shortest` from WS-A **if merged**, else its own BFS by edge count in `trade_rules.gd` (swap later; keep the call in one function).
**Produces:** `TradeRoute { id, nation_id, from_site, to_site, path: Array[int], next_dispatch, active, escort_stack_id }`, `Caravan { route_id, site_index, coin, tag }`, `TradeOrders.new_route(world, nation, town, endpoint) -> TradeRoute`, `TradeOrders.cancel_route(world, route)`, `TradeOrders.escort(world, stack, route)`, `TradeRules.route_value(world, nation, route) -> float` (WS-D reads this), `TradeRules.caravans_on(world, edge) -> Array`.
**Tasks:** 1. Route creation and validation (market town endpoint, ≤ 8 edges, slot cap). 2. `TradePhase` dispatch + movement at edge speed + arrival income and access tags (refresh expiry). 3. Capture on hostile presence at end of turn; escort rule; delayed dispatch; market town occupied → routes cut. 4. `trade_layer.gd`: routes drawn faintly, caravans as moving tokens, buttons New route / Cancel / Escort. 5. Scenario "The Corridor" (App B #2): uses WS-A's scripted raider once merged; until then the test places a hostile 3-stack on the corridor by hand. **Acceptance:** App B bullet 4 ("a caravan with no escort dies to a raider; with an escort it arrives").

### WS-C — Battle bridge and threshold auto-resolve (Design §4, App B "battle stub")

**Owns:** `game/scripts/sim/battle/` (`battle_bridge.gd`, `auto_resolve.gd`), `phases/engagement_phase.gd`, `ui/battle_view.gd` (extracted from `game_root.gd` drawing/input for battles; `game_root.gd` keeps working by delegating to it), `tests/test_battle_bridge.gd`.
**Adds to shared classes:** `World.pending_battles: Array[Dictionary]` (`{attacker: Stack, defender: Stack, site_id, from_site}`), `Stack.retreat_to: int` (set by result), `GameConfig.battle_bridge` (auto-resolve ratio 3.0, hidden-failure chance 0.05, attrition on auto-resolve 10%, rout survival health 50%).
**Consumes:** Phase 0; `Scenarios.start_battle`, `BattleSim`; `Pathing.nearest_depot` from WS-A for the loser's retreat hop (fallback: any adjacent friendly site).
**Produces:**
```gdscript
EngagementPhase.run(world)   # fills world.pending_battles for stacks that stopped on a hostile site
BattleBridge.to_armies(world, terrain, attacker, defender) -> Array[Army]   # Stack → Army (pos = site.pos, facing along from_site→site)
BattleBridge.start(world, terrain, pending: Dictionary, crop := Vector2.ZERO) -> BattleSim
BattleBridge.apply_result(world, sim, pending) -> Dictionary   # destroyed blocks → regiments removed; routed/withdrew survive; loser retreats one hop toward its depot
AutoResolve.ratio(a: Stack, b: Stack) -> float                # strength ratio, shown in UI
AutoResolve.trivial(world, a, b) -> bool                       # ratio ≥ config, may hide-fail
AutoResolve.resolve(world, pending) -> Dictionary              # deterministic via world.rng; the "battle stub" for AI headless sims
```
**Tasks:** 1. `EngagementPhase` from movement stops (needs WS-A's "stop on hostile site" — until it merges, test by placing stacks directly). 2. `to_armies` + `start` (defender = the stack that did not move; deployment via existing `Scenarios.deploy`). 3. `apply_result` and retreat. 4. `AutoResolve` with visible ratio and rare hidden failure. 5. Extract `battle_view.gd`; `campaign_root` switches to it when `pending_battles` is non-empty and the player is involved; AI-vs-AI battles use `AutoResolve.resolve`. 6. Result screen reuse. **Acceptance:** "Parking on the hill before a battle visibly changes the outcome" now holds from the campaign graph (a test fights the East Hill feature site from the hill and from the plain, same rosters); auto-resolve ratio shown; the 87 combat checks unchanged.

### WS-D — Nation AI (Appendix C, milestones 1–5 and the headless harness)

**Owns:** `game/scripts/sim/ai/` (`world_inputs.gd`, `goal.gd`, `strategic.gd`, `planner.gd`, `task.gd`, `tactical.gd`, `headless_sim.gd`), `phases/ai_phase.gd`, `ui/layers/ai_debug_layer.gd`, `tests/test_ai.gd`, `tests/test_headless_perf.gd`.
**Adds to shared classes:** `Nation.intents: Array[Dictionary]` (`{goalType, target, turnChosen, expectedTurn}`), `Nation.goals_last_turn`, `Stack.task: Dictionary`, `GameConfig.ai` (maxGoals 4, hysteresis +0.15 / −0.3 for 3 turns, λ 2, thresholds from App C, the four starting weight vectors).
**Consumes:** WS-A `SupplyRules`, `Pathing`, `Orders`; WS-C `AutoResolve.resolve`; WS-B `TradeRules.route_value` (optional until merged: `EscortRoute`/`NewRoute` goals return 0 when `world.routes` is empty).
**Produces:** `WorldInputs.compute(world) -> Dictionary {threat[nation][site][k], exposure, edge_value[nation][edge], region_value[nation][region]}`, `WorldInputs.proj(world, stack, path: Array[int], n: int) -> float` (cached per (stack.id, path) per turn), `Strategic.goals(world, nation, inputs) -> Array[Goal]`, `Planner.plan(world, nation, goals, inputs) -> Array[Task]`, `Tactical.act(world, stack, inputs)`, `HeadlessSim.simulate(map_data, weights: Array[Dictionary], turns: int, seed) -> Dictionary` (per-nation regions per era, battles fought/won, avg supply, caravans lost, `beats: Dictionary` name → bool).
**Task order:** 1. threat map, edge value, region value, reachability + hand-checked unit tests (can start day 1). 2. `HeadlessSim.simulate` loop and the perf test (8 nations × 100 turns < 5 s; fails loudly if GDScript can't reach it — see Risks). 3. `proj` (after WS-A task 1). 4. Strategic layer: FeedArmies, HoldDepot, HoldRegion, TakeRegion, RaidEdge, Garrison, normalisation, hysteresis, intents. 5. Planner: supply-aware Dijkstra, Mass/Forage/merge, task binding, replanning. 6. Tactical tree + raider variant. 7. EscortRoute, BuildDepot, NewRoute, SeekPeace/Shop stubs. 8. `ai_debug_layer.gd`: goals with scores, active tactical rule per stack, planned paths and Mass points for one selected nation. **Acceptance:** App C bullets 1–4 and 6.

### WS-E — Influence, diplomacy, shop (Design §5)

**Owns:** `game/scripts/sim/diplomacy/` (`influence_rules.gd`, `diplomacy.gd`, `shop.gd`, `shop_catalogue.gd`), `phases/influence_phase.gd`, `ui/layers/diplomacy_layer.gd` (a side panel: relations, actions with prices, shop), `tests/test_diplomacy.gd`.
**Adds to shared classes:** `Nation.legitimacy: float`, `Nation.shop_stock: Array`, `Nation.treaties: Dictionary` (border closure, embargo, tribute with expiry turns), `GameConfig.influence` (income per Social region, capital loss penalty, inheritance fraction ⅓, action base prices, crisis-fired multiplier, tier weights).
**Consumes:** Phase 0 (`Region.posture`, `World.set_relation`, `era_listeners`). WS-F's unrest and WS-H's "crisis fired" flag are read through `Nation` fields that default to zero, so E ships without them.
**Produces:** `Diplomacy.actions(world, from, to) -> Array[{kind, cost, allowed}]` for peace, tribute, border closure, embargo, coalition pressure, marriage (marriage delegates to WS-G when present), `Diplomacy.perform(world, from, to, kind) -> bool`, `Shop.stock(world, nation) -> Array[Item]`, `Shop.buy(world, nation, item) -> bool`, `Shop.refresh(world, nation, reason)` (era edge or crisis), `InfluenceRules.income(world, nation) -> float`. Staples implemented (consolidate a region → WS-M hook, flip posture in one turn, buy a season of peace, restock a depot, retire a trait → WS-G hook, mercenary regiment). Mid/rare tiers as catalogue entries with `apply: Callable`.
**Tasks:** 1. Income and use-it-or-lose-it at era edges. 2. Actions with pricing by target strength and disposition; AI parity (`InfluencePhase` spends for AI nations on the cheapest positive-value action, a stub WS-D's `SeekPeace` calls). 3. Shop tiers and refresh. 4. Panel UI. **Acceptance:** peace bought is reflected in `World.relation`; embargo cuts a route via `TradeRoute.active`; unspent Influence drops to ⅓ across an era edge; a neighbour's purchases appear in `Nation.intents`-style tells.

### WS-F — Society: posture, culture, religion, unrest (Design §2, §3)

**Owns:** `game/scripts/sim/society/` (`posture.gd`, `culture.gd`, `religion.gd`, `unrest.gd`), `phases/economy_phase.gd`, `world/yields.gd` (extends the Phase 0 functions), `ui/layers/society_layer.gd` (posture pickers, culture/faith minority-share glyphs — the design's open question on display), `tests/test_society.gd`.
**Adds to shared classes:** `Region.culture: String`, `Region.culture_minority: float`, `Region.faith: String`, `Region.faith_minority: float`, `Region.unrest: float`, `Region.levies: float`, `Nation.home_culture: String`, `Nation.faith: String`, `Nation.influence_modifier: float` (default 1.0; WS-E multiplies income by it), `Nation.traditions: Array[String]` (WS-H fills it), `GameConfig.society` (posture ±25% yields; Military drains neighbours; foreign-culture penalties; faith spread rate along trade edges and Social posture; unrest thresholds; faith roster `STATE_1..4`, `OLD_FAITH`, `NEW_FAITH`).
**Consumes:** Phase 0; reads `world.routes` (WS-B) for faith spread if present.
**Produces:** `Yields.*` now posture/culture/unrest-aware; `Posture.set(world, region, posture)`; `EconomyPhase` credits coin from `Yields.coin`, accrues levies, drifts unrest, spreads faith; `Unrest.recruitment_pool(world, region) -> float` (WS-H rebellion reads it).
**Tasks:** 1. Posture multipliers into `Yields` + tests for the ±25%. 2. Coin and levies each turn. 3. Culture penalties (foreign region: reduced yields, no levies, unrest). 4. Faith spread along trade edges and Social posture; mismatch → unrest and lost Influence (via a `Nation.influence_modifier` E reads). 5. Layer UI. **Acceptance:** same region under three postures yields three different numbers; a foreign-culture conquest yields less and levies nothing; faith share in a region on a trade route trends toward the sender's faith over 10 turns.

### WS-G — Characters and traits (Design §6)

**Owns:** `game/scripts/sim/characters/` (`character.gd`, `traits.gd`, `trait_picker.gd`, `family.gd`), `phases/character_phase.gd`, `ui/layers/court_layer.gd` (roster panel, assignment, pick-3 dialog — a `panel()` rather than map drawing), `tests/test_characters.gd`. Appends its roster setup to `WorldSetup.hooks()`.
**Adds to shared classes:** `World.characters` is declared; `Nation.ruler_id`, `Nation.heir_id`, `Region.governor_id`, `Stack.leader_id` exists — G makes `Stack.quality` derive from the leader (`Traits.stack_quality(world, stack)`), `GameConfig.characters` (5–12 per run, ~30 traits, −50% quality without a leader, age bands per era).
**Consumes:** Phase 0 `era_listeners` (ageing). Battle-call modifiers are exposed as multipliers WS-C reads via `Traits.battle_mod(world, stack, key)`; posture yield modifiers via `Traits.yield_mod(world, region)` which WS-F's `Yields` calls if a governor is set.
**Produces:** `Character { id, name, nation_id, age_band, traits: Array[String], slot, history: Dictionary }`, `Traits.catalogue()` (30 entries, each `{name, kind: martial|civil|court, effects: Dictionary, invert_when_elderly}`), `TraitPicker.pool(world, character) -> Array[String]` (3, weighted by `history`), `TraitPicker.force(world, character, trait)`, `Family.marry(world, nation, other_nation) -> Character`, `Family.adopt(world, nation, general) -> void`, `Traits.retire(character, trait)` (the shop staple).
**Tasks:** 1. Character + roster + slots. 2. Trait catalogue and effect hooks. 3. Pick-3 seeded by history with visible weighting. 4. Forced bad traits on triggers (sack, flee a winnable fight, idle era). 5. Ageing at era edges with elderly inversion. 6. Marriage/adoption. 7. Court panel. **Acceptance:** a general who won two fights and retreated once gets a pool containing Confident/Veteran/Cautious; an idle character for a full era gets a forced negative trait; an elderly Bold ruler reads as Stubborn.

### WS-J — Map content: the authored world (Design §8)

**Owns:** `game/data/world_map.gd` (40–60 regions, 6–8 nations, wild zones, nodes, cultures, faiths, starting stacks and postures), `game/data/map/biome.txt` + `height.txt` + `roads.json` (terrain art moved out of `terrain.gd` into data files), `game/scripts/sim/terrain_loader.gd`, `tests/test_world_map.gd`.
**Adds to shared classes:** `Terrain` gains `static func from_files(dir: String) -> Terrain` and instance `cols/rows` replacing the constants **behind the same API** (`COLS`/`ROWS`/`SIZE` become instance vars with the same names; `Campaign._build_grid`, `game_root.gd` and the combat tests must still pass — run them). `Region.polygon: PackedVector2Array` for rendering.
**Consumes:** Phase 0 map format; WS-F field names for culture/faith (coordinate the string roster: `STATE_1..4`, `OLD_FAITH`, `NEW_FAITH`).
**Tasks:** 1. Terrain from data files, grid enlarged (target ~240×160 cells at 20 units = 4800×3200 world units so a region is ~10 army-widths). 2. The prototype 60×40 art stays as `map/prototype/` so all existing tests still load it by default. 3. Author the world map: the ailing empire (grain + iron, no horses), the warlord (horses), the hill folk (hills, no depots), the trading empire (coast, sea lanes as `river` edges tagged `sea`), 2–3 clients, wild zones. 4. Well-formedness tests (same as Task 0.3 generalised: counts, connectivity, every nation has a depot and a market, every node type present, no site on water). 5. Region polygons for the graph layer. **Acceptance:** `World.from_map(WorldMap.data())` loads; the campaign renders it; combat prototype tests still pass on the prototype terrain.

### WS-H — Crises, clocks, eras, traditions (Design §5, §7) — Phase 2

**Owns:** `game/scripts/sim/crises/` (`crisis.gd`, `crisis_catalogue.gd`, `clocks.gd`, `traditions.gd`, `relic_pick.gd`), `phases/crisis_phase.gd`, `ui/layers/crisis_layer.gd` (announcement, tells, clocks, resolution choice, era-edge two-pick), `tests/test_crises.gd`.
**Adds to shared classes:** `World.crises` is declared; `Nation.crisis_fired_turn: int` (E reads for pricing), `Nation.crisis_override: Dictionary` (K reads), `GameConfig.crises` (eligibility thresholds, clock rates, tier gating).
**Consumes:** WS-E (Influence sinks, shop refresh on fire), WS-G (ruler traits, heirs), WS-F (`Unrest.recruitment_pool`, faith majority), WS-K (`Nation.crisis_override` consumed by the AI), WS-D intents for tells.
**Produces:** `Crisis { id, actor, tier, trigger: Callable(world)->bool, announce: String, intent: Dictionary, tells: Array, clocks: Array[Clock], resolutions: Array[{name, verb, available: Callable, apply: Callable, legacy: Array}] , ends_when: Callable }`; `CrisisPhase`: evaluate eligibility (one guaranteed nation crisis per era by the last third, tuned eligibility), fire, tick clocks, resolve; `Traditions.catalogue()` and `RelicPick.offer(world, nation, resolution) -> Array[3]`; the era-edge two-pick (relic, then ruler trait via WS-G).
**Tasks:** 1. Crisis object + phase + clocks (generic). 2. Tier-1 catalogue: Rebellion, Plague/Famine, Succession, Crisis of faith, Claimant rival, each as data filling the five slots. 3. Traditions + relic picks with sides. 4. Prevented beats mutate (a delayed/redirected variant instead of vanishing). 5. UI. **Acceptance:** with the prototype map and fixed seeds, the rebellion fires when unrest crosses the threshold and its stack grows per village passed; each tier-1 crisis has ≥ 2 reachable resolutions in a scripted test; a fired crisis makes E's actions against that actor cost more.

### WS-I — Government, succession, client states (Design §5) — Phase 2

**Owns:** `game/scripts/sim/government/` (`government.gd`, `succession.gd`, `client_state.gd`, `court.gd`), `phases/government_phase.gd`, `tests/test_government.gd`, `ui/layers/government_layer.gd`.
**Adds to shared classes:** `Nation.government: enum {CENTRALIZED, PROVINCIAL, LEAGUE, WARBAND}`, `Nation.suzerain_id`, `Nation.court: Dictionary` (client factions loyalist/independence/regional), `Region.province_id` (WS-M sets), `GameConfig.government` (soft caps 6/10/∞/veteran-share, tribute rates).
**Consumes:** WS-G (claimants, governors, veterans via `Character.history`), WS-F (culture for client courts), WS-E (Influence votes), WS-H (`Revolution` trigger predicate and `Succession` crisis consume `Succession.count(world, nation)`).
**Produces:** `Government.constituencies(world, nation) -> Array`, `Government.over_cap(world, nation) -> bool` (Revolution trigger), `Succession.rule(nation) -> String`, `Succession.count(world, nation) -> Dictionary` (claimant id → backing), `Succession.resolve(world, nation) -> Dictionary` at era edges (choice vs result), `ClientState.tribute(world, client)` routed as Coin or Supply up the network, `ClientState.lean(world, client)` court drift each turn, `ClientState.declare_war_allowed`.
**Acceptance:** Centralized past 6 provinces reports `over_cap`; Provincial succession counts provinces per claimant; a client that gets no answer to a raid leans toward independence; a client can drag the suzerain into a war (the suzerain's relation flips).

### WS-K — Crisis brain and headless tuning (Appendix C, milestones 6–7) — Phase 2

**Owns:** `game/scripts/sim/ai/crisis_brain.gd`, `game/scripts/sim/ai/tuner.gd`, `game/tools/tune.gd` (a `SceneTree` script: `godot --headless --script tools/tune.gd -- warlord 500`), `tests/test_crisis_brain.gd`.
**Consumes:** WS-D (weights, forced goal through the same planner), WS-H (`Nation.crisis_override` shape: `{intent, weightOverride, forcedGoalScore, absorb, endsWhen}`), WS-A (`absorb` merges village levies into the stack on region capture).
**Produces:** `CrisisBrain.apply(world, nation)` inside `AiPhase` before scoring; `Tuner.hill_climb(map, nation, beat, target_rate, runs)`; beat predicates catalogue (`warlordHoldsClientStateBy(30)` etc.).
**Acceptance:** App C bullets 5 and 6: warlord takes the target in 60–80% of 500 runs; below 30% with a scripted ford garrison; 8 nations × 100 turns in under 5 s.

### WS-L — Player automation verbs and overlays (Appendix C "Player-side reuse") — Phase 2

**Owns:** `ui/layers/automation_layer.gd`, `ui/layers/threat_layer.gd`, `ui/layers/tells_layer.gd`, `tests/test_automation.gd`.
**Consumes:** WS-D `Planner` (run for the player's nation on demand), `WorldInputs.threat`, `Nation.intents`.
**Produces:** buttons **Forage here**, **Escort this route**, **Mass at (site, turn)**; the threat-at-k=2 shading overlay; delayed tells (muster marker 1–2 turns before the stack arrives).
**Acceptance:** "Forage here" on a 12-stack next to four farms yields four 3-stacks each on a farm; a Mass order reassembles them the turn before T.

### WS-M — Decision density: consolidation and auto-resolve UI (Design §1) — Phase 2

**Owns:** `game/scripts/sim/world/provinces.gd`, `ui/layers/province_layer.gd`, `tests/test_provinces.gd`, `tests/test_decision_density.gd`.
**Adds to shared classes:** `Region.province_id`, `World.provinces: Array`.
**Consumes:** WS-A/WS-F (posture at province level), WS-C (`AutoResolve.trivial` and the ratio display), WS-E (the "consolidate a region" staple), WS-I (merging removes a constituency).
**Produces:** `Provinces.merge(world, nation, region_ids) -> Province`, posture applied per province, frontier grouping; the auto-resolve confirmation UI showing the ratio; a headless audit that counts player decision points per turn in era 1 vs era 3 on a scripted run and asserts they stay within ×1.5 (the doc's open question, made a test).

---

## 4. Phase 3 — Integration (outline)

1. **Run structure**: `RunState` (seat, era, crisis draw, unlock flags), start-of-run seat picker, era-edge flow (crisis resolution → relic → ruler trait → posture reshuffle → Influence ⅓), finale reveal from tier-1/2 legacies.
2. **Nation archetypes and unlocks**: the four archetypes as weight vectors + starting postures/traditions; unlocks keyed to world state at run end.
3. **Tier-2 and tier-3 crises**: Migration/Horde, Overextension, Court schism, Divine reckoning, Revolution (uses WS-I's trigger), hegemon + pretender finale.
4. **Mobile pass on the campaign shell**: port the touch/gesture model from `game_root.gd` into `MapView`; tap-equivalent for every hover; 44 px buttons.
5. **Balance via headless sim**: target beat-fire rates 50–80% for signature beats; average AI army supply > 50.
6. **README and design-doc sync**: resolve the §10 open questions that the prototypes answered (hop loss, depot cap, retreat cost, auto-resolve ratio) in the doc.

---

## 5. Risks and decisions to carry into every workstream

- **GDScript speed for the AI budget.** 200 turns/s × 8 nations in GDScript is unproven. WS-D task 2 measures it on day 1; if it misses by more than 3×, the fallback is to move `WorldInputs` + `Planner` into a C# assembly or GDExtension behind the same static API. Decide from the measurement, not in advance.
- **Two campaign models coexist.** The combat prototype's free-movement `Campaign` stays only for its three scenarios. The game uses the site graph. Do not extend `campaign.gd`.
- **Supply scale.** Campaign `Stack.supply` is 0..100 (Appendix B); battle `Army.supply` is 0..1 (Appendix A). The bridge divides by 100. Never mix them.
- **Presence severs, nothing else does.** `World.is_severed` and `hostile_presence` are the one definition of cutting; no workstream keeps its own "cut" flag.
- **Ids are indices.** Sites, regions, nations are arrays indexed by id; stacks have unique ids but are searched (there are few). Keep it that way for the headless loop.
- **Config merges.** Each workstream appends one `static var` dictionary to `game_config.gd`. Never edit another workstream's dictionary; reference its keys.
- **Terrain resize (WS-J) touches the combat prototype.** It is the one Phase 1 workstream that edits shipped code; it runs the full combat suite before and after.
- **Open questions in the design doc (§10)** are not blockers. Each workstream picks the Appendix number where one exists and writes the choice into its config dict with a comment; Phase 3 syncs the doc.

---

## 6. Suggested staffing for maximum parallelism

| Slot | Phase 1 (after Phase 0 merges) | Phase 2 |
| --- | --- | --- |
| 1 | WS-A (land task 1 first, same day) → continue A | WS-M |
| 2 | WS-C | WS-L |
| 3 | WS-D tasks 1–2, then 3+ as A1 lands | WS-D part 2 → WS-K |
| 4 | WS-B | WS-H |
| 5 | WS-E | WS-H (catalogue) |
| 6 | WS-F | WS-I |
| 7 | WS-G | WS-I |
| 8 | WS-J | Phase 3 run structure |

Merge cadence: each workstream opens a PR against `main` per task group; the PR-preview workflow already publishes a playable build per PR, so a stream's scenario is reviewable in the browser without pulling. CI runs every suite, so a stream cannot break another's tests silently.
