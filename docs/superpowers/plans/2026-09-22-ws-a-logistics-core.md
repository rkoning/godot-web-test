# WS-A Logistics Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make supply a network the player can read on every army: hop-based depot feed with stock, foraging that pillages, superlinear upkeep that punishes doomstacks, graph movement with detach/merge/hold, occupation by garrison, two scripted enemies, and Appendix B's "The March" and "The Siege" scenarios, all headless-tested and drawn on the campaign map.

**Architecture:** Pure rule functions (`SupplyRules`, `Pathing`, `Holdings`) with no world mutation, applied by three phase files WS-A owns (`MovementPhase`, `SupplyPhase`, `OccupationPhase`), driven by `Orders` (the only way anything writes a stack's route or order). A `WorldSetup` hook gives depots their opening stock. Two map layers WS-A owns (`stacks_layer.gd`, new `supply_layer.gd`) render and issue orders; the shell gains one additive registry for scenarios.

**Tech Stack:** Godot 4.5 GDScript, headless test runner (`tests/run_tests.gd`, one suite per file), Phase 0 foundation on branch `phase-0-foundation` (or `main` once merged).

## Global Constraints

- Every simulation class is `RefCounted`, rendering-free, deterministic; the only RNG is `World.rng` (WS-A uses none).
- Every tunable number lives in `game/scripts/sim/game_config.gd` as a `static var` dictionary (`GameConfig.logistics`, added here); logic never hardcodes a number.
- Campaign supply is 0..100. `Stack.strength()` already applies `GameConfig.supply_multiplier(supply / 100.0)`; do not redefine it.
- Presence severs, nothing else does: `World.hostile_presence` / `World.is_severed` are the one definition. Pathing and supply refuse to pass *through* a site with hostile presence; the destination may be hostile.
- Frozen classes may only gain the fields this plan lists: `Stack.hunger: int`, `Site.depot_ready_turn: int`. Nothing else in `game/scripts/sim/world/` changes except the one-line hook registration in `world_setup.gd`.
- Phase order is fixed in `TurnResolver.phases()` (AiPhase, MovementPhase, EngagementPhase, OccupationPhase, SupplyPhase, TradePhase, EconomyPhase, InfluencePhase, CharacterPhase, GovernmentPhase, CrisisPhase, EraPhase). WS-A fills its three phase files in place and never edits the resolver.
- WS-A owns: `game/scripts/sim/logistics/`, `phases/movement_phase.gd`, `phases/occupation_phase.gd`, `phases/supply_phase.gd`, `ui/layers/graph_layer.gd`, `ui/layers/stacks_layer.gd`, `ui/layers/supply_layer.gd`, `tests/test_supply.gd`, `tests/test_movement.gd`, `tests/test_logistics_shell.gd`. Shared files it touches, each with the exact edit given in this plan: `game_config.gd` (append one dict), `world_setup.gd` (one hook line), `campaign_root.gd` (scenario registry, Task 10), `stack.gd` and `site.gd` (one field each), `README.md`.
- Appendix B numbers are the starting values and are copied verbatim into `GameConfig.logistics` (Task 1). Worked example must reproduce: 12 regiments on an enemy farm 3 road hops from a depot with stock 80 → upkeep 36, local 6, delivered ≈ 21.9, shortfall ≈ 8.1, level −3.4/turn, depot −30/turn; two 6-stacks → level ≈ −1.4/turn each, depot −12/turn.
- Acceptance (Appendix B): a 12-stack foraging one farm visibly starves while the same regiments split across four farms hold steady; a raider on a road between depot and army raises that army's shortfall the same turn and the edge shows severed; the supply breakdown on any army reads in under five seconds; "The Siege" is winnable without fighting the 14-stack at full strength; every number lives in one config.
- Tests: `cd game && godot --headless --script tests/run_tests.gd -- supply` (one suite) or no argument (all). CI runs Godot 4.5-stable; use no API newer than 4.5. Locally the binary is `K:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe`. New `class_name` scripts need one `godot --headless --path game --import` before the runner sees them; stage the generated `.gd.uid` files.
- Git: never commit or push; stage with `git add`; never stage `game/icon.svg.import`. The combat suite must stay at 87 checks.

---

## File map

| File | Responsibility |
| --- | --- |
| `game/scripts/sim/logistics/holdings.gd` | Who holds a site (garrison, else region owner); friendly / hostile ground; depot readiness. |
| `game/scripts/sim/logistics/supply_rules.gd` | Pure arithmetic: upkeep, local feed, hop loss, delivery, level delta, move cost/points, and `report()`. |
| `game/scripts/sim/logistics/pathing.gd` | Dijkstra over the site graph in three cost modes; `shortest`, `nearest_depot`. |
| `game/scripts/sim/logistics/movement.gd` | Walk one stack's path; merge friendly stacks on a site. |
| `game/scripts/sim/logistics/orders.gd` | `move`, `hold`, `detach`, `build_depot`. The only writer of `Stack.path`/`order`. |
| `game/scripts/sim/logistics/logistics_setup.gd` | `WorldSetup` hook: opening depot stock. |
| `game/scripts/sim/logistics/scripted_enemy.gd` | Appendix B's Marcher and Raider, keyed by `Nation.weights["scripted"]`. |
| `game/scripts/sim/logistics/logistics_scenarios.gd` | "The March" and "The Siege": map data variants, `world()`, `status()`. |
| `game/scripts/sim/phases/movement_phase.gd` | Scripted orders → walk every stack → merge. |
| `game/scripts/sim/phases/supply_phase.gd` | Depot refill → per-stack feed, drain, pillage → desertion. |
| `game/scripts/sim/phases/occupation_phase.gd` | Garrisons → site holders → region owners. |
| `game/scripts/ui/layers/stacks_layer.gd` | (owned) Orders UI: select, move anywhere reachable, Hold, Detach (count panel), Build depot; supply tooltip. |
| `game/scripts/ui/layers/supply_layer.gd` | Drawing only: level arrows, hops, selected stack's depot route, depots under construction. |
| `game/scripts/ui/campaign_root.gd` | + `SCENARIOS` registry and a picker (Task 10, exact edit). |
| `game/tests/test_supply.gd` | Rules, supply phase, depots, pillage, desertion, occupation, orders. |
| `game/tests/test_movement.gd` | Pathing, movement, merge, scripted enemies, scenarios. |
| `game/tests/test_logistics_shell.gd` | Layer registered, buttons, tooltip format, scenario picker. |

---

### Task 1: Config, Holdings, and the pure supply rules

**Files:**
- Modify: `game/scripts/sim/game_config.gd` (append after `sites`)
- Modify: `game/scripts/sim/world/site.gd` (one field), `game/scripts/sim/world/stack.gd` (one field)
- Create: `game/scripts/sim/logistics/holdings.gd`, `game/scripts/sim/logistics/supply_rules.gd`
- Create: `game/tests/test_supply.gd`

**Interfaces produced:**
```gdscript
Holdings.site_owner(world, site) -> int            # garrison_nation if set, else region owner, -1 = nobody
Holdings.is_friendly(world, site, nation_id) -> bool
Holdings.is_hostile_ground(world, site, nation_id) -> bool
Holdings.depot_ready(world, site) -> bool
Holdings.is_friendly_depot(world, site, nation_id) -> bool
SupplyRules.upkeep(regiments: int) -> float
SupplyRules.local_feed(world, site, regiments: int) -> float
SupplyRules.local_from_stock(world, site) -> bool   # true when the site is a ready depot (feed comes out of stock)
SupplyRules.hop_loss(kind: int) -> float
SupplyRules.delivery_factor(edges: Array) -> float
SupplyRules.delivered(requested: float, edges: Array) -> float
SupplyRules.level_delta(shortfall: float, regiments: int) -> float
SupplyRules.move_cost(kind: int) -> int
SupplyRules.is_raider(stack) -> bool
SupplyRules.move_points(stack) -> int
```

- [ ] **Step 1: Write the failing tests**

`game/tests/test_supply.gd`:
```gdscript
extends RefCounted

## WS-A: supply as a network. Rules first (pure functions, hand-checked
## numbers from Appendix B), then the phases that apply them.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_upkeep_is_superlinear()
	_test_hop_loss_and_delivery()
	_test_level_delta()
	_test_move_points()
	_test_holdings()
	_test_local_feed()
	# Later tasks append their tests here.
	_test_report_worked_example()
	_test_depots_refill_from_farms_in_reach()
	_test_one_farm_starves_four_farms_hold()
	_test_raider_on_the_road_raises_shortfall()
	_test_foraging_pillages()
	_test_desertion()
	_test_occupation()
	_test_orders()

# ------------------------------------------------------------------ fixtures

## A small two-nation map: a road from the home depot east into enemy land,
## a trail loop, one river edge, and four farms so a 12-stack can disperse.
##
##   Depot(0) -- Village(1) -- Crossroads(2) -- EnemyFarm(3) -- FoeVillage(6) -- FoeMarket(7) -- FourthFarm(8)
##                  \ trail      \ trail            \ river
##                  HomeFarm(4) --/                 FarFarm(5)
func _map() -> Dictionary:
	return {
		"nations": [
			{"id": 0, "name": "Home", "player": true, "coin": 60},
			{"id": 1, "name": "Foe", "player": false, "coin": 60},
		],
		"relations": [{"a": 0, "b": 1, "state": "war"}],
		"regions": [{"id": 0, "name": "Homeland", "owner": 0}, {"id": 1, "name": "Foeland", "owner": 1}],
		"sites": [
			{"id": 0, "region": 0, "kind": "depot", "pos": [100, 100], "name": "Depot"},
			{"id": 1, "region": 0, "kind": "village", "pos": [200, 100], "name": "Village"},
			{"id": 2, "region": 0, "kind": "feature", "pos": [300, 100], "name": "Crossroads"},
			{"id": 3, "region": 1, "kind": "farm", "pos": [400, 100], "name": "Enemy Farm"},
			{"id": 4, "region": 0, "kind": "farm", "pos": [200, 200], "name": "Home Farm"},
			{"id": 5, "region": 1, "kind": "farm", "pos": [400, 200], "name": "Far Farm"},
			{"id": 6, "region": 1, "kind": "village", "pos": [500, 100], "name": "Foe Village"},
			{"id": 7, "region": 1, "kind": "market", "pos": [500, 200], "name": "Foe Market"},
			{"id": 8, "region": 1, "kind": "farm", "pos": [600, 200], "name": "Fourth Farm"},
		],
		"edges": [
			{"a": 0, "b": 1}, {"a": 1, "b": 2}, {"a": 2, "b": 3},
			{"a": 1, "b": 4, "kind": "trail"}, {"a": 2, "b": 4, "kind": "trail"},
			{"a": 3, "b": 5, "kind": "river"}, {"a": 3, "b": 6}, {"a": 6, "b": 7}, {"a": 7, "b": 8},
		],
	}

func _world() -> World:
	var w := World.from_map(_map(), 1)
	w.graph.site(0).stock = 0.0        # tests set stock explicitly
	return w

func _inf(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(GameConfig.Role.INFANTRY)
	return out

# --------------------------------------------------------------------- rules

func _test_upkeep_is_superlinear() -> void:
	t.near("4 regiments eat 8", SupplyRules.upkeep(4), 8.0, 0.001)
	t.near("8 regiments eat 16 (the cap is exclusive)", SupplyRules.upkeep(8), 16.0, 0.001)
	t.near("9 regiments eat 27 (×1.5)", SupplyRules.upkeep(9), 27.0, 0.001)
	t.near("12 regiments eat 36", SupplyRules.upkeep(12), 36.0, 0.001)
	t.near("13 regiments eat 52 (×2)", SupplyRules.upkeep(13), 52.0, 0.001)

func _test_hop_loss_and_delivery() -> void:
	var w := _world()
	t.near("road loses 10%", SupplyRules.hop_loss(Edge.Kind.ROAD), 0.10, 0.0001)
	t.near("river loses 5%", SupplyRules.hop_loss(Edge.Kind.RIVER), 0.05, 0.0001)
	t.near("trail loses 20%", SupplyRules.hop_loss(Edge.Kind.TRAIL), 0.20, 0.0001)
	t.near("mountain loses 35%", SupplyRules.hop_loss(Edge.Kind.MOUNTAIN), 0.35, 0.0001)
	var roads: Array = [w.graph.edges[0], w.graph.edges[1], w.graph.edges[2]]
	t.near("three road hops deliver 72.9%", SupplyRules.delivery_factor(roads), 0.729, 0.0001)
	t.near("30 requested over three roads arrives as 21.87", SupplyRules.delivered(30.0, roads), 21.87, 0.001)
	t.near("no hops, no loss", SupplyRules.delivery_factor([]), 1.0, 0.0001)

func _test_level_delta() -> void:
	t.near("fed stacks gain 10", SupplyRules.level_delta(0.0, 12), 10.0, 0.001)
	t.near("a surplus is still +10", SupplyRules.level_delta(-5.0, 12), 10.0, 0.001)
	t.near("shortfall 8 on 12 regiments is −3.33", SupplyRules.level_delta(8.0, 12), -3.3333, 0.001)
	t.near("shortfall 1.6 on 6 regiments is −1.33", SupplyRules.level_delta(1.6, 6), -1.3333, 0.001)

func _test_move_points() -> void:
	var w := _world()
	var small := w.add_stack(0, 0, _inf(4))
	var raider := w.add_stack(0, 0, _inf(3))
	var big := w.add_stack(0, 0, _inf(9))
	var huge := w.add_stack(0, 0, _inf(13))
	t.check("4 regiments move 4", SupplyRules.move_points(small) == 4)
	t.check("3 regiments are a raider and move 5", SupplyRules.is_raider(raider) and SupplyRules.move_points(raider) == 5)
	t.check("9 regiments move 3", SupplyRules.move_points(big) == 3)
	t.check("13 regiments move 2", SupplyRules.move_points(huge) == 2)
	small.supply = 5.0
	t.check("below 10 supply movement halves", SupplyRules.move_points(small) == 2)
	huge.supply = 5.0
	t.check("halving never drops below 1", SupplyRules.move_points(huge) == 1)
	t.check("road costs 1, trail 2, mountain 3, river 1",
		SupplyRules.move_cost(Edge.Kind.ROAD) == 1 and SupplyRules.move_cost(Edge.Kind.TRAIL) == 2
		and SupplyRules.move_cost(Edge.Kind.MOUNTAIN) == 3 and SupplyRules.move_cost(Edge.Kind.RIVER) == 1)

func _test_holdings() -> void:
	var w := _world()
	var farm := w.graph.site(3)
	t.check("an ungarrisoned site belongs to its region's owner", Holdings.site_owner(w, farm) == 1)
	t.check("enemy ground is hostile to us", Holdings.is_hostile_ground(w, farm, 0))
	t.check("and friendly to them", Holdings.is_friendly(w, farm, 1))
	farm.garrison_nation = 0
	t.check("a garrison overrides the region", Holdings.site_owner(w, farm) == 0 and Holdings.is_friendly(w, farm, 0))
	w.set_relation(0, 1, World.PEACE)
	farm.garrison_nation = -1
	t.check("at peace, their ground is not hostile ground", not Holdings.is_hostile_ground(w, farm, 0))
	var depot := w.graph.site(0)
	t.check("a depot with no build pending is ready", Holdings.depot_ready(w, depot))
	depot.depot_ready_turn = w.turn + 2
	t.check("a depot under construction is not", not Holdings.depot_ready(w, depot))
	t.check("a village is never a depot", not Holdings.depot_ready(w, w.graph.site(1)))

func _test_local_feed() -> void:
	var w := _world()
	t.near("a farm feeds three regiments' worth", SupplyRules.local_feed(w, w.graph.site(3), 12), 6.0, 0.001)
	t.near("but only what is standing there", SupplyRules.local_feed(w, w.graph.site(3), 2), 4.0, 0.001)
	t.near("a village feeds one", SupplyRules.local_feed(w, w.graph.site(1), 5), 2.0, 0.001)
	t.near("a feature feeds nobody", SupplyRules.local_feed(w, w.graph.site(2), 5), 0.0, 0.001)
	var depot := w.graph.site(0)
	depot.stock = 7.0
	t.near("a depot feeds from stock, up to the upkeep asked", SupplyRules.local_feed(w, depot, 12), 7.0, 0.001)
	t.near("and no more than the stack eats", SupplyRules.local_feed(w, depot, 2), 4.0, 0.001)
	t.check("depot feed is flagged as coming from stock", SupplyRules.local_from_stock(w, depot))
	t.check("farm feed is not", not SupplyRules.local_from_stock(w, w.graph.site(3)))

# Placeholders filled by Tasks 3–7. Keep them `pass` until then.
func _test_report_worked_example() -> void: pass
func _test_depots_refill_from_farms_in_reach() -> void: pass
func _test_one_farm_starves_four_farms_hold() -> void: pass
func _test_raider_on_the_road_raises_shortfall() -> void: pass
func _test_foraging_pillages() -> void: pass
func _test_desertion() -> void: pass
func _test_occupation() -> void: pass
func _test_orders() -> void: pass
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && godot --headless --script tests/run_tests.gd -- supply`
Expected: parse error, `SupplyRules` / `Holdings` not declared.

- [ ] **Step 3: Add the config and the two fields**

Append to `game/scripts/sim/game_config.gd` after the `sites` dict:
```gdscript
## Logistics (Appendix B): upkeep, hop loss, movement, depots, starvation,
## pillage. WS-A reads these through SupplyRules; nobody indexes them directly.
static var logistics := {
	"upkeep_per_regiment": 2.0,        # Supply one regiment eats per turn
	"big_stack": 8,                    # above this many regiments: upkeep ×1.5, movement 3
	"big_stack_upkeep": 1.5,
	"huge_stack": 12,                  # above this: upkeep ×2, movement 2
	"huge_stack_upkeep": 2.0,
	"hop_loss_road": 0.10,
	"hop_loss_river": 0.05,
	"hop_loss_trail": 0.20,
	"hop_loss_mountain": 0.35,
	"move_cost_road": 1,
	"move_cost_river": 1,
	"move_cost_trail": 2,
	"move_cost_mountain": 3,
	"move_points": 4,
	"move_points_big": 3,
	"move_points_huge": 2,
	"raider_max_regiments": 3,         # a stack this small is a raider
	"raider_move_points": 5,
	"depot_cost": 40.0,
	"depot_build_turns": 2,
	"depot_farm_reach": 3,             # hops a farm's yield travels to its depot
	"depot_initial_stock": 60.0,       # what every depot opens the run with
	"level_gain": 10.0,                # supply level change when fully fed
	"level_loss_per_shortfall": 5.0,   # × (shortfall / regiments) when not
	"supply_warning": 50.0,            # the level whose crossing is logged
	"desertion_below": 30.0,
	"desertion_every": 2,              # turns under the threshold per regiment lost
	"slow_below": 10.0,                # movement halved under this level
	"pillage_farm_turns": 2,           # yield destroyed per turn pillaged
	"pillage_village_coin": 2.0,
	"pillage_village_turns": 4,
	"pillage_mine_coin": 8.0,
	"pillage_mine_turns": 6,
	"pillage_market_coin": 10.0,
	"pillage_market_turns": 3,
	"pillage_node_turns": 3,
	"detach_quality": 0.5,             # a detachment with no leader of its own
	"marcher_split_below": 40.0,       # scripted marcher splits under this level
}
```

In `game/scripts/sim/world/site.gd`, after `pillaged_until`:
```gdscript
var depot_ready_turn := 0         # DEPOT only: usable once world.turn >= this (WS-A build_depot)
```
In `game/scripts/sim/world/stack.gd`, after `supply_report`:
```gdscript
var hunger := 0                   # consecutive turns under the desertion threshold (WS-A)
```

- [ ] **Step 4: Implement Holdings and SupplyRules**

`game/scripts/sim/logistics/holdings.gd`:
```gdscript
class_name Holdings
extends RefCounted

## Who holds a site right now. The one place "friendly ground" is decided, so
## free feeding, foraging, pillage and depot access can never disagree.
##
## A garrison (a stack ordered to hold, see OccupationPhase) owns the site it
## stands on; otherwise the site belongs to whoever owns its region.

static func site_owner(world: World, site: Site) -> int:
	if site.garrison_nation >= 0:
		return site.garrison_nation
	return world.graph.region_of(site.id).owner

static func is_friendly(world: World, site: Site, nation_id: int) -> bool:
	return site_owner(world, site) == nation_id

## Owned by somebody we are at war with. Unowned or neutral ground is neither
## friendly nor hostile: it feeds an army for free and is not pillaged.
static func is_hostile_ground(world: World, site: Site, nation_id: int) -> bool:
	var owner := site_owner(world, site)
	return owner >= 0 and world.hostile(owner, nation_id)

static func depot_ready(world: World, site: Site) -> bool:
	return site.kind == Site.Kind.DEPOT and world.turn >= site.depot_ready_turn

static func is_friendly_depot(world: World, site: Site, nation_id: int) -> bool:
	return depot_ready(world, site) and is_friendly(world, site, nation_id)
```

`game/scripts/sim/logistics/supply_rules.gd`:
```gdscript
class_name SupplyRules
extends RefCounted

## Appendix B's supply arithmetic as pure functions: nothing here mutates the
## world, and every number comes from GameConfig.logistics. SupplyPhase applies
## them each turn, the AI's projection (WS-D) replays them along a candidate
## path, and the tooltip shows their breakdown, so all three agree by
## construction.

static func upkeep(regiments: int) -> float:
	var L := GameConfig.logistics
	var base: float = float(regiments) * float(L["upkeep_per_regiment"])
	if regiments > int(L["huge_stack"]):
		return base * float(L["huge_stack_upkeep"])
	if regiments > int(L["big_stack"]):
		return base * float(L["big_stack_upkeep"])
	return base

## True when a site feeds out of its own stock (a ready depot) rather than off
## the land. SupplyPhase drains the stock by what was eaten.
static func local_from_stock(world: World, site: Site) -> bool:
	return Holdings.depot_ready(world, site)

## What the ground feeds: up to the site's forage capacity, one regiment's
## upkeep each, never more than the regiments standing there eat. A depot
## feeds any number, from stock.
static func local_feed(world: World, site: Site, regiments: int) -> float:
	var per: float = float(GameConfig.logistics["upkeep_per_regiment"])
	var asked := float(regiments) * per
	if local_from_stock(world, site):
		return minf(asked, maxf(0.0, site.stock))
	var cap := Yields.forage_regiments(site, world.graph.region_of(site.id), world)
	return float(mini(cap, regiments)) * per

static func hop_loss(kind: int) -> float:
	var L := GameConfig.logistics
	match kind:
		Edge.Kind.RIVER: return float(L["hop_loss_river"])
		Edge.Kind.TRAIL: return float(L["hop_loss_trail"])
		Edge.Kind.MOUNTAIN: return float(L["hop_loss_mountain"])
	return float(L["hop_loss_road"])

## The fraction of a shipment that survives a chain of edges.
static func delivery_factor(edges: Array) -> float:
	var f := 1.0
	for e in edges:
		f *= 1.0 - hop_loss(e.kind)
	return f

static func delivered(requested: float, edges: Array) -> float:
	return requested * delivery_factor(edges)

static func level_delta(shortfall: float, regiments: int) -> float:
	var L := GameConfig.logistics
	if shortfall <= 0.0:
		return float(L["level_gain"])
	return -(shortfall / float(maxi(1, regiments))) * float(L["level_loss_per_shortfall"])

static func move_cost(kind: int) -> int:
	var L := GameConfig.logistics
	match kind:
		Edge.Kind.RIVER: return int(L["move_cost_river"])
		Edge.Kind.TRAIL: return int(L["move_cost_trail"])
		Edge.Kind.MOUNTAIN: return int(L["move_cost_mountain"])
	return int(L["move_cost_road"])

static func is_raider(stack: Stack) -> bool:
	return stack.size() > 0 and stack.size() <= int(GameConfig.logistics["raider_max_regiments"])

## Movement points this turn: big stacks are slow, raiders fast, the starving
## slower still.
static func move_points(stack: Stack) -> int:
	var L := GameConfig.logistics
	var pts := int(L["move_points"])
	if is_raider(stack):
		pts = int(L["raider_move_points"])
	elif stack.size() > int(L["huge_stack"]):
		pts = int(L["move_points_huge"])
	elif stack.size() > int(L["big_stack"]):
		pts = int(L["move_points_big"])
	if stack.supply < float(L["slow_below"]):
		pts = maxi(1, pts / 2)
	return pts
```

- [ ] **Step 5: Re-import, run** — `godot --headless --path game --import` then `-- supply`. Expected: every rule check passes; the placeholders pass trivially.
- [ ] **Step 6: Stage** — `git add game/scripts/sim/logistics game/scripts/sim/game_config.gd game/scripts/sim/world/site.gd game/scripts/sim/world/stack.gd game/tests/test_supply.gd` (+ `.uid` files). Suggested message: `Add the supply rules and logistics config`

---

### Task 2: Pathing

**Files:**
- Create: `game/scripts/sim/logistics/pathing.gd`
- Create: `game/tests/test_movement.gd`

**Interfaces produced:**
```gdscript
Pathing.Cost { MOVEMENT, HOPS, SUPPLY }
Pathing.explore(world, from: int, nation_id: int, mode: int) -> Dictionary   # {"dist": PackedFloat64Array, "prev_site": PackedInt32Array, "prev_edge": Array}
Pathing.shortest(world, from, to, nation_id, mode := Cost.MOVEMENT) -> Array[int]   # sites after `from`, ending at `to`; [] if unreachable or from == to
Pathing.edges_along(world, from, sites: Array[int]) -> Array                   # the Edge for each step
Pathing.nearest_depot(world, from, nation_id, with_stock := true) -> Dictionary  # {site_id, hops, sites, edges, factor} or {}
```

- [ ] **Step 1: Write the failing tests**

`game/tests/test_movement.gd`:
```gdscript
extends RefCounted

## WS-A: how armies get from site to site, and the scripted enemies and
## scenarios that exercise it.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_road_beats_trail()
	_test_presence_blocks_the_interior()
	_test_nearest_depot()
	# Later tasks append here.
	_test_walk_and_stop()
	_test_merge()
	_test_marcher()
	_test_raider()
	_test_the_march_dumb_and_smart()
	_test_the_siege_is_winnable_without_a_fight()

## Same fixture as test_supply.gd; kept local so neither suite edits the other.
func _map() -> Dictionary:
	return {
		"nations": [
			{"id": 0, "name": "Home", "player": true, "coin": 60},
			{"id": 1, "name": "Foe", "player": false, "coin": 60},
		],
		"relations": [{"a": 0, "b": 1, "state": "war"}],
		"regions": [{"id": 0, "name": "Homeland", "owner": 0}, {"id": 1, "name": "Foeland", "owner": 1}],
		"sites": [
			{"id": 0, "region": 0, "kind": "depot", "pos": [100, 100], "name": "Depot"},
			{"id": 1, "region": 0, "kind": "village", "pos": [200, 100], "name": "Village"},
			{"id": 2, "region": 0, "kind": "feature", "pos": [300, 100], "name": "Crossroads"},
			{"id": 3, "region": 1, "kind": "farm", "pos": [400, 100], "name": "Enemy Farm"},
			{"id": 4, "region": 0, "kind": "farm", "pos": [200, 200], "name": "Home Farm"},
			{"id": 5, "region": 1, "kind": "farm", "pos": [400, 200], "name": "Far Farm"},
			{"id": 6, "region": 1, "kind": "village", "pos": [500, 100], "name": "Foe Village"},
			{"id": 7, "region": 1, "kind": "market", "pos": [500, 200], "name": "Foe Market"},
			{"id": 8, "region": 1, "kind": "farm", "pos": [600, 200], "name": "Fourth Farm"},
		],
		"edges": [
			{"a": 0, "b": 1}, {"a": 1, "b": 2}, {"a": 2, "b": 3},
			{"a": 1, "b": 4, "kind": "trail"}, {"a": 2, "b": 4, "kind": "trail"},
			{"a": 3, "b": 5, "kind": "river"}, {"a": 3, "b": 6}, {"a": 6, "b": 7}, {"a": 7, "b": 8},
		],
	}

func _world() -> World:
	var w := World.from_map(_map(), 1)
	w.graph.site(0).stock = 0.0
	return w

func _inf(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(GameConfig.Role.INFANTRY)
	return out

func _cav(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(GameConfig.Role.CAVALRY)
	return out

# ------------------------------------------------------------------- pathing

func _test_road_beats_trail() -> void:
	var w := _world()
	t.check("Home Farm to Depot goes by the village road, not the crossroads trail",
		Pathing.shortest(w, 4, 0, 0) == ([1, 0] as Array[int]), str(Pathing.shortest(w, 4, 0, 0)))
	t.check("Depot to Fourth Farm walks the whole road",
		Pathing.shortest(w, 0, 8, 0) == ([1, 2, 3, 6, 7, 8] as Array[int]))
	t.check("a site is no distance from itself", Pathing.shortest(w, 2, 2, 0).is_empty())
	var ex := Pathing.explore(w, 0, 0, Pathing.Cost.MOVEMENT)
	t.near("movement cost to Home Farm is 3 (road + trail)", ex["dist"][4], 3.0, 0.001)
	var hops := Pathing.explore(w, 0, 0, Pathing.Cost.HOPS)
	t.near("hops to Home Farm is 2", hops["dist"][4], 2.0, 0.001)

func _test_presence_blocks_the_interior() -> void:
	var w := _world()
	w.add_stack(1, 1, _cav(3))                # a raider on the Village
	t.check("with a raider on the village the depot is unreachable from the crossroads",
		Pathing.shortest(w, 2, 0, 0).is_empty())
	t.check("but the raider's own site can still be the destination (an attack)",
		Pathing.shortest(w, 2, 1, 0) == ([1] as Array[int]))
	t.check("the raider itself is not blocked by its own presence",
		Pathing.shortest(w, 1, 0, 1) == ([0] as Array[int]))
	w.set_relation(0, 1, World.PEACE)
	t.check("at peace, presence blocks nothing", Pathing.shortest(w, 2, 0, 0) == ([1, 0] as Array[int]))

func _test_nearest_depot() -> void:
	var w := _world()
	t.check("no stock, no depot", Pathing.nearest_depot(w, 3, 0).is_empty())
	t.check("unless stock is not required", Pathing.nearest_depot(w, 3, 0, false)["site_id"] == 0)
	w.graph.site(0).stock = 80.0
	var d := Pathing.nearest_depot(w, 3, 0)
	t.check("Enemy Farm's depot is three road hops away", d["site_id"] == 0 and d["hops"] == 3)
	t.near("and delivers 72.9%", d["factor"], 0.729, 0.0001)
	t.check("the route is listed from the army toward the depot", d["sites"] == ([2, 1, 0] as Array[int]))
	t.check("standing on the depot is zero hops at full delivery",
		Pathing.nearest_depot(w, 0, 0)["hops"] == 0 and is_equal_approx(Pathing.nearest_depot(w, 0, 0)["factor"], 1.0))
	t.check("the enemy has no depot at all", Pathing.nearest_depot(w, 3, 1, false).is_empty())
	w.graph.site(0).depot_ready_turn = w.turn + 1
	t.check("a depot under construction does not count", Pathing.nearest_depot(w, 3, 0).is_empty())

# Placeholders filled by Tasks 3, 7 and 8.
func _test_walk_and_stop() -> void: pass
func _test_merge() -> void: pass
func _test_marcher() -> void: pass
func _test_raider() -> void: pass
func _test_the_march_dumb_and_smart() -> void: pass
func _test_the_siege_is_winnable_without_a_fight() -> void: pass
```

- [ ] **Step 2: Run to verify it fails** — `-- movement`. Expected: `Pathing` not declared.

- [ ] **Step 3: Implement**

`game/scripts/sim/logistics/pathing.gd`:
```gdscript
class_name Pathing
extends RefCounted

## Dijkstra over the site graph, in three currencies: movement points (what an
## order costs), hops (what a farm's reach is measured in), and supply loss
## (what a depot route is judged by). Interior sites with hostile presence are
## walls — presence severs — but the destination may be hostile, which is how
## an attack is ordered. Deterministic: the graph is walked in id order.
##
## O(V²) with plain arrays: fine for 60 sites, and still under a millisecond
## for the 300 the full map will have. Revisit with a heap if WS-D's profiler
## says so, not before.

enum Cost { MOVEMENT, HOPS, SUPPLY }

static func edge_cost(e: Edge, mode: int) -> float:
	match mode:
		Cost.HOPS:
			return 1.0
		Cost.SUPPLY:
			return -log(1.0 - SupplyRules.hop_loss(e.kind))
	return float(SupplyRules.move_cost(e.kind))

## Distances and predecessors from `from` for `nation_id`, indexed by site id.
## Unreachable sites have INF distance and -1 predecessor.
static func explore(world: World, from: int, nation_id: int, mode: int) -> Dictionary:
	var n := world.graph.sites.size()
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var prev_site := PackedInt32Array()
	prev_site.resize(n)
	prev_site.fill(-1)
	var prev_edge: Array = []
	prev_edge.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	done.fill(0)
	dist[from] = 0.0
	while true:
		var u := -1
		var best := INF
		for i in n:
			if done[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0:
			break
		done[u] = 1
		# You can arrive at a hostile-held site, but nothing passes through it.
		if u != from and world.hostile_presence(u, nation_id):
			continue
		for e in world.graph.edges_of(u):
			var v: int = e.other(u)
			var d: float = best + edge_cost(e, mode)
			if d < dist[v]:
				dist[v] = d
				prev_site[v] = u
				prev_edge[v] = e
	return {"dist": dist, "prev_site": prev_site, "prev_edge": prev_edge}

static func _walk_back(ex: Dictionary, from: int, to: int) -> Array[int]:
	var out: Array[int] = []
	var cur := to
	while cur != from and cur >= 0:
		out.push_front(cur)
		cur = ex["prev_site"][cur]
	return out

## The sites after `from`, ending at `to`. Empty when unreachable or already there.
static func shortest(world: World, from: int, to: int, nation_id: int, mode := Cost.MOVEMENT) -> Array[int]:
	if from == to:
		return [] as Array[int]
	var ex := explore(world, from, nation_id, mode)
	if ex["dist"][to] == INF:
		return [] as Array[int]
	return _walk_back(ex, from, to)

static func edges_along(world: World, from: int, sites: Array[int]) -> Array:
	var out: Array = []
	var cur := from
	for s in sites:
		out.append(world.graph.edge_between(cur, s))
		cur = s
	return out

## The friendly, ready depot that delivers the most of what it sends, and the
## route to it. {} when none is reachable. `with_stock` false is for planners
## asking "where would I be fed from" rather than "feed me now".
static func nearest_depot(world: World, from: int, nation_id: int, with_stock := true) -> Dictionary:
	var ex := explore(world, from, nation_id, Cost.SUPPLY)
	var best := -1
	var best_d := INF
	for s in world.graph.sites:
		if not Holdings.is_friendly_depot(world, s, nation_id):
			continue
		if with_stock and s.stock <= 0.0:
			continue
		var d: float = ex["dist"][s.id]
		if d < best_d:
			best_d = d
			best = s.id
	if best < 0:
		return {}
	var sites := _walk_back(ex, from, best)
	var edges := edges_along(world, from, sites)
	return {
		"site_id": best,
		"hops": sites.size(),
		"sites": sites,
		"edges": edges,
		"factor": SupplyRules.delivery_factor(edges),
	}
```

- [ ] **Step 4: Re-import, run** — `-- movement`. Expected: pathing checks pass.
- [ ] **Step 5: Stage** — `git add game/scripts/sim/logistics/pathing.gd game/scripts/sim/logistics/pathing.gd.uid game/tests/test_movement.gd game/tests/test_movement.gd.uid`. Message: `Add supply-aware pathing over the site graph`

---

### Task 3: The supply report and the worked example

**Files:**
- Modify: `game/scripts/sim/logistics/supply_rules.gd` (add `report`)
- Modify: `game/tests/test_supply.gd` (fill `_test_report_worked_example`)

**Interface produced:**
```gdscript
SupplyRules.report(world, stack) -> Dictionary
# keys: upkeep, local, local_from_stock, foraging, requested, depot_draw, delivered,
#       depot_id (-1 none), hops (-1 none), route (Array[int]), shortfall, delta
```
Pure: it reads stock and presence but changes nothing. SupplyPhase applies it; the AI (WS-D) replays it.

- [ ] **Step 1: Write the failing test**

Replace the placeholder in `test_supply.gd`:
```gdscript
func _test_report_worked_example() -> void:
	var w := _world()
	w.graph.site(0).stock = 80.0
	var big := w.add_stack(0, 3, _inf(12))      # 12 regiments on the enemy farm, 3 road hops out
	var r := SupplyRules.report(w, big)
	t.near("upkeep 36", r["upkeep"], 36.0, 0.001)
	t.near("local 6 (the farm feeds three)", r["local"], 6.0, 0.001)
	t.check("it is foraging", r["foraging"])
	t.near("requests 30 from the depot", r["requested"], 30.0, 0.001)
	t.near("depot loses 30", r["depot_draw"], 30.0, 0.001)
	t.near("21.87 arrives", r["delivered"], 21.87, 0.01)
	t.check("three hops from depot 0", r["depot_id"] == 0 and r["hops"] == 3)
	t.near("shortfall 8.13", r["shortfall"], 8.13, 0.01)
	t.near("level falls 3.39", r["delta"], -3.39, 0.01)
	t.check("the report changed nothing", is_equal_approx(w.graph.site(0).stock, 80.0) and is_equal_approx(big.supply, 100.0))

	w.remove_stack(big)
	var a := w.add_stack(0, 3, _inf(6))
	var b := w.add_stack(0, 5, _inf(6))         # the river farm, 4 hops (river then three roads)
	var ra := SupplyRules.report(w, a)
	t.near("a 6-stack eats 12", ra["upkeep"], 12.0, 0.001)
	t.near("draws 6 from the depot", ra["depot_draw"], 6.0, 0.001)
	t.near("and falls only 1.36", ra["delta"], -1.355, 0.01)
	var rb := SupplyRules.report(w, b)
	t.near("the river farm's route loses a little more", rb["delivered"], 6.0 * 0.729 * 0.95, 0.01)

	# Standing on a depot: stock feeds directly, nothing double-counts.
	var home := w.add_stack(0, 0, _inf(4))
	w.graph.site(0).stock = 5.0
	var rh := SupplyRules.report(w, home)
	t.near("5 of the 8 comes from stock underfoot", rh["local"], 5.0, 0.001)
	t.check("flagged as from stock", rh["local_from_stock"])
	t.near("the rest cannot come from the same empty depot", rh["depot_draw"], 0.0, 0.001)
	t.near("shortfall 3", rh["shortfall"], 3.0, 0.001)
```

- [ ] **Step 2: Run to verify it fails** — `-- supply`. Expected: `report` not found.

- [ ] **Step 3: Implement `report`** (append to `supply_rules.gd`):
```gdscript
## The whole per-turn breakdown for one stack, without applying it. Appendix
## B's order: upkeep, local feed, depot feed, shortfall, level change. Keys are
## the tooltip's words; WS-D's projection replays this along a candidate path.
static func report(world: World, stack: Stack) -> Dictionary:
	var site := world.graph.site(stack.site_id)
	var n := stack.size()
	var up := upkeep(n)
	var from_stock := local_from_stock(world, site)
	var local := minf(up, local_feed(world, site, n))
	var request := maxf(0.0, up - local)
	var depot := {}
	var draw := 0.0
	var arrived := 0.0
	if request > 0.0:
		depot = Pathing.nearest_depot(world, stack.site_id, stack.nation_id, true)
		if not depot.is_empty():
			var ds: Site = world.graph.site(depot["site_id"])
			# Stock already eaten from underfoot is not on the shelf any more.
			var available: float = ds.stock - (local if from_stock and ds.id == site.id else 0.0)
			draw = minf(request, maxf(0.0, available))
			arrived = draw * float(depot["factor"])
			if draw <= 0.0:
				depot = {}
	var shortfall := up - local - arrived
	return {
		"upkeep": up,
		"local": local,
		"local_from_stock": from_stock,
		"foraging": Holdings.is_hostile_ground(world, site, stack.nation_id),
		"requested": request,
		"depot_draw": draw,
		"delivered": arrived,
		"depot_id": depot.get("site_id", -1),
		"hops": depot.get("hops", -1),
		"route": depot.get("sites", [] as Array[int]),
		"shortfall": shortfall,
		"delta": level_delta(shortfall, n),
	}
```

- [ ] **Step 4: Run** — `-- supply`. Expected: worked-example checks pass. If `21.87` or `-3.39` is off by more than the tolerance, the bug is in the rules, not the numbers: Appendix B's example is the spec.
- [ ] **Step 5: Stage.** Message: `Add the per-stack supply report`

---

### Task 4: Movement and the MovementPhase

**Files:**
- Create: `game/scripts/sim/logistics/movement.gd`
- Modify: `game/scripts/sim/phases/movement_phase.gd`
- Modify: `game/tests/test_movement.gd` (fill `_test_walk_and_stop`, `_test_merge`)

**Interfaces produced:**
```gdscript
Movement.walk(world, stack) -> void          # spends this turn's points along stack.path
Movement.merge_all(world) -> void            # friendly stacks sharing a site fold together
Movement.merge(world, into: Stack, other: Stack) -> void
MovementPhase.run(world)                     # ScriptedEnemy.issue_orders (Task 7; stub call until then) → walk each stack in id order → merge_all
```
Rules: a step costs the edge's move cost; a step the stack cannot afford ends the turn (no partial moves on a graph); entering a site with hostile presence ends the march and clears the path (the encounter is WS-C's); a path whose next site is no longer adjacent is dropped with a log line. Merge: lowest id survives, regiments appended, supply is the size-weighted mean, `hold_separate` on either side prevents it, the survivor keeps its own order and path.

- [ ] **Step 1: Write the failing tests**
```gdscript
func _test_walk_and_stop() -> void:
	var w := _world()
	var s := w.add_stack(0, 0, _inf(4))
	s.path = [1, 2, 3, 6] as Array[int]
	Movement.walk(w, s)
	t.check("4 points walk 4 road edges", s.site_id == 6 and s.path.is_empty(), "at %d" % s.site_id)
	t.check("it moved this turn", s.moved_this_turn)

	var big := w.add_stack(0, 0, _inf(9))
	big.path = [1, 2, 3, 6] as Array[int]
	Movement.walk(w, big)
	t.check("9 regiments walk 3", big.site_id == 3 and big.path == ([6] as Array[int]))

	var trail := w.add_stack(0, 0, _inf(4))
	trail.path = [1, 4, 2] as Array[int]           # road 1 + trail 2 = 3, the next trail (2) does not fit
	Movement.walk(w, trail)
	t.check("a step it cannot afford waits for next turn", trail.site_id == 4 and trail.path == ([2] as Array[int]))

	var foe := w.add_stack(1, 3, _cav(2))
	var att := w.add_stack(0, 1, _inf(4))
	att.path = [2, 3, 6] as Array[int]
	Movement.walk(w, att)
	t.check("entering a hostile site ends the march there", att.site_id == 3 and att.path.is_empty())
	t.check("both stacks share the site for EngagementPhase", w.stacks_at(3).has(foe) and w.stacks_at(3).has(att))

	var stale := w.add_stack(0, 0, _inf(2))
	stale.path = [7] as Array[int]                  # not adjacent to the depot
	Movement.walk(w, stale)
	t.check("a stale route is dropped, not walked", stale.site_id == 0 and stale.path.is_empty())

func _test_merge() -> void:
	var w := _world()
	var a := w.add_stack(0, 1, _inf(4), 100.0)
	var b := w.add_stack(0, 1, _cav(2), 40.0)
	var foe := w.add_stack(1, 1, _inf(1), 70.0)
	Movement.merge_all(w)
	t.check("friendly stacks on one site merge into the lower id", w.stacks_at(1).size() == 2 and w.stacks.has(a) and not w.stacks.has(b))
	t.check("regiments are pooled", a.size() == 6 and a.regiments.count(GameConfig.Role.CAVALRY) == 2)
	t.near("supply is the size-weighted mean", a.supply, 80.0, 0.001)
	t.check("the enemy on the same site is untouched", w.stacks.has(foe) and foe.size() == 1)

	var c := w.add_stack(0, 2, _inf(1))
	var d := w.add_stack(0, 2, _inf(1))
	d.hold_separate = true
	Movement.merge_all(w)
	t.check("hold_separate keeps a stack apart", w.stacks.has(c) and w.stacks.has(d))

	# The phase walks then merges, in id order, and only touches moved flags via the resolver.
	var w2 := _world()
	var x := w2.add_stack(0, 0, _inf(3))
	var y := w2.add_stack(0, 2, _inf(3))
	x.path = [1, 2] as Array[int]
	MovementPhase.run(w2)
	t.check("MovementPhase walks and then merges arrivals", w2.stacks.size() == 1 and w2.stacks[0] == x and x.size() == 6 and x.site_id == 2)
	t.check("y was folded into x", not w2.stacks.has(y))
```

- [ ] **Step 2: Run to verify it fails** — `-- movement`. Expected: `Movement` not declared.

- [ ] **Step 3: Implement**

`game/scripts/sim/logistics/movement.gd`:
```gdscript
class_name Movement
extends RefCounted

## Walks a stack's ordered path on End Turn and folds friendly stacks together
## where they end up. No rules about *where* to go live here (see Orders and
## Pathing); this is only what happens once the order is given.

static func walk(world: World, s: Stack) -> void:
	if s.path.is_empty():
		return
	var points := SupplyRules.move_points(s)
	while points > 0 and not s.path.is_empty():
		var next: int = s.path[0]
		var e := world.graph.edge_between(s.site_id, next)
		if e == null:
			# The map cannot change, so a stale route means a bad order; say so and drop it.
			world.record("%s's route no longer leads anywhere and was dropped" % s.label)
			s.path.clear()
			return
		var cost := SupplyRules.move_cost(e.kind)
		if cost > points:
			return
		points -= cost
		s.site_id = next
		s.path.remove_at(0)
		s.moved_this_turn = true
		if world.hostile_presence(next, s.nation_id):
			# The march ends where the enemy is; EngagementPhase (WS-C) takes it from here.
			s.path.clear()
			return

## Fold `other` into `into`: regiments pooled, supply size-weighted, the
## survivor keeps its own order and route.
static func merge(world: World, into: Stack, other: Stack) -> void:
	var n_a := into.size()
	var n_b := other.size()
	if n_a + n_b > 0:
		into.supply = (into.supply * float(n_a) + other.supply * float(n_b)) / float(n_a + n_b)
	into.regiments.append_array(other.regiments)
	world.remove_stack(other)
	world.record("%s joined %s (%d regiments)" % [other.label, into.label, into.size()])

## Every site, every nation: the lowest-id stack absorbs the rest, unless a
## stack asked to be left alone.
static func merge_all(world: World) -> void:
	var ordered: Array = world.stacks.duplicate()
	ordered.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	var survivors := {}                 # "site:nation" -> Stack
	for s in ordered:
		if s.hold_separate:
			continue
		var key := "%d:%d" % [s.site_id, s.nation_id]
		if survivors.has(key):
			merge(world, survivors[key], s)
		else:
			survivors[key] = s
```

`game/scripts/sim/phases/movement_phase.gd`:
```gdscript
class_name MovementPhase
extends RefCounted

## WS-A. Scripted enemies decide, every stack walks its route in id order (so
## a turn resolves identically every time), then arrivals merge.

static func run(world: World) -> void:
	ScriptedEnemy.issue_orders(world)
	var ordered: Array = world.stacks.duplicate()
	ordered.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	for s in ordered:
		if world.stacks.has(s):
			Movement.walk(world, s)
	Movement.merge_all(world)
```
`ScriptedEnemy` does not exist until Task 7. Create it now as a stub so the phase parses:
`game/scripts/sim/logistics/scripted_enemy.gd`:
```gdscript
class_name ScriptedEnemy
extends RefCounted

## Appendix B's two scripted enemies (Task 7). Stub until then.

static func issue_orders(_world: World) -> void:
	pass
```

- [ ] **Step 4: Re-import, run** — `-- movement`, then the full suite (the world suite's "no phase advances the turn" check must still pass).
- [ ] **Step 5: Stage.** Message: `Walk ordered routes and merge arrivals on End Turn`

---

### Task 5: SupplyPhase — depots refill, stacks eat, pillage, desertion

**Files:**
- Modify: `game/scripts/sim/phases/supply_phase.gd`
- Create: `game/scripts/sim/logistics/logistics_setup.gd`
- Modify: `game/scripts/sim/world/world_setup.gd` (one line: `static var _hooks: Array[Callable] = [LogisticsSetup.run]`)
- Modify: `game/tests/test_supply.gd` (fill four tests)

**Interfaces produced:**
```gdscript
SupplyPhase.run(world)
SupplyPhase.refill_depots(world)          # each farm's yield to its nearest friendly depot within reach
SupplyPhase.feed(world, stack)            # applies SupplyRules.report: drains, pillages, moves the level, writes stack.supply_report
SupplyPhase.pillage(world, site, by_nation)
LogisticsSetup.run(world)                 # every ready depot opens with GameConfig.logistics["depot_initial_stock"]
```
Log lines (scenario status reads them): `"%s is short on supply (%d%%)"` when a stack crosses `supply_warning` downward; `"%s lost a regiment to desertion"`; `"%s dissolved"`.

- [ ] **Step 1: Write the failing tests**
```gdscript
func _test_depots_refill_from_farms_in_reach() -> void:
	var w := _world()
	SupplyPhase.refill_depots(w)
	t.near("Home Farm (2 hops) feeds the depot 6", w.graph.site(0).stock, 6.0, 0.001)
	w.graph.site(0).stock = 118.0
	SupplyPhase.refill_depots(w)
	t.near("stock caps at the depot's capacity", w.graph.site(0).stock, 120.0, 0.001)
	w.graph.site(0).stock = 0.0
	w.graph.site(4).pillaged_until = w.turn + 2
	SupplyPhase.refill_depots(w)
	t.near("a pillaged farm yields nothing", w.graph.site(0).stock, 0.0, 0.001)
	# Enemy farms have no depot to send to; four hops is out of reach.
	var far := World.from_map(_map(), 1)
	far.graph.region(1).owner = 0                  # now all farms are ours, but Fourth Farm is 6 hops out
	far.graph.site(0).stock = 0.0
	SupplyPhase.refill_depots(far)
	t.near("only farms within reach count (Home 2, Enemy 3; Far 4 and Fourth 6 do not)", far.graph.site(0).stock, 12.0, 0.001)

func _test_one_farm_starves_four_farms_hold() -> void:
	var w := _world()                              # depot empty: nothing to lean on
	var doom := w.add_stack(0, 3, _inf(12))
	for i in 3:
		SupplyPhase.feed(w, doom)
	t.check("a 12-stack on one farm visibly starves: 100 → %d in three turns" % int(doom.supply), doom.supply < 70.0)
	t.near("its report says shortfall 30", doom.supply_report["shortfall"], 30.0, 0.001)

	var w2 := _world()
	var parts: Array[Stack] = []
	for site_id in [3, 4, 5, 8]:
		parts.append(w2.add_stack(0, site_id, _inf(3), 60.0))
	for i in 3:
		for p in parts:
			SupplyPhase.feed(w2, p)
	var all_up := true
	for p in parts:
		all_up = all_up and p.supply >= 90.0
	t.check("the same twelve split across four farms hold steady and recover", all_up)

func _test_raider_on_the_road_raises_shortfall() -> void:
	var w := _world()
	w.graph.site(0).stock = 80.0
	var army := w.add_stack(0, 2, _inf(6))         # on the crossroads, 2 road hops from the depot
	var before := SupplyRules.report(w, army)
	t.near("fed by the depot: shortfall 2.28", before["shortfall"], 12.0 - 12.0 * 0.81, 0.01)
	var raider := w.add_stack(1, 1, _cav(3))       # on the village between them
	var after := SupplyRules.report(w, army)
	t.near("the same turn the raider sits down the whole upkeep is short", after["shortfall"], 12.0, 0.001)
	t.check("and the edge shows severed", w.is_severed(w.graph.edge_between(1, 2), 0) and w.is_severed(w.graph.edge_between(0, 1), 0))
	w.remove_stack(raider)
	t.near("repair is free the moment it leaves", SupplyRules.report(w, army)["shortfall"], before["shortfall"], 0.001)

func _test_foraging_pillages() -> void:
	var w := _world()
	var coin_before: float = w.nation(0).coin
	var s := w.add_stack(0, 3, _inf(3))            # enemy farm
	SupplyPhase.feed(w, s)
	t.check("pillaging a farm kills two turns of yield", w.graph.site(3).pillaged_until == w.turn + 2)
	SupplyPhase.feed(w, s)
	t.check("and it accumulates", w.graph.site(3).pillaged_until == w.turn + 4)
	t.near("a farm pays no coin", w.nation(0).coin, coin_before, 0.001)
	s.site_id = 6
	SupplyPhase.feed(w, s)
	t.near("a village pays 2 coin once", w.nation(0).coin, coin_before + 2.0, 0.001)
	SupplyPhase.feed(w, s)
	t.near("not twice while it is still pillaged", w.nation(0).coin, coin_before + 2.0, 0.001)
	s.site_id = 7
	SupplyPhase.feed(w, s)
	t.near("a market pays 10", w.nation(0).coin, coin_before + 12.0, 0.001)
	t.check("and stays pillaged 3 turns", w.graph.site(7).pillaged_until == w.turn + 3)
	# Friendly ground is not pillaged.
	var home := w.add_stack(0, 4, _inf(2))
	SupplyPhase.feed(w, home)
	t.check("our own farm is untouched", w.graph.site(4).pillaged_until == 0 and not home.supply_report["foraging"])

func _test_desertion() -> void:
	var w := _world()
	var s := w.add_stack(0, 2, _inf(4), 20.0)      # the crossroads feeds nobody, no depot stock
	SupplyPhase.run(w)
	t.check("one turn under 30 loses nothing yet", s.size() == 4 and s.hunger == 1)
	SupplyPhase.run(w)
	t.check("the second turn costs a regiment", s.size() == 3 and s.hunger == 0)
	s.supply = 100.0
	s.hunger = 1
	w.graph.site(0).stock = 100.0
	s.site_id = 0
	SupplyPhase.run(w)
	t.check("being fed resets the count", s.hunger == 0 and s.size() == 3)
	var last := w.add_stack(0, 2, _inf(1), 0.0)
	for i in 2:
		SupplyPhase.run(w)
	t.check("a stack that loses its last regiment is removed", not w.stacks.has(last))
	# The warning line, once, on the way down.
	var w2 := _world()
	var s2 := w2.add_stack(0, 2, _inf(4), 55.0)
	SupplyPhase.run(w2)
	SupplyPhase.run(w2)
	var warned := 0
	for line in w2.events:
		if line.contains("short on supply"):
			warned += 1
	t.check("crossing 50 is logged once", warned == 1, str(w2.events))
	# Opening stock from the setup hook.
	var fresh := t.world()
	t.near("every depot opens the run with the configured stock", fresh.graph.site(1).stock, 60.0, 0.001)
```

- [ ] **Step 2: Run to verify it fails** — `-- supply`.

- [ ] **Step 3: Implement**

`game/scripts/sim/phases/supply_phase.gd`:
```gdscript
class_name SupplyPhase
extends RefCounted

## WS-A. Depots fill from the farms that can reach them, then every stack eats
## in id order (so two stacks leaning on one depot always split it the same
## way), then hunger takes its toll.

static func run(world: World) -> void:
	refill_depots(world)
	var ordered: Array = world.stacks.duplicate()
	ordered.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	for s in ordered:
		feed(world, s)
	for s in ordered:
		if world.stacks.has(s):
			_starve(world, s)

## Each farm's yield goes to the nearest friendly, ready depot within reach
## (hops); a farm with none keeps its yield for foragers only.
static func refill_depots(world: World) -> void:
	var reach := int(GameConfig.logistics["depot_farm_reach"])
	for farm in world.graph.sites:
		if farm.kind != Site.Kind.FARM:
			continue
		var owner := Holdings.site_owner(world, farm)
		if owner < 0:
			continue
		var amount := Yields.supply(farm, world.graph.region_of(farm.id), world)
		if amount <= 0.0:
			continue
		var ex := Pathing.explore(world, farm.id, owner, Pathing.Cost.HOPS)
		var best: Site = null
		var best_d := INF
		for s in world.graph.sites:
			if not Holdings.is_friendly_depot(world, s, owner):
				continue
			var d: float = ex["dist"][s.id]
			if d <= float(reach) and d < best_d:
				best_d = d
				best = s
		if best != null:
			best.stock = minf(Yields.depot_capacity(best, world), best.stock + amount)

## Apply one stack's report: drain what it ate, pillage if it foraged hostile
## ground, move the level, and leave the breakdown on the stack for the UI.
static func feed(world: World, s: Stack) -> void:
	var r := SupplyRules.report(world, s)
	var site := world.graph.site(s.site_id)
	if r["local_from_stock"]:
		site.stock = maxf(0.0, site.stock - float(r["local"]))
	if int(r["depot_id"]) >= 0:
		var depot := world.graph.site(int(r["depot_id"]))
		depot.stock = maxf(0.0, depot.stock - float(r["depot_draw"]))
	if r["foraging"]:
		pillage(world, site, s.nation_id)
	var warn := float(GameConfig.logistics["supply_warning"])
	var before := s.supply
	s.supply = clampf(s.supply + float(r["delta"]), 0.0, 100.0)
	if before >= warn and s.supply < warn:
		world.record("%s is short on supply (%d%%)" % [s.label, int(round(s.supply))])
	s.supply_report = r

## Appendix B's pillage table. A site already pillaged pays no coin again but
## its ruin extends; a farm's ruin accumulates per turn stood on.
static func pillage(world: World, site: Site, by_nation: int) -> void:
	var L := GameConfig.logistics
	var fresh := world.turn >= site.pillaged_until
	var n := world.nation(by_nation)
	match site.kind:
		Site.Kind.FARM:
			site.pillaged_until = maxi(site.pillaged_until, world.turn) + int(L["pillage_farm_turns"])
		Site.Kind.VILLAGE:
			if fresh:
				n.coin += float(L["pillage_village_coin"])
				site.pillaged_until = world.turn + int(L["pillage_village_turns"])
		Site.Kind.MINE:
			if fresh:
				n.coin += float(L["pillage_mine_coin"])
				site.pillaged_until = world.turn + int(L["pillage_mine_turns"])
		Site.Kind.MARKET:
			if fresh:
				n.coin += float(L["pillage_market_coin"])
				site.pillaged_until = world.turn + int(L["pillage_market_turns"])
		Site.Kind.NODE:
			if fresh:
				site.pillaged_until = world.turn + int(L["pillage_node_turns"])
		# DEPOT: its stock is eaten through local feed; taking it is Occupation's business.
		# FEATURE: nothing to ruin.

## Under the desertion threshold a regiment walks away every `desertion_every`
## turns; being fed again resets the count.
static func _starve(world: World, s: Stack) -> void:
	var L := GameConfig.logistics
	if s.supply >= float(L["desertion_below"]):
		s.hunger = 0
		return
	s.hunger += 1
	if s.hunger < int(L["desertion_every"]):
		return
	s.hunger = 0
	if s.size() > 0:
		s.regiments.remove_at(s.size() - 1)
		world.record("%s lost a regiment to desertion" % s.label)
	if s.size() == 0:
		world.record("%s dissolved" % s.label)
		world.remove_stack(s)
```

`game/scripts/sim/logistics/logistics_setup.gd`:
```gdscript
class_name LogisticsSetup
extends RefCounted

## WS-A's run-start hook: every depot that exists when the world is born opens
## with the configured stock. Map data has no stock field on purpose — a depot
## is a depot, and how full it starts is a tuning number, not a map fact.

static func run(world: World) -> void:
	for s in world.graph.sites:
		if Holdings.depot_ready(world, s):
			s.stock = float(GameConfig.logistics["depot_initial_stock"])
```
In `world_setup.gd`, change the initializer line to `static var _hooks: Array[Callable] = [LogisticsSetup.run]` and add `LogisticsSetup.run   # WS-A  opening depot stock` to the header list.

- [ ] **Step 4: Re-import, run** — `-- supply`, then the whole suite. `test_world.gd`'s setup-hook test asserts `hooks().is_empty()` at its start; it now must not: **that assertion is the one seam edit this task makes outside WS-A files** — change it to assert the registry contains `LogisticsSetup.run` and that the test's own appended hook is erased afterwards. Say so in the report. `test_campaign_shell.gd` uses a world where the depot now opens at 60 stock; nothing there asserts stock.
- [ ] **Step 5: Stage.** Message: `Feed armies from depots and the land each turn`

---

### Task 6: OccupationPhase

**Files:**
- Modify: `game/scripts/sim/phases/occupation_phase.gd`
- Modify: `game/tests/test_supply.gd` (fill `_test_occupation`)

**Interface:** `OccupationPhase.run(world)`. A garrison is a stack with `order == "hold"` and an empty path. Each turn: every site's `garrison_nation` is recomputed (−1 unless garrisoned); a region's owner becomes the nation garrisoning **more than half** of its villages and market town; otherwise ownership is unchanged. Log line: `"%s is now held by %s"`.

- [ ] **Step 1: Write the failing test**
```gdscript
func _test_occupation() -> void:
	var w := _world()
	var s := w.add_stack(0, 6, _inf(2))            # standing on Foe Village, no hold order
	OccupationPhase.run(w)
	t.check("passing through changes nothing", w.graph.region(1).owner == 1 and w.graph.site(6).garrison_nation == -1)
	s.order = "hold"
	OccupationPhase.run(w)
	t.check("a holding stack garrisons its site", w.graph.site(6).garrison_nation == 0)
	t.check("one of two is not a majority", w.graph.region(1).owner == 1)
	var m := w.add_stack(0, 7, _inf(1))
	m.order = "hold"
	OccupationPhase.run(w)
	t.check("village and market both held flips the region", w.graph.region(1).owner == 0)
	t.check("the flip is logged", w.events[w.events.size() - 1].contains("Foeland is now held by Home"))
	w.remove_stack(m)
	OccupationPhase.run(w)
	t.check("losing the majority does not flip it back on its own", w.graph.region(1).owner == 0)
	t.check("but the empty market is nobody's garrison", w.graph.site(7).garrison_nation == -1)
	s.path = [3] as Array[int]
	OccupationPhase.run(w)
	t.check("a holding stack with a route is marching, not garrisoning", w.graph.site(6).garrison_nation == -1)
```

- [ ] **Step 2: Run to verify it fails** — `-- supply`.

- [ ] **Step 3: Implement**
```gdscript
class_name OccupationPhase
extends RefCounted

## WS-A. Holding a region is splitting: it belongs to whoever garrisons most
## of its villages and its market town. A stack passing through changes
## nothing, and an empty region keeps its owner.

static func run(world: World) -> void:
	for site in world.graph.sites:
		site.garrison_nation = -1
	for s in world.stacks:
		if s.order == "hold" and s.path.is_empty() and s.size() > 0:
			world.graph.site(s.site_id).garrison_nation = s.nation_id
	for r in world.graph.regions:
		var total := 0
		var held := {}
		for sid in r.sites:
			var site := world.graph.site(sid)
			if site.kind != Site.Kind.VILLAGE and site.kind != Site.Kind.MARKET:
				continue
			total += 1
			if site.garrison_nation >= 0:
				held[site.garrison_nation] = int(held.get(site.garrison_nation, 0)) + 1
		for nation_id in held:
			if int(held[nation_id]) * 2 > total and r.owner != nation_id:
				r.owner = nation_id
				world.record("%s is now held by %s" % [r.name, world.nation(nation_id).name])
```

- [ ] **Step 4: Run** — `-- supply`.
- [ ] **Step 5: Stage.** Message: `Regions belong to whoever garrisons their villages`

---

### Task 7: Orders

**Files:**
- Create: `game/scripts/sim/logistics/orders.gd`
- Modify: `game/tests/test_supply.gd` (fill `_test_orders`)

**Interfaces produced:**
```gdscript
Orders.move(world, stack, to_site: int) -> bool          # path via Pathing.shortest; false if unreachable; clears a hold
Orders.hold(world, stack) -> void                        # order "hold", path cleared (garrison here)
Orders.detach(world, stack, n: int, to_site: int, then_hold := false) -> Stack   # null if n not in 1..size-1 or unreachable
Orders.build_depot(world, nation: Nation, site: Site) -> bool
Orders.can_build_depot(world, nation, site) -> String    # "" when allowed, else the reason
```
Detach takes the last `n` regiments of the roster (map rosters list cavalry and archers last, so a small detachment is the fast part). The detachment has no leader: `quality = parent.quality × detach_quality`, `leader_id = -1`. `then_hold` sets `order = "hold"` with the route still to walk, so it garrisons on arrival (OccupationPhase counts a garrison only when the path is empty). Build depot: site friendly to the nation, kind FARM / VILLAGE / FEATURE, no depot (ready or building) already in the region, coin ≥ cost; the site becomes a DEPOT with `stock 0` and `depot_ready_turn = turn + build_turns`; the coin is spent now.

- [ ] **Step 1: Write the failing test**
```gdscript
func _test_orders() -> void:
	var w := _world()
	var s := w.add_stack(0, 0, _inf(12))
	t.check("move plans the road", Orders.move(w, s, 6) and s.path == ([1, 2, 3, 6] as Array[int]))
	s.order = "hold"
	Orders.move(w, s, 2)
	t.check("a move cancels a hold", s.order == "" and s.path == ([1, 2] as Array[int]))
	Orders.hold(w, s)
	t.check("hold clears the route", s.order == "hold" and s.path.is_empty())
	t.check("an unreachable order is refused", not Orders.move(w, s, 0) and s.order == "hold")

	var d := Orders.detach(w, s, 3, 4, true)
	t.check("detach makes a new stack of the last three", d != null and d.size() == 3 and s.size() == 9)
	t.check("it inherits supply, loses the leader, and walks to its site holding",
		is_equal_approx(d.supply, s.supply) and d.leader_id == -1 and is_equal_approx(d.quality, 0.5)
		and d.order == "hold" and d.path == ([1, 4] as Array[int]))
	t.check("detaching everything is refused", Orders.detach(w, s, 9, 4) == null and s.size() == 9)
	t.check("detaching nothing is refused", Orders.detach(w, s, 0, 4) == null)
	t.check("detachments are labelled", d.label.contains("detachment"))

	var n := w.nation(0)
	var cross := w.graph.site(2)
	t.check("a friendly feature can take a depot", Orders.can_build_depot(w, n, cross) == "")
	t.check("but the region already has one", Orders.can_build_depot(w, n, cross) == "" and not Orders.build_depot(w, n, cross) or true)
```
Stop: that last line is self-contradictory. Replace the last three lines with:
```gdscript
	var n := w.nation(0)
	var cross := w.graph.site(2)
	t.check("Homeland already has a depot, so a second is refused",
		Orders.can_build_depot(w, n, cross).contains("already") and not Orders.build_depot(w, n, cross))
	t.check("enemy ground is refused", Orders.can_build_depot(w, n, w.graph.site(3)).contains("not yours"))
	# Take Foeland's market and village so it is ours, then build there.
	w.graph.region(1).owner = 0
	var far := w.graph.site(5)
	n.coin = 30.0
	t.check("too poor is refused", Orders.can_build_depot(w, n, far).contains("coin"))
	n.coin = 60.0
	t.check("a friendly farm can be built on", Orders.build_depot(w, n, far))
	t.check("it costs 40 and is a depot under construction", is_equal_approx(n.coin, 20.0)
		and far.kind == Site.Kind.DEPOT and far.depot_ready_turn == w.turn + 2 and not Holdings.depot_ready(w, far))
	t.check("a second in the same region is refused", Orders.can_build_depot(w, n, w.graph.site(8)).contains("already"))
	w.turn += 2
	t.check("two turns later it is ready", Holdings.depot_ready(w, far))
```

- [ ] **Step 2: Run to verify it fails** — `-- supply`.

- [ ] **Step 3: Implement**
```gdscript
class_name Orders
extends RefCounted

## Everything a player or an AI can tell an army to do. The only code that
## writes Stack.path and Stack.order, so the UI, the scripted enemies and WS-D's
## planner all go through one door.

static func move(world: World, s: Stack, to_site: int) -> bool:
	if to_site == s.site_id:
		return false
	var path := Pathing.shortest(world, s.site_id, to_site, s.nation_id)
	if path.is_empty():
		return false
	s.path = path
	s.order = ""
	return true

static func hold(world: World, s: Stack) -> void:
	s.path.clear()
	s.order = "hold"

## Split the last `n` regiments off as their own stack and send them to
## `to_site`. A detachment with no leader of its own fights at a discount;
## `then_hold` makes it garrison where it arrives.
static func detach(world: World, s: Stack, n: int, to_site: int, then_hold := false) -> Stack:
	if n < 1 or n >= s.size():
		return null
	var roster: Array = []
	for i in range(s.size() - n, s.size()):
		roster.append(s.regiments[i])
	var d := world.add_stack(s.nation_id, s.site_id, roster, s.supply)
	d.quality = s.quality * float(GameConfig.logistics["detach_quality"])
	d.leader_id = -1
	d.label = "%s detachment %d" % [world.nation(s.nation_id).name, d.id]
	if to_site != s.site_id and not move(world, d, to_site):
		world.remove_stack(d)
		return null
	s.regiments.resize(s.size() - n)
	if then_hold:
		d.order = "hold"
	world.record("%s detached %d regiments toward %s" % [s.label, n, world.graph.site(to_site).name])
	return d

## "" when a depot can go here, otherwise why not — the UI shows the reason.
static func can_build_depot(world: World, nation: Nation, site: Site) -> String:
	var L := GameConfig.logistics
	if not Holdings.is_friendly(world, site, nation.id):
		return "%s is not yours" % site.name
	if site.kind != Site.Kind.FARM and site.kind != Site.Kind.VILLAGE and site.kind != Site.Kind.FEATURE:
		return "a depot needs a farm, a village or open ground"
	for other in world.graph.sites_in(site.region_id, Site.Kind.DEPOT):
		return "%s already has a depot at %s" % [world.graph.region_of(site.id).name, other.name]
	if nation.coin < float(L["depot_cost"]):
		return "needs %d coin" % int(L["depot_cost"])
	return ""

static func build_depot(world: World, nation: Nation, site: Site) -> bool:
	if can_build_depot(world, nation, site) != "":
		return false
	var L := GameConfig.logistics
	nation.coin -= float(L["depot_cost"])
	site.kind = Site.Kind.DEPOT
	site.stock = 0.0
	site.depot_ready_turn = world.turn + int(L["depot_build_turns"])
	world.record("%s began a depot at %s" % [nation.name, site.name])
	return true
```

- [ ] **Step 4: Re-import, run** — `-- supply`.
- [ ] **Step 5: Stage.** Message: `Add move, hold, detach and build-depot orders`

---

### Task 8: Scripted enemies and the two scenarios

**Files:**
- Modify: `game/scripts/sim/logistics/scripted_enemy.gd` (replace the stub)
- Create: `game/scripts/sim/logistics/logistics_scenarios.gd`
- Modify: `game/tests/test_movement.gd` (fill the last four tests)

**Interfaces produced:**
```gdscript
ScriptedEnemy.issue_orders(world)        # nations with weights["scripted"] == "marcher" | "raider"
LogisticsScenarios.all() -> Array[Dictionary]      # [{name, lesson}]
LogisticsScenarios.world(index: int, seed := 1) -> World
LogisticsScenarios.status(index: int, world) -> Dictionary   # {text, won, lost}
```
Marcher (every stack of that nation): target = the player's nearest ready depot by movement cost; if a route exists, `Orders.move` (re-planned every turn); if none (blocked), `Orders.hold`. When supply < `marcher_split_below` and size > `big_stack`, detach half toward the nearest reachable friendly-or-neutral farm not on its own site (once; halves are under the size guard). Raider (≤ `raider_max_regiments`): if any hostile stack bigger than a raider stands on its site or an adjacent one, flee to an adjacent site with no hostile presence and no such threat adjacent, else stay; otherwise target the first interior site of the route from the player's largest stack to its nearest depot (with_stock false); if that route has no interior site, the player's nearest farm; order "" (never hold: a raider that garrisons a village would occupy it).

- [ ] **Step 1: Write the failing tests**
```gdscript
func _test_marcher() -> void:
	var w := _world()
	w.nation(1).weights["scripted"] = "marcher"
	w.graph.site(0).stock = 100.0
	var m := w.add_stack(1, 8, _inf(12), 100.0)     # at Fourth Farm, the far end of the road
	ScriptedEnemy.issue_orders(w)
	t.check("the marcher heads for the player's depot", m.path == ([7, 6, 3, 2, 1, 0] as Array[int]))
	m.supply = 35.0
	ScriptedEnemy.issue_orders(w)
	t.check("under 40 it splits in two", m.size() == 6 and w.stacks_of(1).size() == 2)
	var half := w.stacks_of(1)[1]
	t.check("the half heads for a farm", half.size() == 6 and not half.path.is_empty()
		and w.graph.site(half.path[half.path.size() - 1]).kind == Site.Kind.FARM)
	ScriptedEnemy.issue_orders(w)
	t.check("a six does not split again", w.stacks_of(1).size() == 2)
	# Blocked: a player stack on the only road makes it hold where it is.
	var block := w.add_stack(0, 3, _inf(8))
	ScriptedEnemy.issue_orders(w)
	t.check("with the road held it holds instead of walking into a wall", m.order == "hold" and m.path.is_empty())

func _test_raider() -> void:
	var w := _world()
	w.nation(1).weights["scripted"] = "raider"
	w.graph.site(0).stock = 80.0
	var army := w.add_stack(0, 3, _inf(8))        # the player's largest, on Enemy Farm, 3 hops from the depot
	var r := w.add_stack(1, 8, _cav(3))
	ScriptedEnemy.issue_orders(w)
	t.check("the raider goes for the road between depot and army (the crossroads)",
		not r.path.is_empty() and r.path[r.path.size() - 1] == 2, str(r.path))
	r.site_id = 2
	r.path.clear()
	army.site_id = 1                               # the army comes back to the village next door
	ScriptedEnemy.issue_orders(w)
	t.check("a big stack next door makes it flee", not r.path.is_empty() and r.path[0] != 1, str(r.path))
	t.check("raiders never hold", r.order == "")
```
For the scenarios:
```gdscript
func _test_the_march_dumb_and_smart() -> void:
	var names: Array = []
	for s in LogisticsScenarios.all():
		names.append(s["name"])
	t.check("both Appendix B scenarios exist", names == ["The March", "The Siege"])

	# Dumb: cross the ford as one stack, hold both villages with it and a single detachment.
	var w := LogisticsScenarios.world(0)
	var me := w.stacks_of(0)[0]
	var east := _site(w, "Fording East")
	var reed := _site(w, "Reed Landing")
	Orders.move(w, me, east.id)
	TurnResolver.end_turn(w)
	TurnResolver.end_turn(w)
	t.check("two turns to cross with twelve", me.site_id == east.id)
	Orders.detach(w, me, 1, reed.id, true)
	Orders.hold(w, me)
	var lost := false
	for i in 9:
		TurnResolver.end_turn(w)
		lost = lost or LogisticsScenarios.status(0, w)["lost"]
	t.check("holding River East as one hungry stack fails (%s)" % LogisticsScenarios.status(0, w)["text"], lost)

	# Smart: one regiment per village, three on the farm, the rest back on a friendly farm.
	var w2 := LogisticsScenarios.world(0)
	var me2 := w2.stacks_of(0)[0]
	Orders.move(w2, me2, _site(w2, "Fording East").id)
	TurnResolver.end_turn(w2)
	TurnResolver.end_turn(w2)
	Orders.detach(w2, me2, 1, _site(w2, "Reed Landing").id, true)
	Orders.detach(w2, me2, 3, _site(w2, "East Bank Farm").id, true)
	Orders.detach(w2, me2, 1, _site(w2, "Fording East").id, true)   # same site: an order to hold here
	Orders.move(w2, me2, _site(w2, "West Bank Farm").id)
	var won := false
	for i in 12:
		TurnResolver.end_turn(w2)
		if me2.path.is_empty() and me2.order != "hold":
			Orders.hold(w2, me2)
		won = won or LogisticsScenarios.status(0, w2)["won"]
	t.check("dispersed to eat and garrisoned, River East is held for six turns above 50 (%s)"
		% LogisticsScenarios.status(0, w2)["text"], won)

func _test_the_siege_is_winnable_without_a_fight() -> void:
	var w := LogisticsScenarios.world(1)
	var marcher := w.stacks_of(1)[0]
	t.check("the marcher sits on our frontier depot with fourteen", marcher.size() == 14
		and w.graph.site(marcher.site_id).name == "Riverwatch Depot")
	var me := w.stacks_of(0)[0]
	t.check("we have eight", me.size() == 8)
	# Turn 1: a three-cavalry raider to Fordwatch, the marcher's only road home.
	var raider := Orders.detach(w, me, 3, _site(w, "Fordwatch").id, false)
	t.check("the raider is fast enough to get there this turn", raider != null and SupplyRules.move_points(raider) == 5)
	for i in 8:
		TurnResolver.end_turn(w)
	t.check("cut off, the marcher starves below 40 (%d%%)" % int(marcher.supply), marcher.supply < 40.0)
	t.check("it never got past the raider", w.graph.site(marcher.site_id).name == "Riverwatch Depot")
	t.check("our raider still stands", w.stacks.has(raider) and raider.size() == 3)
	t.check("the scenario reports the strangling as progress", LogisticsScenarios.status(1, w)["text"].contains("starving"))

func _site(w: World, name: String) -> Site:
	for s in w.graph.sites:
		if s.name == name:
			return s
	t.check("site '%s' exists" % name, false)
	return w.graph.site(0)
```
`Orders.detach(..., same site, true)` above: detach refuses `to_site == site` only in `move`; in `detach` the "to_site != s.site_id" guard skips the move and the new stack holds in place. That is the intended "leave one here to hold" verb.

- [ ] **Step 2: Run to verify it fails** — `-- movement`.

- [ ] **Step 3: Implement ScriptedEnemy**
```gdscript
class_name ScriptedEnemy
extends RefCounted

## Appendix B's two scripted enemies, until WS-D's real AI exists. A nation
## whose `weights` has "scripted": "marcher" | "raider" is driven here from
## MovementPhase; WS-D's AiPhase skips those nations. Both re-decide every turn
## from the visible world, through Orders and Pathing like everyone else.

static func issue_orders(world: World) -> void:
	for n in world.nations:
		var mode := str(n.weights.get("scripted", ""))
		if mode == "":
			continue
		var mine: Array = world.stacks_of(n.id).duplicate()
		mine.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
		for s in mine:
			if not world.stacks.has(s):
				continue
			match mode:
				"marcher":
					_marcher(world, s)
				"raider":
					_raider(world, s)

## One big stack follows the road toward the player's depot, foraging as it
## goes, and splits in two when it starts to starve.
static func _marcher(world: World, s: Stack) -> void:
	var L := GameConfig.logistics
	var player := world.player()
	if player == null:
		return
	if s.supply < float(L["marcher_split_below"]) and s.size() > int(L["big_stack"]):
		var farm := _nearest_site(world, s, Site.Kind.FARM, true)
		if farm >= 0:
			Orders.detach(world, s, s.size() / 2, farm)
	var target := _nearest_depot_of(world, s, player.id)
	if target < 0 or target == s.site_id or not Orders.move(world, s, target):
		Orders.hold(world, s)

## Three fast regiments sit on the road between the player's depot and their
## biggest army, and run from anything that could catch them.
static func _raider(world: World, s: Stack) -> void:
	var player := world.player()
	if player == null:
		return
	s.order = ""
	var threat := _threat_adjacent(world, s)
	if threat >= 0:
		var away := _escape(world, s)
		if away >= 0:
			s.path = [away] as Array[int]
		else:
			s.path.clear()
		return
	var target := _raid_target(world, player)
	if target < 0 or target == s.site_id:
		s.path.clear()
		return
	Orders.move(world, s, target)

static func _raid_target(world: World, player: Nation) -> int:
	var largest: Stack = null
	for st in world.stacks_of(player.id):
		if largest == null or st.size() > largest.size():
			largest = st
	if largest != null:
		var d := Pathing.nearest_depot(world, largest.site_id, player.id, false)
		if not d.is_empty() and int(d["hops"]) >= 2:
			return int(d["sites"][0])
	# No route to cut: the nearest player farm will do.
	var best := -1
	var best_d := INF
	for site in world.graph.sites:
		if site.kind == Site.Kind.FARM and Holdings.is_friendly(world, site, player.id):
			var dist: float = site.pos.distance_to(world.graph.site(largest.site_id).pos) if largest != null else 0.0
			if dist < best_d:
				best_d = dist
				best = site.id
	return best

## A hostile stack too big to be a raider on this site or the next.
static func _threat_adjacent(world: World, s: Stack) -> int:
	var raider_max := int(GameConfig.logistics["raider_max_regiments"])
	for other in world.stacks:
		if not world.hostile(other.nation_id, s.nation_id) or other.size() <= raider_max:
			continue
		if other.site_id == s.site_id or world.graph.edge_between(other.site_id, s.site_id) != null:
			return other.site_id
	return -1

## An adjacent site with nobody hostile on it and no big hostile stack next to it.
static func _escape(world: World, s: Stack) -> int:
	var raider_max := int(GameConfig.logistics["raider_max_regiments"])
	for nb in world.graph.neighbors(s.site_id):
		if world.hostile_presence(nb, s.nation_id):
			continue
		var safe := true
		for other in world.stacks:
			if world.hostile(other.nation_id, s.nation_id) and other.size() > raider_max \
					and (other.site_id == nb or world.graph.edge_between(other.site_id, nb) != null):
				safe = false
				break
		if safe:
			return nb
	return -1

static func _nearest_depot_of(world: World, s: Stack, nation_id: int) -> int:
	var ex := Pathing.explore(world, s.site_id, s.nation_id, Pathing.Cost.MOVEMENT)
	var best := -1
	var best_d := INF
	for site in world.graph.sites:
		if Holdings.is_friendly_depot(world, site, nation_id) and ex["dist"][site.id] < best_d:
			best_d = ex["dist"][site.id]
			best = site.id
	return best

## Nearest reachable site of a kind that is not hostile ground, other than here.
static func _nearest_site(world: World, s: Stack, kind: int, not_here: bool) -> int:
	var ex := Pathing.explore(world, s.site_id, s.nation_id, Pathing.Cost.MOVEMENT)
	var best := -1
	var best_d := INF
	for site in world.graph.sites:
		if site.kind != kind or (not_here and site.id == s.site_id):
			continue
		if Holdings.is_hostile_ground(world, site, s.nation_id) or world.hostile_presence(site.id, s.nation_id):
			continue
		if ex["dist"][site.id] < best_d:
			best_d = ex["dist"][site.id]
			best = site.id
	return best
```
Note for `_test_marcher`: the marcher at Fourth Farm splitting sends the half to the nearest *non-hostile* farm; with region 1 owned by the Foe, Far Farm and Enemy Farm are its own ground, so the half goes to Far Farm (via 7, 6, 3, river). Fine.

- [ ] **Step 4: Implement LogisticsScenarios**
```gdscript
class_name LogisticsScenarios
extends RefCounted

## Appendix B's two logistics set-pieces as map-data variants of the prototype
## map. `world()` builds one; `status()` reads progress back out of the world's
## own state and log, so it needs no state of its own and a headless test can
## ask the same question the HUD does.

const HOLD_TURNS := 6            # The March: turns River East must be held
const HOLD_ABOVE := 50.0         # ... with every stack at or above this supply
const MARCH_DEADLINE := 20
const SIEGE_STARVED := 40.0      # The Siege: the marcher under this is "starving"
const SIEGE_DEADLINE := 25

static func all() -> Array[Dictionary]:
	return [
		{
			"name": "The March",
			"lesson": "Take River East and hold it six turns without any stack dropping under 50 supply. Split to forage and garrison; one stack cannot eat there.",
		},
		{
			"name": "The Siege",
			"lesson": "A 14-stack sits on your frontier depot. Do not fight it: cut its road home with a raider, let it starve and split, then take the pieces.",
		},
	]

static func world(index: int, seed := 1) -> World:
	var data := PrototypeMap.data()
	match index:
		0:
			data["stacks"] = [_stack(0, "Capital Depot", 8, 2, 2)]
		1:
			var riverwatch: Dictionary = data["sites"][12]
			riverwatch["kind"] = "depot"
			riverwatch["name"] = "Riverwatch Depot"
			data["stacks"] = [_stack(0, "Capital Depot", 6, 2, 0), _stack(1, "Riverwatch Depot", 10, 2, 2)]
	var w := World.from_map(data, seed)
	if index == 1:
		w.nation(1).weights["scripted"] = "marcher"
	return w

static func _stack(nation: int, site: String, inf: int, cav: int, arc: int) -> Dictionary:
	var roster: Array = []
	for i in inf:
		roster.append("infantry")
	for i in cav:
		roster.append("cavalry")
	for i in arc:
		roster.append("archers")
	return {"nation": nation, "site": site, "supply": 100, "regiments": roster}

static func status(index: int, w: World) -> Dictionary:
	match index:
		0:
			return _march_status(w)
		1:
			return _siege_status(w)
	return {"text": "", "won": false, "lost": false}

static func _march_status(w: World) -> Dictionary:
	var player := w.player()
	var region := _region_named(w, "River East")
	var captured := _last_event_turn(w, "River East is now held by %s" % player.name)
	if region.owner != player.id or captured < 0:
		var late := w.turn > MARCH_DEADLINE
		return {"text": "River East is not yours yet (turn %d of %d)." % [w.turn, MARCH_DEADLINE], "won": false, "lost": late}
	var held := w.turn - captured
	var hungry := _last_event_turn(w, "%s " % player.name, "short on supply") > captured
	if hungry:
		return {"text": "A stack fell under 50 supply while holding. Lost.", "won": false, "lost": true}
	if held >= HOLD_TURNS:
		return {"text": "River East held %d turns above 50 supply. Won." % held, "won": true, "lost": false}
	return {"text": "River East held %d of %d turns; keep every stack above 50." % [held, HOLD_TURNS], "won": false, "lost": w.turn > MARCH_DEADLINE}

static func _siege_status(w: World) -> Dictionary:
	var player := w.player()
	var capital := _region_named(w, "Capital Plain")
	if capital.owner != player.id:
		return {"text": "The capital fell. Lost.", "won": false, "lost": true}
	var west: Array = []
	for s in w.stacks:
		if s.nation_id != player.id and w.graph.region_of(s.site_id).owner == player.id:
			west.append(s)
	if west.is_empty():
		return {"text": "No enemy stands on your land. Won.", "won": true, "lost": false}
	var biggest: Stack = west[0]
	for s in west:
		if s.size() > biggest.size():
			biggest = s
	var starving := biggest.supply < SIEGE_STARVED
	var text := "%s: %d regiments at %d%% supply%s." % [
		biggest.label, biggest.size(), int(round(biggest.supply)), " — starving" if starving else ""]
	if west.size() > 1:
		text += " It has split into %d." % west.size()
	# WS-C turns "take the pieces" into battles; until then the strangle is the lesson.
	return {"text": text, "won": false, "lost": w.turn > SIEGE_DEADLINE}

static func _region_named(w: World, name: String) -> Region:
	for r in w.graph.regions:
		if r.name == name:
			return r
	return w.graph.region(0)

## The turn of the latest log line containing both needles, or -1.
static func _last_event_turn(w: World, needle: String, also := "") -> int:
	var found := -1
	for line in w.events:
		if line.contains(needle) and (also == "" or line.contains(also)):
			var head: String = line.substr(1, line.find(" ") - 1)
			found = int(head)
	return found
```

- [ ] **Step 5: Re-import, run** — `-- movement`, then everything. The two scenario tests are numeric: if "dumb" does not lose within nine turns or "smart" does not win within twelve, first check the rules against the worked example (Task 3 must still pass), then adjust the *orders* in the test (the sequence of detachments), never the rules. Record what was needed in the report.
- [ ] **Step 6: Stage.** Message: `Add the scripted marcher and raider and the two logistics scenarios`

---

### Task 9: The map layers — orders, breakdown, routes

**Files:**
- Modify (owned): `game/scripts/ui/layers/stacks_layer.gd`, `game/scripts/ui/layers/graph_layer.gd`
- Create (owned): `game/scripts/ui/layers/supply_layer.gd`
- Create: `game/tests/test_logistics_shell.gd`

Rules: layers only read the world and call `Orders`; every button ≥ 44 px; no simulation logic here.

**StacksLayer** (order 100) changes:
- `pressed`: a click on a site with a player stack selected calls `Orders.move` (any reachable site, not just adjacent); if the layer's detach mode is armed, it calls `Orders.detach(world, selected, count, site.id, true)` instead and disarms; if build mode is armed and the click is on the selected stack's own site, nothing (build acts immediately, see buttons).
- `buttons()`: `Hold` (selected player stack → `Orders.hold`), `Detach` (arms detach mode; label shows the count from the panel), `Build depot` (enabled when `Orders.can_build_depot(world, player, site_of_selected) == ""`; action builds), plus the existing `Clear order`.
- `panel()`: a `VBoxContainer` with a `Label` "Detach" and a `SpinBox` (min 1, max 15, value 3, 44 px tall) whose value is the detach count; the panel instance is created once and reused.
- `tooltip`: the supply breakdown formatted from `supply_report`, e.g.
  `Empire stack 1 — 8 infantry, 2 cavalry, 2 archers`
  `Supply 91% ↓ −4.6 · upkeep 36 · land 2 · depot 20 (3 hops from Capital Depot) · short 11`
  `foraging Fording East` on a third line when `foraging` is true. When `supply_report` is empty (turn 1): `Supply 100% · no turn yet`.

**GraphLayer** (order 0): the severed-edge dashes stay; add a hollow "under construction" ring around depots with `depot_ready_turn > turn`, and the tooltip on a depot appends `stock %d / %d` and `ready in %d turns` when building.

**SupplyLayer** (new, order 50): drawing only. For each stack: a small ▲ (green) or ▼ (red) glyph left of the stacks layer's label using `supply_report["delta"]` sign, and `"%d hops"` when `hops >= 0`. For the selected stack: its `supply_report["route"]` drawn as a dotted line in the nation color from the stack to the depot (only when `depot_id >= 0`). No tooltip, no buttons, `panel()` null.

- [ ] **Step 1: Write the failing shell test**

`game/tests/test_logistics_shell.gd` — hosts `campaign.tscn` like `test_campaign_shell.gd` does (copy its guarded instantiate/free pattern), then:
```gdscript
	var layers: Array[MapLayer] = view.layers
	var has_supply := false
	for l in layers:
		if l is SupplyLayer:
			has_supply = true
	t.check("the supply layer is registered", has_supply)
	var stacks: MapLayer = layers[layers.size() - 1]
	var labels: Array = []
	for b in stacks.buttons():
		labels.append(b["label"])
	t.check("the orders buttons exist", labels.has("Hold") and labels.has("Build depot") and labels.has("Clear order"))
	var detach_label := ""
	for lb in labels:
		if str(lb).begins_with("Detach"):
			detach_label = lb
	t.check("Detach shows its count", detach_label.contains("3"))
	t.check("the stacks layer has a panel with the detach count", stacks.panel() != null and stacks.panel() == stacks.panel())
	# Tooltip format after a turn.
	var me: Stack = view.world.stacks_of(view.world.player().id)[0]
	root._on_end_turn()
	var tip: String = stacks.tooltip(view.stack_pos(me))
	t.check("the breakdown names upkeep, land and depot in one line", tip.contains("upkeep") and tip.contains("depot") and tip.contains("Supply"))
	# Ordering through the layer: select, then click a site three hops away.
	view.selected = me
	var far := _site(view.world, "Fordwatch")
	t.check("a click on a reachable site orders a route", stacks.pressed(far.pos) and me.path.size() == 2 and me.path[me.path.size() - 1] == far.id)
```
plus the registration line in `campaign_root.gd`'s `LAYERS` (Task 10 lists it; add it here so this test can pass — it is the one-line additive hunk the seam allows):
```gdscript
	preload("res://scripts/ui/layers/supply_layer.gd"),
```

- [ ] **Step 2: Run to verify it fails** — `-- logistics_shell`.

- [ ] **Step 3: Implement the three layers**

`game/scripts/ui/layers/supply_layer.gd`:
```gdscript
class_name SupplyLayer
extends MapLayer

## Supply as a thing you can see: which way every army's level is going, how
## far its food travels, and — for the selected army — the road it comes by.
## Draws only; every number is read from SupplyPhase's report on the stack.

const ARROW := 6.0

func order() -> int:
	return 50

func draw(canvas: CanvasItem) -> void:
	if view.world == null:
		return
	if view.selected != null and view.world.stacks.has(view.selected):
		_draw_route(canvas, view.selected)
	for s in view.world.stacks:
		_draw_trend(canvas, s)

func _draw_trend(canvas: CanvasItem, s: Stack) -> void:
	if s.supply_report.is_empty():
		return
	var at := view.w2s(view.stack_pos(s)) + Vector2(-StacksLayer.DISC - ARROW - 4.0, 0.0)
	var delta := float(s.supply_report["delta"])
	var up := delta >= 0.0
	var col := ThemeColors.ACCENT if up else ThemeColors.ENEMY
	var tip := at + Vector2(0.0, -ARROW if up else ARROW)
	var base := at + Vector2(0.0, ARROW if up else -ARROW)
	canvas.draw_colored_polygon(PackedVector2Array([tip, base + Vector2(-ARROW, 0.0), base + Vector2(ARROW, 0.0)]), col)
	var hops := int(s.supply_report["hops"])
	if hops >= 0:
		canvas.draw_string(view.font, at + Vector2(-ARROW - 30.0, 4.0), "%d hop%s" % [hops, "" if hops == 1 else "s"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ThemeColors.TEXT_DIM)

func _draw_route(canvas: CanvasItem, s: Stack) -> void:
	if s.supply_report.is_empty() or int(s.supply_report["depot_id"]) < 0:
		return
	var col := view.world.nation(s.nation_id).color.lightened(0.2)
	var from := view.w2s(view.stack_pos(s))
	for sid in s.supply_report["route"]:
		var to := view.w2s(view.world.graph.site(sid).pos)
		MapLayer.dashes(canvas, from, to, col, 2.0, 6.0, 0.4)
		from = to
```

`stacks_layer.gd`: keep `DISC`, `order`, `draw`, `_draw_stack`, `_draw_path`, `_roster`, `_destination` as they are; replace `buttons`, `pressed`, `tooltip`, and add `panel`:
```gdscript
var _panel: VBoxContainer = null
var _count: SpinBox = null
var _detaching := false            # the next site click detaches instead of moving

func _player_stack() -> Stack:
	var s := view.selected
	if s == null or view.world == null or view.world.player() == null:
		return null
	if s.nation_id != view.world.player().id or not view.world.stacks.has(s):
		return null
	return s

func buttons() -> Array[Dictionary]:
	var has := func() -> bool:
		return _player_stack() != null
	var has_order := func() -> bool:
		var s := _player_stack()
		return s != null and (not s.path.is_empty() or s.order == "hold")
	var can_build := func() -> bool:
		var s := _player_stack()
		return s != null and Orders.can_build_depot(view.world, view.world.player(), view.world.graph.site(s.site_id)) == ""
	var can_detach := func() -> bool:
		var s := _player_stack()
		return s != null and s.size() > 1
	return [
		{"label": "Hold", "enabled": has, "action": func() -> void:
			var s := _player_stack()
			if s != null:
				Orders.hold(view.world, s)},
		{"label": "Detach %d" % _detach_count(), "enabled": can_detach, "action": func() -> void:
			_detaching = not _detaching},
		{"label": "Build depot", "enabled": can_build, "action": func() -> void:
			var s := _player_stack()
			if s != null:
				Orders.build_depot(view.world, view.world.player(), view.world.graph.site(s.site_id))},
		{"label": "Clear order", "enabled": has_order, "action": func() -> void:
			var s := _player_stack()
			if s != null:
				s.path.clear()
				s.order = ""
				_detaching = false},
	]

func _detach_count() -> int:
	return int(_count.value) if _count != null else 3

func panel() -> Control:
	if _panel == null:
		_panel = VBoxContainer.new()
		var title := Label.new()
		title.text = "Detach: regiments to split off"
		_panel.add_child(title)
		_count = SpinBox.new()
		_count.min_value = 1
		_count.max_value = 15
		_count.value = 3
		_count.custom_minimum_size = Vector2(110, 44)
		_panel.add_child(_count)
	return _panel

func pressed(world_pos: Vector2) -> bool:
	if view.world == null:
		return false
	var hit := view.stack_at(world_pos)
	if hit != null:
		view.selected = null if view.selected == hit else hit
		_detaching = false
		return true
	var s := _player_stack()
	if s == null:
		return false
	var site := view.site_at(world_pos)
	if site == null:
		return false
	if _detaching:
		_detaching = false
		return Orders.detach(view.world, s, mini(_detach_count(), s.size() - 1), site.id, true) != null
	if site.id == s.site_id:
		return false
	return Orders.move(view.world, s, site.id)

func tooltip(world_pos: Vector2) -> String:
	if view.world == null:
		return ""
	var s := view.stack_at(world_pos)
	if s == null:
		return ""
	var lines: PackedStringArray = ["%s — %s%s" % [s.label, _roster(s), _destination(s)]]
	var r := s.supply_report
	if r.is_empty():
		lines.append("Supply %d%% · no turn yet" % int(round(s.supply)))
		return "\n".join(lines)
	var delta := float(r["delta"])
	var line := "Supply %d%% %s %+.1f · upkeep %d · land %d" % [
		int(round(s.supply)), "▲" if delta >= 0.0 else "▼", delta, int(round(r["upkeep"])), int(round(r["local"]))]
	if int(r["depot_id"]) >= 0:
		line += " · depot %d (%d hops from %s)" % [int(round(r["delivered"])), int(r["hops"]), view.world.graph.site(int(r["depot_id"])).name]
	else:
		line += " · no depot in reach"
	if float(r["shortfall"]) > 0.0:
		line += " · short %d" % int(round(r["shortfall"]))
	lines.append(line)
	if r["foraging"]:
		lines.append("Foraging %s — it is being pillaged" % view.world.graph.site(s.site_id).name)
	return "\n".join(lines)
```
Note: `_detaching = false` must also happen in `_player_stack()`'s failure path if the selection changes; the shell clears `view.selected` on End Turn, so also reset `_detaching` inside `draw()` when `_player_stack() == null`.

`graph_layer.gd`: in `_draw_depot`, after the fill, `if s.depot_ready_turn > view.world.turn: canvas.draw_arc(at, GLYPH * 1.6, 0.0, TAU, 20, ThemeColors.WARN, 1.5)`; in `tooltip`, when `s.kind == Site.Kind.DEPOT`, append `" Stock %d / %d." % [int(s.stock), int(Yields.depot_capacity(s, world))]` and `" Ready in %d turns." % (s.depot_ready_turn - world.turn)` when building.

- [ ] **Step 4: Re-import, run** — `-- logistics_shell`, then the full suite; run the campaign scene headless with `--quit-after 30` (no SCRIPT ERROR); then launch it windowed once and check by eye: arrows and hops appear after End Turn, the selected stack shows its depot route, Detach arms and a site click splits the stack, Build depot works on a farm you own.
- [ ] **Step 5: Stage.** Message: `Show supply on every army and issue orders from the map`

---

### Task 10: Scenario picker in the shell (seam change) and docs

**Files:**
- Modify: `game/scripts/ui/campaign_root.gd` (exact edits below)
- Modify: `game/tests/test_logistics_shell.gd` (add picker checks)
- Modify: `README.md`, `docs/superpowers/plans/2026-09-21-logistics-roguelike-workstreams.md` (WS-A section: mark done, note the registry)

This is the one edit to a shared Phase 0 file. It is additive: a registry const, one HUD control, three small functions.

- [ ] **Step 1: Add the picker checks** to `test_logistics_shell.gd`:
```gdscript
	t.check("the scenario registry lists the logistics scenarios", CampaignRoot.SCENARIOS.size() >= 1)
	root.select_scenario(0, 0)      # first registry entry, first scenario: The March
	t.check("selecting a scenario rebuilds the world from it",
		view.world.stacks.size() == 1 and view.world.stacks[0].size() == 12)
	t.check("the status line carries the scenario's progress", root.scenario_text().contains("River East"))
	root.select_scenario(-1, 0)
	t.check("back to the open campaign", view.world.stacks.size() == 2)
```

- [ ] **Step 2: Edit `campaign_root.gd`**

After `const LAYERS`, add:
```gdscript
## Scenario providers, one preload per workstream. Each script exposes
## `static func all() -> Array[Dictionary]` ({name, lesson}),
## `static func world(index: int, seed: int) -> World` and
## `static func status(index: int, world: World) -> Dictionary` ({text, won, lost}).
## The picker lists "Campaign" and then every provider's scenarios in order.
const SCENARIOS: Array = [
	preload("res://scripts/sim/logistics/logistics_scenarios.gd"),
]

var _scenario_provider := -1        # index into SCENARIOS, -1 = the open campaign
var _scenario_index := 0
```
Replace `_seeded_world()` with:
```gdscript
func _seeded_world() -> World:
	if _scenario_provider >= 0:
		return SCENARIOS[_scenario_provider].world(_scenario_index, SEED)
	return World.from_map(PrototypeMap.data(), SEED)

## Switch the run to a scenario (or back to the campaign with provider -1) and
## rebuild the world from it.
func select_scenario(provider: int, index: int) -> void:
	_scenario_provider = provider
	_scenario_index = index
	_on_reset()

## The active scenario's progress line, or "" for the open campaign.
func scenario_text() -> String:
	if _scenario_provider < 0:
		return ""
	return str(SCENARIOS[_scenario_provider].status(_scenario_index, view.world)["text"])
```
In `_build_hud()`, after the `Tuning` button:
```gdscript
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(160, 44)
	picker.add_item("Campaign")
	for p in SCENARIOS.size():
		for sc in SCENARIOS[p].all():
			picker.add_item(str(sc["name"]))
	picker.item_selected.connect(func(i: int) -> void:
		if i == 0:
			select_scenario(-1, 0)
			return
		var n := 1
		for p in SCENARIOS.size():
			var count: int = SCENARIOS[p].all().size()
			if i < n + count:
				select_scenario(p, i - n)
				return
			n += count)
	controls.add_child(picker)
	_hud["scenario"] = picker
```
In `_refresh_status()`, after the status text is set: `var sc := scenario_text(); if sc != "": _hud["status"].text += " · " + sc`. And the info fallback line: when a scenario is active, show its `lesson` instead of the click hint.

- [ ] **Step 3: Run** — `-- logistics_shell`, then everything; headless scene run; then windowed: pick The March and The Siege from the dropdown.

- [ ] **Step 4: Docs.** README: a "Logistics" paragraph (hops + depot stock, upkeep curve, presence severs, the two scenarios, how to read the tooltip) and the new files in the layout block. Master plan: in the WS-A section add "Done: tasks 1–8; `CampaignRoot.SCENARIOS` registry added (additive, one preload per workstream); `MovementPhase` calls `ScriptedEnemy.issue_orders` for nations with `weights["scripted"]`, which WS-D's `AiPhase` must skip."

- [ ] **Step 5: Stage** — `git add game/scripts/ui/campaign_root.gd game/tests/test_logistics_shell.gd README.md docs/superpowers/plans/2026-09-21-logistics-roguelike-workstreams.md`. Message: `Add a scenario picker and document the logistics layer`

---

## Self-review notes

- **Spec coverage (Appendix B):** map data ✓ (Phase 0), depots and refill ✓ (T5), army supply level in the spec's order ✓ (T3/T5), worked example ✓ (T3), detachments/merge/leaders ✓ (T4/T7), movement points ✓ (T1/T4), occupation ✓ (T6), raiding as presence ✓ (Phase 0 + T2/T5 test), pillage table ✓ (T5; village "yield halved" is approximated as zero yield for the period, noted in code), scripted Marcher/Raider ✓ (T8), scenarios 1 and 3 ✓ (T8), UI one-glance rule ✓ (T9), tuning panel ✓ (generic, picks up `logistics` automatically). Out of WS-A: trade/caravans/escorts (WS-B, scenario 2), battles (WS-C), winter (optional, skipped).
- **Interface consistency:** `Orders.detach(world, stack, n, to_site, then_hold)` is used with five args in T8 and T9 and four in the master plan (default `false`) ✓; `Pathing.nearest_depot` returns `sites` and `edges` and `factor`, consumed by `SupplyRules.report` (T3) and `ScriptedEnemy` (T8) ✓; `SupplyRules.report` keys used by `SupplyPhase.feed`, `StacksLayer.tooltip`, `SupplyLayer` all listed in T3 ✓; `Holdings` used by T2, T3, T5, T7, T8 with the T1 signatures ✓.
- **Known numeric risk:** the two scenario tests in T8 and the "dumb loses / smart wins" thresholds depend on the prototype map's exact hop counts. The implementer adjusts the scripted orders, not the rules, and reports the final sequence.
