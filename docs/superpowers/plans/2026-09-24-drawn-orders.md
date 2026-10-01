# Drawn Orders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In battle, drag from a unit to draw its route (a group keeps its shape; a stroke ending on an enemy attacks it) and drag across the ground to set a formation line (infantry on the line, archers behind, cavalry on the wings), with time slowed while drawing — after first landing the three open battle-contact fixes.

**Architecture:** Routes are real sim orders on `Block` (`route`, `end_facing`, `route_target_id`) walked by `BattleSim._move`; `BattleSim` cleans strokes (resample, drop impassable samples, route river crossings over the bridge's two ends) and builds group routes and formation slots. `BattleView` turns gestures into those orders, slows the clock while a stroke is in progress, previews strokes and draws remaining routes.

**Tech Stack:** Godot 4.5 GDScript (CI) / 4.7.1 locally; headless runner `game/tests/run_tests.gd`.

**Spec:** `docs/superpowers/specs/2026-09-24-drawn-orders-design.md` (approved). Prerequisite fixes come from the battle-contact final review (`.superpowers/sdd/progress.md`, "Battle contact ledger").

## Global Constraints

- The sim stays `RefCounted`, rendering-free and deterministic.
- New tunables in `GameConfig.combat` and the tuning panels: `route_sample` 12.0, `route_reach` 2.0, `formation_rank_gap` 32.0, `draw_time_scale` 0.25.
- Existing claims are pass/fail bars: the combat suite (prints 88 = 87 real checks + runner line), WS-C's East Hill acceptance (`test_battle_bridge.gd`), every `test_contact.gd` rule. If a claim fails, tune only the battle-contact values (`seat_speed`, `push_*`, `pivot_angle`, `turn_rate`, `reform_*`) with a recorded sweep; never weaken a check; if tuning cannot keep it, stop and report.
- Battle AI does not use routes (out of scope). `order_move(b, p)` keeps its signature and becomes a one-point route; `order_point` stays the final destination so existing callers and tests keep working.
- Probed ground: flat plain around (120, 90) (arena field `Rect2(10, 10, 220, 160)`); river at y 330 is water for x 600–650, plain from 660 east and up to 590 west; the ford's bridge cells run east–west along y ≈ 380–399 for x ≈ 560–619 (feature centroid (590, 390), mid-river); `terrain.crosses_water(a, b)` and `terrain.nearest_bridge(p)` exist.
- Tests: `cd game && $G --headless --script tests/run_tests.gd -- routes` (new suite) / `-- battle_shell` / all. `$G` = `/k/Godot/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe`. New `class_name`/test scripts: run `$G --headless --path game --import` once and stage `.gd.uid` files. No API newer than Godot 4.5.
- Git: never commit or push; stage with `git add`; never stage `game/icon.svg.import`.

---

## File map

| File | Responsibility |
| --- | --- |
| `game/scripts/sim/block.gd` | + `route`, `end_facing`, `route_target_id`. |
| `game/scripts/sim/battle_sim.gd` | `order_route`, `order_move` as a one-point route, route walking and arrival in `_move`, `clean_route` (+ bridge ends), `order_group_route`, `formation_slots`, `order_formation`; other orders clear routes. |
| `game/scripts/sim/game_config.gd` | four new `combat` keys. |
| `game/scripts/ui/battle_view.gd` | route and line gestures, slow-mo, stroke preview and ghosts, remaining-route drawing, Move/Attack buttons removed, touch deselect. |
| `game/tests/test_routes.gd` (new) | sim rules for routes, cleaning, groups, formation. |
| `game/tests/test_battle_shell.gd` | gesture tests. |
| `README.md` | the controls table and a "Drawing orders" paragraph. |

---

### Task 0: Finish the battle-contact final-review fixes

**Files:**
- Modify: `game/scripts/sim/battle_sim.gd`, `game/tests/test_contact.gd`, `docs/superpowers/specs/2026-09-23-battle-contact-design.md`; `game/scripts/sim/game_config.gd` only if tuning.

**State you inherit:** an earlier agent was interrupted mid-way through this task. The working tree has **unstaged** changes in `battle_sim.gd` (+68/−13: a `_sidestep` in `_try_step`, `_turn_closes_on_friend`, a `reach` parameter) and `test_contact.gd` (+150 lines of new tests). With them the suite is `892 checks, 2 failed`: the combat checks "the crossing turns 6 attackers into 1 survivor" (2 enemy blocks left) and "The Ford is a near-miss … not a walkover" (you 0 vs enemy 2). Read `git diff -- game/scripts/sim/battle_sim.gd game/tests/test_contact.gd` first; keep what is right, fix or replace what is not, and say which.

**Required (each with a test; TDD where not already done):**
1. A routing block can be put into a reform and stands still up to 2 s. Guard the reform start in `order_attack` with `not b.routing`, and in `_tick_reforms` cancel a reform whose own block fails `_can_lock(b)`. Test: a routing block ordered to attack its flanker does not reform and keeps running.
2. A block deep inside an enemy can never move out (`_blocked_by_enemy` refuses any step that stays deep; rotations are not collision-checked, e.g. the reform's instant facing flip grows a 24×12 block 6 u into its old front foe). Give enemy blocking the friends' rule via `_closes_on`: an already-deep pair may move apart. Test: two enemy blocks deeply overlapping, one ordered to Withdraw, is out within ~3 s.
3. Friends meeting head-on on one axis deadlock forever. A perpendicular sidestep in `_try_step` (keep the inherited `_sidestep` if it is sound). Test: two friends ordered to swap positions head-on along x both arrive within 15 s.
4. Comments: `_move`'s stale "Only an explicit Move … breaks contact" → the lock rules; `_push`'s "no block is moved more than once" → say it covers the push only.
5. Tests for spec gaps: a cavalry charge on a front seats flush within 2 s of contact; a reform cancels when its target dies and when it routs; a *losing* block's Withdraw gets it out (the uphill fixture's downhill block); a reforming block keeps taking flank damage; a plain duel has exactly one lock between its two blocks.
6. Spec stragglers in `docs/superpowers/specs/2026-09-23-battle-contact-design.md`: §3 "pivot_angle (30°)" → 45°; §2 "(~1 s)" → 1.5 s; §1 the initiator is the block whose front points more squarely at the other (ties: lower id), not "the block that moved into contact"; drop "(593 lines) does not grow much"; §2 add: a loser gives ground only if every winner against it can follow, else the fight grinds in place; pushes stall on a bridge (a winner cannot follow into the loser's bridge cell); a released pair that keeps touching fights unlocked until it separates; §3 add: on completion, locks the reformer initiated are recast so its old foe strikes it.
7. **Make every suite green.** The two Ford failures appeared with the inherited sidestep. Diagnose first (print the Ford's block positions/queue at the bridge with and without the sidestep); prefer a sidestep that does not fire in the Ford's queue (e.g. only when the friend ahead is moving toward the block, i.e. a head-on meeting, not a queue behind a slower friend) over tuning. Tune only the contact values listed in the Global Constraints, with a sweep, if the rule change alone does not restore them. If nothing restores them, stop and report DONE_WITH_CONCERNS with the evidence.

- [ ] **Step 1:** read the inherited diff; run all suites to reproduce `892 checks, 2 failed`.
- [ ] **Step 2:** write the missing failing tests for items 1, 2, 3, 5; run `-- contact` and see them fail for the right reasons (tests already added by the previous agent that pass: keep, and say whether they would have failed without the fix).
- [ ] **Step 3:** implement items 1–4 and 7; update the spec (item 6).
- [ ] **Step 4:** run all suites → `0 failed`; combat 88; East Hill passes.
- [ ] **Step 5:** stage `game/scripts/sim/battle_sim.gd game/tests/test_contact.gd docs/superpowers/specs/2026-09-23-battle-contact-design.md` (+ `game_config.gd` if tuned). Suggested message: `Battle contact: routers never reform, deep overlaps can part, friends sidestep head-on`.

---

### Task 1: Routes in the sim

**Files:**
- Modify: `game/scripts/sim/block.gd`, `game/scripts/sim/battle_sim.gd`, `game/scripts/sim/game_config.gd`
- Create: `game/tests/test_routes.gd`

**Interfaces:**
- Produces on `Block`: `var route: PackedVector2Array`, `var end_facing := NAN`, `var route_target_id := -1`.
- Produces on `BattleSim`: `order_route(b: Block, points: PackedVector2Array, end_facing := NAN, target: Block = null) -> void`; `order_move(b, point)` = `order_route(b, [point])`; `clean_route(b: Block, points: PackedVector2Array) -> PackedVector2Array`; `order_attack`/`order_hold`/`order_withdraw` clear the route fields. At the end of a route: attack `route_target_id` if alive; else turn to `end_facing` if set then Hold; else order NONE (today's Move behaviour).

- [ ] **Step 1: Write the failing tests**

Create `game/tests/test_routes.gd`:

```gdscript
extends RefCounted

## Drawn orders (spec 2026-09-24-drawn-orders-design.md): routes walked point
## by point, strokes cleaned (impassable samples dropped, the river crossed
## over the bridge), group routes that keep their shape, formation lines.

const INF_ := GameConfig.Role.INFANTRY
const CAV := GameConfig.Role.CAVALRY
const ARC := GameConfig.Role.ARCHERS
const P := GameConfig.Side.PLAYER
const E := GameConfig.Side.ENEMY

var t: TestHarness
var terrain: Terrain

func run(harness: TestHarness) -> void:
	t = harness
	terrain = Terrain.new()
	_test_config()
	_test_route_is_walked_in_order()
	_test_route_ends_facing()
	_test_route_ending_on_enemy_attacks()
	_test_move_is_a_one_point_route()
	_test_other_orders_clear_the_route()
	_test_clean_drops_impassable_samples()
	_test_river_stroke_uses_the_bridge()

# ------------------------------------------------------------------ helpers

## A started battle on `field`, both sides player-controlled, with one idle
## sentinel per side in far corners so the arena never counts as won.
func _arena(field := Rect2(10, 10, 220, 160)) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(terrain, field)
	for side in [P, E]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[P] = Vector2.LEFT
	sim.home_dir[E] = Vector2.RIGHT
	sim.started = true
	sim.add_block(P, INF_, field.position + Vector2(8, 8), 0.0)
	sim.add_block(E, INF_, field.end - Vector2(8, 8), 0.0)
	return sim

func _run(sim: BattleSim, seconds: float) -> void:
	t.run_for(sim, seconds)

func _off(a: float, b: float) -> float:
	return absf(angle_difference(a, b))

## Seconds until `b` is within `reach` of `at`, or -1 if not within `limit`.
func _time_to(sim: BattleSim, b: Block, at: Vector2, reach: float, limit: float) -> float:
	var steps := int(limit / TestHarness.DT)
	for i in steps:
		if b.pos.distance_to(at) <= reach:
			return float(i) * TestHarness.DT
		sim.step(TestHarness.DT)
	return -1.0

# -------------------------------------------------------------------- tests

func _test_config() -> void:
	print("\nroutes config")
	for key in ["route_sample", "route_reach", "formation_rank_gap", "draw_time_scale"]:
		t.check("combat.%s is configured" % key, GameConfig.combat.has(key))

func _test_route_is_walked_in_order() -> void:
	print("\nroute: walked point by point")
	var sim := _arena()
	var b := sim.add_block(P, INF_, Vector2(40, 90), 0.0)
	var pts := PackedVector2Array([Vector2(100, 90), Vector2(100, 40), Vector2(160, 40)])
	sim.order_route(b, pts)
	var went_north_first := false
	var reached_corner := _time_to(sim, b, Vector2(100, 40), 3.0, 15.0)
	t.check("it reaches the second point", reached_corner >= 0.0)
	if b.pos.x < 110.0:
		went_north_first = true
	t.check("before heading for the third", went_north_first, str(b.pos))
	t.check("and then reaches the end", _time_to(sim, b, Vector2(160, 40), 1.5, 15.0) >= 0.0)
	_run(sim, 0.5)
	t.check("a plain route ends with no order", b.order == Block.OrderType.NONE, str(b.order))

func _test_route_ends_facing() -> void:
	print("\nroute: turns to its end facing, then holds")
	var sim := _arena()
	var b := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
	sim.order_route(b, PackedVector2Array([Vector2(140, 90)]), PI / 2.0)
	_run(sim, 10.0)
	t.check("it faces the end facing", _off(b.facing, PI / 2.0) < 0.05, str(b.facing))
	t.check("and holds", b.order == Block.OrderType.HOLD, str(b.order))

func _test_route_ending_on_enemy_attacks() -> void:
	print("\nroute: a stroke that ends on an enemy attacks it, round a flank")
	var sim := _arena()
	var p := sim.add_block(P, INF_, Vector2(40, 90), 0.0)
	var e := sim.add_block(E, INF_, Vector2(170, 90), PI)
	sim.order_hold(e)
	var pts := PackedVector2Array([Vector2(100, 40), Vector2(170, 40), Vector2(170, 90)])
	sim.order_route(p, pts, NAN, e)
	_run(sim, 14.0)
	t.check("it is now attacking that enemy", p.order == Block.OrderType.ATTACK and p.target_id == e.id,
		"order %d target %d" % [p.order, p.target_id])
	var lock := sim._lock_between(p, e)
	t.check("locked with it", lock != null)
	t.check("on its flank, not its front", lock != null and lock.face != "front",
		lock.face if lock != null else "-")

func _test_move_is_a_one_point_route() -> void:
	print("\nroute: order_move is a one-point route")
	var sim := _arena()
	var b := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
	sim.order_move(b, Vector2(140, 90))
	t.check("MOVE with a one-point route", b.order == Block.OrderType.MOVE and b.route.size() == 1)
	t.check("order_point is the destination", b.order_point == Vector2(140, 90))

func _test_other_orders_clear_the_route() -> void:
	print("\nroute: Hold, Attack and Withdraw replace it")
	var sim := _arena()
	var b := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
	var e := sim.add_block(E, INF_, Vector2(170, 130), PI)
	for order in ["hold", "attack", "withdraw"]:
		sim.order_route(b, PackedVector2Array([Vector2(100, 90), Vector2(140, 90)]), 1.0, e)
		match order:
			"hold": sim.order_hold(b)
			"attack": sim.order_attack(b, e)
			"withdraw": sim.order_withdraw(b)
		t.check("%s clears the route" % order,
			b.route.is_empty() and b.route_target_id == -1 and is_nan(b.end_facing))

func _test_clean_drops_impassable_samples() -> void:
	print("\nclean_route: resampled, impassable and off-field samples dropped")
	var sim := _arena(Rect2(480, 250, 240, 200))
	var b := sim.add_block(P, INF_, Vector2(520, 330), 0.0)
	var raw := PackedVector2Array([Vector2(520, 330), Vector2(700, 330)])
	var route := sim.clean_route(b, raw)
	var ok := true
	for p in route:
		if terrain.is_blocked(p, INF_) or not sim.field.has_point(p):
			ok = false
	t.check("every point is on open ground in the field", ok, str(route))
	var spacing := float(GameConfig.combat["route_sample"])
	var dense := true
	for i in range(1, route.size()):
		if route[i].distance_to(route[i - 1]) > spacing * 1.5 and not terrain.crosses_water(route[i - 1], route[i]):
			# only the bridge hop may be longer than a sample
			if route[i - 1].distance_to(Vector2(590, 390)) > 60.0:
				dense = false
	t.check("sampled every route_sample units on land", dense)
	t.check("ends at the stroke's end", route.size() > 0 and route[route.size() - 1].distance_to(Vector2(700, 330)) < 1.0)

func _test_river_stroke_uses_the_bridge() -> void:
	print("\nclean_route: a stroke across the river goes over the bridge")
	var sim := _arena(Rect2(480, 250, 240, 200))
	var b := sim.add_block(P, INF_, Vector2(520, 330), 0.0)
	var route := sim.clean_route(b, PackedVector2Array([Vector2(520, 330), Vector2(690, 330)]))
	var near_bridge := false
	var crosses := false
	for i in route.size():
		if route[i].distance_to(Vector2(590, 390)) < 25.0:
			near_bridge = true
		if i > 0 and terrain.crosses_water(route[i - 1], route[i]):
			var mid: Vector2 = route[i - 1].lerp(route[i], 0.5)
			if terrain.biome_at(mid) != Terrain.Biome.BRIDGE:
				crosses = true
	t.check("the route passes over the bridge", near_bridge, str(route))
	t.check("no leg of it crosses open water", not crosses, str(route))
	sim.order_route(b, route)
	t.check("the block walks it to the far bank", _time_to(sim, b, Vector2(690, 330), 6.0, 40.0) >= 0.0,
		str(b.pos))
```

- [ ] **Step 2: Run to verify it fails**

Run: `$G --headless --path game --import` then `cd game && $G --headless --script tests/run_tests.gd -- routes`
Expected: FAIL / parse error — `order_route`, `clean_route` and the config keys do not exist.

- [ ] **Step 3: Implement**

`game_config.gd`, append to `combat` before `"battle_seconds"`:

```gdscript
	# Drawn orders (spec 2026-09-24).
	"route_sample": 12.0,        # u between points of a cleaned stroke
	"route_reach": 2.0,          # u within which a route point counts as reached
	"formation_rank_gap": 32.0,  # u between ranks of a formation line
	"draw_time_scale": 0.25,     # battle speed while a stroke is being drawn
```

`block.gd`, beside `order_point`:

```gdscript
var route: PackedVector2Array = []    # drawn orders: points still to walk; the last is order_point
var end_facing := NAN                 # facing to take at the end of a route, NAN = none
var route_target_id := -1             # enemy to attack when the route ends, -1 = none
```

`battle_sim.gd` — orders section:

```gdscript
func order_move(b: Block, point: Vector2) -> void:
	order_route(b, PackedVector2Array([point]))

## Walk `points` in order. At the end: attack `target` if it is still alive
## (or as soon as the block touches it on the way), else turn to `end_facing`
## and hold, else simply stop. An empty route with a target is an attack.
func order_route(b: Block, points: PackedVector2Array, end_facing := NAN, target: Block = null) -> void:
	if points.is_empty():
		if target != null:
			order_attack(b, target)
		return
	b.order = Block.OrderType.MOVE
	b.route = points.duplicate()
	b.order_point = points[points.size() - 1]
	b.end_facing = end_facing
	b.route_target_id = target.id if target != null else -1
	b.target_id = -1
	b.braced = false
	b.hold_time = 0.0

func _clear_route(b: Block) -> void:
	b.route = PackedVector2Array()
	b.end_facing = NAN
	b.route_target_id = -1
```

Call `_clear_route(b)` at the top of `order_attack`, `order_hold` and `order_withdraw` (before their existing lines).

In `_move`, replace the `Block.OrderType.MOVE:` branch of the `match b.order:` with:

```gdscript
			Block.OrderType.MOVE:
				var aim := block_by_id(b.route_target_id)
				if aim != null and aim.alive() and _prev_contacts.get(b.id, []).has(aim):
					order_attack(b, aim)           # touched the target on the way
					b.charge_run = 0.0
					return
				var reach := float(GameConfig.combat["route_reach"])
				while b.route.size() > 1 and b.pos.distance_to(b.route[0]) <= reach:
					b.route.remove_at(0)
				dest = b.route[0] if not b.route.is_empty() else b.order_point
```

and replace the arrival block

```gdscript
	var to_dest := dest - b.pos
	if to_dest.length() < 1.0:
		b.order = Block.OrderType.NONE if b.order == Block.OrderType.MOVE else b.order
		return
```

with

```gdscript
	var to_dest := dest - b.pos
	if to_dest.length() < 1.0:
		if b.order == Block.OrderType.MOVE:
			_arrive(b, dt)
		return
```

and add after `_move`:

```gdscript
## The end of a route: attack its target, else turn to its end facing and
## hold, else stop.
func _arrive(b: Block, dt: float) -> void:
	var aim := block_by_id(b.route_target_id)
	if aim != null and aim.alive():
		order_attack(b, aim)
		return
	if not is_nan(b.end_facing):
		if b.turn_toward(b.end_facing, dt) > 0.001:
			return                              # still turning; stays on the spot
		order_hold(b)
		return
	b.route = PackedVector2Array()
	b.order = Block.OrderType.NONE
```

Add the cleaning section:

```gdscript
# -------------------------------------------------------------- drawn orders

## A stroke made walkable for `b`: resampled every `route_sample` units,
## samples on impassable ground or off the field dropped, and a leg that would
## cross water replaced by the bridge — entered at its near end, left at its
## far end — so the line keeps its shape and never asks a block to swim.
func clean_route(b: Block, points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	var spacing := maxf(1.0, float(GameConfig.combat["route_sample"]))
	var samples := PackedVector2Array([points[0]])
	var left := spacing
	for i in range(1, points.size()):
		var a := points[i - 1]
		var c := points[i]
		var seg := a.distance_to(c)
		var d := 0.0
		while seg - d >= left:
			d += left
			samples.append(a.lerp(c, d / seg))
			left = spacing
		left -= seg - d
	if samples[samples.size() - 1] != points[points.size() - 1]:
		samples.append(points[points.size() - 1])
	var last := b.pos
	for p in samples:
		if terrain.is_blocked(p, b.role) or not field.has_point(p):
			continue
		if terrain.crosses_water(last, p):
			for end in _bridge_ends(last, p):
				if out.is_empty() or out[out.size() - 1].distance_to(end) > 0.5:
					out.append(end)
					last = end
			if terrain.crosses_water(last, p):
				continue                      # no bridge serves this leg: drop the sample
		out.append(p)
		last = p
	return out

## The nearest bridge's two ends as [entry, exit] for a walk from `from`
## toward `to`: the bridge cells are walked out from its centre along the axis
## they run on, and each end is the first open ground past them. [] if there is
## no bridge.
func _bridge_ends(from: Vector2, to: Vector2) -> PackedVector2Array:
	var centre := terrain.nearest_bridge(from.lerp(to, 0.5))
	if centre == Vector2.INF:
		return PackedVector2Array()
	var best_axis := Vector2.RIGHT
	var best_len := -1.0
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		var span := _bridge_run(centre, axis) + _bridge_run(centre, -axis)
		if span > best_len:
			best_len = span
			best_axis = axis
	var a := centre + best_axis * (_bridge_run(centre, best_axis) + Terrain.CELL * 0.5)
	var z := centre - best_axis * (_bridge_run(centre, -best_axis) + Terrain.CELL * 0.5)
	if from.distance_to(a) <= from.distance_to(z):
		return PackedVector2Array([a, z])
	return PackedVector2Array([z, a])

## How far bridge cells continue from `centre` along `dir`, in world units.
func _bridge_run(centre: Vector2, dir: Vector2) -> float:
	var d := 0.0
	while d < 200.0 and terrain.biome_at(centre + dir * (d + 2.0)) == Terrain.Biome.BRIDGE:
		d += 2.0
	return d
```

- [ ] **Step 4: Run tests**

`-- routes` → all `ok`; then all suites (`test_battle_shell.gd`'s right-click Move check reads `order_point`, which `order_route` sets). If `_bridge_ends` lands an end on water or cliff at the Ford, print the ends and fix the end offset; the test requires no leg over open water.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/block.gd game/scripts/sim/battle_sim.gd game/scripts/sim/game_config.gd game/tests/test_routes.gd game/tests/test_routes.gd.uid
```
Suggested message: `Battle: routes — walk drawn strokes point by point, over the bridge`

---

### Task 2: Group routes and formation lines

**Files:**
- Modify: `game/scripts/sim/battle_sim.gd`, `game/tests/test_routes.gd`

**Interfaces:**
- Consumes: Task 1's `order_route`, `clean_route`.
- Produces: `order_group_route(group: Array[Block], lead: Block, points: PackedVector2Array, end_facing := NAN, target: Block = null) -> void`; `formation_slots(group: Array[Block], stroke: PackedVector2Array) -> Array[Dictionary]` (`{block: Block, pos: Vector2, facing: float}`); `order_formation(group: Array[Block], stroke: PackedVector2Array) -> void`.

- [ ] **Step 1: Write the failing tests**

Add to `run()`: `_test_group_keeps_its_shape()`, `_test_group_squeezes_over_the_bridge()`, `_test_formation_slots()`, `_test_formation_is_walked()`, `_test_locked_loser_ignores_a_route()`. Append:

```gdscript
func _test_group_keeps_its_shape() -> void:
	print("\ngroup route: a line stays a line on open ground")
	var sim := _arena()
	var top := sim.add_block(P, INF_, Vector2(50, 50), 0.0)
	var lead := sim.add_block(P, INF_, Vector2(50, 90), 0.0)
	var bottom := sim.add_block(P, INF_, Vector2(50, 130), 0.0)
	var group: Array[Block] = [top, lead, bottom]
	sim.order_group_route(group, lead, PackedVector2Array([Vector2(50, 90), Vector2(190, 90)]))
	_run(sim, 12.0)
	t.near("the lead arrived", lead.pos.distance_to(Vector2(190, 90)), 0.0, 2.0)
	t.near("the top block kept its offset", top.pos.distance_to(Vector2(190, 50)), 0.0, 3.0)
	t.near("the bottom block kept its offset", bottom.pos.distance_to(Vector2(190, 130)), 0.0, 3.0)

func _test_group_squeezes_over_the_bridge() -> void:
	print("\ngroup route: a line squeezes into a column over the bridge")
	var sim := _arena(Rect2(480, 250, 240, 250))
	var a := sim.add_block(P, INF_, Vector2(520, 360), 0.0)
	var lead := sim.add_block(P, INF_, Vector2(520, 390), 0.0)
	var c := sim.add_block(P, INF_, Vector2(520, 420), 0.0)
	var group: Array[Block] = [a, lead, c]
	sim.order_group_route(group, lead, PackedVector2Array([Vector2(520, 390), Vector2(690, 390)]))
	var overlapped := false
	for i in int(45.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		for x in group:
			for y in group:
				if x != y and x.overlaps_deeply(y):
					overlapped = true
	for b in group:
		t.check("block %d crossed to the east bank" % b.id, b.pos.x > 630.0, str(b.pos))
	t.check("they never overlapped on the way", not overlapped)

func _test_formation_slots() -> void:
	print("\nformation: infantry on the line, archers behind, cavalry on the wings")
	var sim := _arena()
	var i1 := sim.add_block(P, INF_, Vector2(60, 50), 0.0)
	var i2 := sim.add_block(P, INF_, Vector2(60, 130), 0.0)
	var ar := sim.add_block(P, ARC, Vector2(40, 90), 0.0)
	var c1 := sim.add_block(P, CAV, Vector2(30, 30), 0.0)
	var c2 := sim.add_block(P, CAV, Vector2(30, 150), 0.0)
	var group: Array[Block] = [i1, i2, ar, c1, c2]
	var stroke := PackedVector2Array([Vector2(150, 40), Vector2(150, 140)])   # a north–south line
	var slots := sim.formation_slots(group, stroke)
	var at := {}
	for s in slots:
		at[s["block"]] = s
	t.check("every block has a slot", at.size() == 5)
	if at.size() != 5:
		return
	for b in group:
		t.check("block %d faces the enemy side (east)" % b.id, _off(at[b]["facing"], 0.0) < 0.01)
	t.near("infantry stand on the line", at[i1]["pos"].x, 150.0, 0.5)
	t.near("both of them", at[i2]["pos"].x, 150.0, 0.5)
	t.check("in their current order (no crossing)", at[i1]["pos"].y < at[i2]["pos"].y)
	t.near("archers a rank behind", at[ar]["pos"].x, 150.0 - float(GameConfig.combat["formation_rank_gap"]), 0.5)
	t.check("cavalry past the north end", at[c1]["pos"].y < 40.0, str(at[c1]["pos"]))
	t.check("and past the south end", at[c2]["pos"].y > 140.0, str(at[c2]["pos"]))

func _test_formation_is_walked() -> void:
	print("\nformation: the blocks walk to their slots and face the enemy")
	var sim := _arena()
	var i1 := sim.add_block(P, INF_, Vector2(60, 60), 0.0)
	var i2 := sim.add_block(P, INF_, Vector2(60, 120), 0.0)
	var group: Array[Block] = [i1, i2]
	var stroke := PackedVector2Array([Vector2(150, 50), Vector2(150, 130)])
	var slots := sim.formation_slots(group, stroke)
	sim.order_formation(group, stroke)
	_run(sim, 15.0)
	for s in slots:
		var b: Block = s["block"]
		t.near("block %d reached its slot" % b.id, b.pos.distance_to(s["pos"]), 0.0, 2.0)
		t.check("block %d faces east" % b.id, _off(b.facing, 0.0) < 0.05, str(b.facing))
		t.check("block %d holds" % b.id, b.order == Block.OrderType.HOLD)

func _test_locked_loser_ignores_a_route() -> void:
	print("\nroute: a block losing a lock ignores a new route")
	var sim := _arena(Rect2(860, 400, 180, 180))
	var up := sim.add_block(P, INF_, Vector2(944, 490), 0.0)
	var down := sim.add_block(E, INF_, Vector2(956, 490), PI)
	sim.order_attack(up, down)
	sim.order_attack(down, up)
	_run(sim, 3.0)
	sim.order_route(down, PackedVector2Array([Vector2(1000, 450), Vector2(1020, 490)]))
	_run(sim, 1.0)
	t.check("still locked", not sim.locks_of(down).is_empty())
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `order_group_route`, `formation_slots`, `order_formation` missing.

- [ ] **Step 3: Implement** (append to the drawn-orders section of `battle_sim.gd`)

```gdscript
## Every block of `group` follows the lead's cleaned route, offset by where it
## stood relative to the lead, in the route's own frame so the shape turns
## with it. An offset point on blocked ground falls back to the lead's point
## there, and solid friends make those blocks queue: a line squeezes into a
## column through a gap and fans out after. Routing blocks are left alone.
func order_group_route(group: Array[Block], lead: Block, points: PackedVector2Array,
		end_facing := NAN, target: Block = null) -> void:
	var route := clean_route(lead, points)
	if route.is_empty():
		return
	var first := route[0] - lead.pos
	var heading0 := first.angle() if first.length() > 0.5 else lead.facing
	for b in group:
		if not b.alive() or b.routing:
			continue
		if b == lead:
			order_route(b, route, end_facing, target)
			continue
		var local := (b.pos - lead.pos).rotated(-heading0)
		var pts := PackedVector2Array()
		for i in route.size():
			var ahead := route[i] - (route[i - 1] if i > 0 else lead.pos)
			var h := ahead.angle() if ahead.length_squared() > 0.01 else heading0
			# `local` is the offset in the frame of the route's first heading;
			# re-applied at this point's heading, the shape turns with the route.
			var p := route[i] + local.rotated(h)
			if terrain.is_blocked(p, b.role) or not field.has_point(p):
				p = route[i]
			pts.append(p)
		order_route(b, pts, end_facing, target)

## Where each block of `group` stands on a formation line drawn as `stroke`:
## infantry spread evenly along it, archers a rank behind, cavalry on the
## wings past its ends; with no infantry the archers take the line. Blocks keep
## their current order along the line so no paths cross, a rank too long for
## the line spills into a further rank behind, and everyone faces
## perpendicular to the line, away from home.
func formation_slots(group: Array[Block], stroke: PackedVector2Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if group.is_empty() or stroke.size() < 2:
		return out
	var a := stroke[0]
	var z := stroke[stroke.size() - 1]
	if a.distance_to(z) < 1.0:
		return out
	var dir := (z - a).normalized()
	var normal := Vector2(-dir.y, dir.x)
	if normal.dot(home_dir[group[0].side]) > 0.0:
		normal = -normal
	var facing := normal.angle()
	var length := _polyline_length(stroke)
	var inf: Array[Block] = []
	var arc: Array[Block] = []
	var cav: Array[Block] = []
	for b in group:
		if not b.alive() or b.routing:
			continue
		match b.role:
			GameConfig.Role.CAVALRY: cav.append(b)
			GameConfig.Role.ARCHERS: arc.append(b)
			_: inf.append(b)
	var by_line := func(x: Block, y: Block) -> bool: return (x.pos - a).dot(dir) < (y.pos - a).dot(dir)
	inf.sort_custom(by_line)
	arc.sort_custom(by_line)
	cav.sort_custom(by_line)
	var gap := float(GameConfig.combat["formation_rank_gap"])
	var line: Array[Block] = inf if not inf.is_empty() else arc
	var ranks := _fill_ranks(out, line, stroke, length, facing, normal, 0.0, gap)
	if not inf.is_empty():
		_fill_ranks(out, arc, stroke, length, facing, normal, float(ranks) * gap, gap)
	var half := int(ceil(float(cav.size()) / 2.0))
	for i in cav.size():
		var b := cav[i]
		var w := b.frontage() + 6.0
		var slot: Vector2
		if i < half:
			slot = a - dir * w * float(half - i)
		else:
			slot = z + dir * w * float(i - half + 1)
		out.append({"block": b, "pos": slot, "facing": facing})
	return out

## Put `blocks` along `stroke`, `back` units behind it, as many per rank as fit
## at their frontage; the rest go further back. Returns the ranks used.
func _fill_ranks(out: Array[Dictionary], blocks: Array[Block], stroke: PackedVector2Array,
		length: float, facing: float, normal: Vector2, back: float, gap: float) -> int:
	if blocks.is_empty():
		return 0
	var w := blocks[0].frontage() + 6.0
	var per_rank := maxi(1, int(length / w) + 1)
	var ranks := 0
	var i := 0
	while i < blocks.size():
		var n := mini(per_rank, blocks.size() - i)
		for k in n:
			var d := length * (float(k) + 0.5) / float(n)
			var slot := _point_along(stroke, d) - normal * (back + float(ranks) * gap)
			out.append({"block": blocks[i + k], "pos": slot, "facing": facing})
		i += n
		ranks += 1
	return ranks

## Send `group` to its formation slots. A slot on blocked ground: the block
## turns to the line's facing where it stands.
func order_formation(group: Array[Block], stroke: PackedVector2Array) -> void:
	for s in formation_slots(group, stroke):
		var b: Block = s["block"]
		var slot: Vector2 = s["pos"]
		if terrain.is_blocked(slot, b.role) or not field.has_point(slot):
			slot = b.pos
		order_route(b, PackedVector2Array([slot]), s["facing"])

func _polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total

func _point_along(pts: PackedVector2Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if d <= seg or i == pts.size() - 1:
			return pts[i - 1].lerp(pts[i], clampf(d / maxf(seg, 0.0001), 0.0, 1.0))
		d -= seg
	return pts[pts.size() - 1]
```

- [ ] **Step 4: Run tests**

`-- routes` → all `ok`; all suites.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/battle_sim.gd game/tests/test_routes.gd
```
Suggested message: `Battle: group routes keep their shape; formation lines by role`

---

### Task 3: Drawing gestures, slow motion and previews

**Files:**
- Modify: `game/scripts/ui/battle_view.gd`, `game/tests/test_battle_shell.gd`

**Interfaces:**
- Consumes: `BattleSim.order_group_route`, `order_formation`, `formation_slots`, `clean_route`, `Block.route/route_target_id`.
- Produces on `BattleView`: `var _stroke: PackedVector2Array` (world points), `var _stroke_kind := ""` (`"" | "route" | "line"`), `var _stroke_lead: Block`; `func _time_scale() -> float` (`draw_time_scale` while a stroke is in progress, else 1.0).

- [ ] **Step 1: Write the failing tests**

In `test_battle_shell.gd`, add `_test_drawing(tree)` to `run()` after `_test_view_input(tree)` and append:

```gdscript
func _test_drawing(tree: SceneTree) -> void:
	print("\nBattleView: drawing routes and formation lines")
	var host := Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := BattleSim.new()
	sim.setup(terrain, Rect2(10, 10, 220, 160))
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	var mine := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(50, 90), 0.0)
	var mate := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(50, 130), 0.0)
	sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(220, 160), PI)
	var view := BattleView.new()
	host.add_child(view)
	view.open(terrain, sim, false)
	view._process(0.0)
	var cam := view.camera

	var no_buttons := true
	for b in view.find_children("*", "Button", true, false):
		if b.text == "Move" or b.text == "Attack":
			no_buttons = false
	t.check("the Move and Attack buttons are gone", no_buttons)

	# Drag from a block: a route.
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	for p in [Vector2(80, 70), Vector2(120, 50), Vector2(160, 60)]:
		_motion(view, cam.w2s(p))
	t.check("time slows while drawing", is_equal_approx(view._time_scale(),
		float(GameConfig.combat["draw_time_scale"])), str(view._time_scale()))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(160, 60)), false)
	t.check("and returns to normal on release", is_equal_approx(view._time_scale(), 1.0))
	t.check("a drag from a block gives it a route", mine.order == Block.OrderType.MOVE and mine.route.size() > 1,
		"order %d route %d" % [mine.order, mine.route.size()])
	t.check("ending near (160, 60)", mine.order_point.distance_to(Vector2(160, 60)) < 13.0, str(mine.order_point))
	t.check("the dragged block is the selection", view.selection.size() == 1 and view.selection[0] == mine)

	# Nothing selected: a ground drag box-selects.
	view.selection.clear()
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(20, 20)), true)
	_motion(view, cam.w2s(Vector2(100, 160)))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(100, 160)), false)
	t.check("with nothing selected a ground drag box-selects", view.selection.has(mine) and view.selection.has(mate),
		str(view.selection.size()))

	# With a selection: a ground drag draws their formation line.
	sim.order_hold(mine)
	sim.order_hold(mate)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(140, 40)), true)
	_motion(view, cam.w2s(Vector2(140, 90)))
	_motion(view, cam.w2s(Vector2(140, 140)))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(140, 140)), false)
	t.check("a ground drag with a selection forms them on the line",
		mine.order == Block.OrderType.MOVE and mate.order == Block.OrderType.MOVE
		and not is_nan(mine.end_facing) and not is_nan(mate.end_facing))

	# A short scribble is ignored.
	sim.order_hold(mine)
	view.selection = [mine] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	_motion(view, cam.w2s(mine.pos) + Vector2(12, 0))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos) + Vector2(12, 0), false)
	t.check("a stroke shorter than 20 px is ignored", mine.order == Block.OrderType.HOLD)

	# Touch: tapping a selected block again deselects it.
	view.touch = true
	view.selection = [mine] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), false)
	t.check("on touch, tapping the selected block deselects it", view.selection.is_empty())
	tree.root.remove_child(host)
	host.free()
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_shell`
Expected: FAIL — the buttons exist; `_time_scale` missing.

- [ ] **Step 3: Implement** (`battle_view.gd`)

1. **Remove the armed orders:** delete `pending_order` and every use (`_order_button`, `_apply_pending`, the `pending_order` branches in `_battle_tap`, `_update_hover`, `_selection_tooltip`, `_refresh_hud`, `open`), and the `move_btn` / `attack_btn` lines in `_build_hud` and `_refresh_hud`. `_update_hover`'s cursor becomes: pointing hand over your block; cross over an enemy when something is selected; else arrow. `_selection_tooltip`'s last line becomes `"Drag from a block to draw its route; drag across the ground to form a line; tap an enemy to attack."` on touch and `"Drag from a block to draw its route, drag on ground to form a line, click an enemy to attack, right-click to move."` with a mouse.

2. **State** (beside `dragging_block`):

```gdscript
var _stroke: PackedVector2Array = []   # world points of the stroke being drawn
var _stroke_kind := ""                 # "" | "route" | "line"
var _stroke_lead: Block = null         # the block a route is drawn from
```

3. **Time scale:** in `_process` replace `_accum += delta * speed` with `_accum += delta * speed * _time_scale()`, and add:

```gdscript
func _time_scale() -> float:
	if _stroke_kind != "" and _press_moved:
		return float(GameConfig.combat["draw_time_scale"])
	return 1.0
```

In `_refresh_status`, when `_time_scale() < 1.0` append `" · DRAWING — slowed"` to the status text.

4. **Pointer down** — after the existing defender-drag block, add:

```gdscript
	if not sim.started:
		return
	if _press_block != null:
		_stroke_kind = "route"
		_stroke_lead = _press_block
	elif not selection.is_empty():
		_stroke_kind = "line"
	_stroke = PackedVector2Array([hover_world])
```

5. **Pointer move** — replace the tail

```gdscript
	if sim != null:
		if _press_block == null:
			_box_to = screen
		return
```

with

```gdscript
	if sim == null:
		return
	if _stroke_kind != "":
		if _stroke.is_empty() or hover_world.distance_to(_stroke[_stroke.size() - 1]) >= 4.0 / camera.zoom:
			_stroke.append(hover_world)
		return
	_box_to = screen
```

6. **Pointer up** — replace the `elif sim != null:` branch with:

```gdscript
	elif sim != null:
		if _stroke_kind != "" and _press_moved:
			_finish_stroke(world, screen)
		elif _box_to != Vector2.INF:
			_box_select(Rect2(_press_screen, _box_to - _press_screen).abs())
		elif tapped:
			_battle_tap(world)
```

and reset `_stroke = PackedVector2Array()`, `_stroke_kind = ""`, `_stroke_lead = null` with the other resets at the end of `_pointer_up` and in `_cancel_pointer`.

7. **Finishing a stroke:**

```gdscript
## A released stroke becomes orders. Shorter than 20 px, or a route released
## back on its own block: nothing. A route ends on an enemy → attack it; on
## ground → face the way the stroke was heading. A line forms the selection.
func _finish_stroke(world: Vector2, screen: Vector2) -> void:
	if _press_screen.distance_to(screen) < 20.0 and _stroke_length_px() < 20.0:
		return
	_stroke.append(world)
	if _stroke_kind == "route":
		if _stroke_lead == null or not _stroke_lead.alive():
			return
		if _block_at(world, GameConfig.Side.PLAYER) == _stroke_lead:
			return
		if not selection.has(_stroke_lead):
			selection = [_stroke_lead] as Array[Block]
		var foe := _block_at(world, GameConfig.Side.ENEMY)
		var heading := NAN
		if foe == null:
			var tail := _stroke[maxi(0, _stroke.size() - 6)]
			if tail.distance_to(world) > 1.0:
				heading = (world - tail).angle()
		var group: Array[Block] = []
		for b in selection:
			if b.alive():
				group.append(b)
		sim.order_group_route(group, _stroke_lead, _stroke, heading, foe)
		_acknowledge(foe.pos if foe != null else world)
	elif _stroke_kind == "line":
		var group: Array[Block] = []
		for b in selection:
			if b.alive():
				group.append(b)
		sim.order_formation(group, _stroke)
		_acknowledge(world)

func _stroke_length_px() -> float:
	var total := 0.0
	for i in range(1, _stroke.size()):
		total += _w2s(_stroke[i - 1]).distance_to(_w2s(_stroke[i]))
	return total
```

8. **Touch deselect** in `_battle_tap`: in the `if friend != null:` branch, first `if touch and selection.size() == 1 and selection[0] == friend: selection.clear(); _refresh_hud(); return` (on separate lines).

9. **Drawing the stroke** — add `_draw_stroke()` to `_draw_battle()` after `_draw_orders()`:

```gdscript
## The stroke being drawn, as it will be walked; an enemy under the tip gets
## brackets (attack at the end); a formation stroke shows ghost slots.
func _draw_stroke() -> void:
	if _stroke_kind == "" or not _press_moved or _stroke.size() < 2:
		return
	var col := ThemeColors.ACCENT
	if _stroke_kind == "route" and _stroke_lead != null:
		var walk := sim.clean_route(_stroke_lead, _stroke)
		var pts := PackedVector2Array([_w2s(_stroke_lead.pos)])
		for p in walk:
			pts.append(_w2s(p))
		if pts.size() >= 2:
			draw_polyline(pts, col, 3.0)
		var foe := _block_at(_stroke[_stroke.size() - 1], GameConfig.Side.ENEMY)
		if foe != null:
			_draw_brackets(_screen_bounds(foe).grow(6.0), ThemeColors.ENEMY.lightened(0.25))
	elif _stroke_kind == "line":
		var raw := PackedVector2Array()
		for p in _stroke:
			raw.append(_w2s(p))
		draw_polyline(raw, col * Color(1, 1, 1, 0.8), 2.0)
		var group: Array[Block] = []
		for b in selection:
			if b.alive():
				group.append(b)
		for s in sim.formation_slots(group, _stroke):
			var b: Block = s["block"]
			var d := b.depth()
			var w := b.frontage()
			draw_set_transform(_w2s(s["pos"]), s["facing"], Vector2(camera.zoom, camera.zoom))
			draw_rect(Rect2(Vector2(-d * 0.5, -w * 0.5), Vector2(d, w)), col * Color(1, 1, 1, 0.5), false, 1.5)
			draw_line(Vector2(d * 0.5, -w * 0.5), Vector2(d * 0.5, w * 0.5), col, 2.0)
			draw_set_transform_matrix(Transform2D.IDENTITY)
```

10. **Remaining routes** — in `_draw_orders`, replace the `if b.order == Block.OrderType.MOVE:` body with:

```gdscript
		if b.order == Block.OrderType.MOVE:
			var col := ThemeColors.ACCENT * Color(1, 1, 1, 0.85)
			var prev := from
			var points: PackedVector2Array = b.route if not b.route.is_empty() else PackedVector2Array([b.order_point])
			for p in points:
				var at := _w2s(p)
				_draw_dashes(prev, at, col, 2.0, 0.0)
				prev = at
			var aim := sim.block_by_id(b.route_target_id)
			if aim != null and aim.alive() and sim.visible_to(aim, GameConfig.Side.PLAYER):
				var red := ThemeColors.ENEMY.lightened(0.25)
				_draw_arrow(prev, _w2s(aim.pos), red, 2.0, 9.0)
				_draw_brackets(_screen_bounds(aim).grow(4.0), red)
			else:
				draw_circle(prev, 6.0, ThemeColors.ACCENT * Color(1, 1, 1, 0.25))
				draw_arc(prev, 6.0, 0.0, TAU, 20, col, 1.5)
```

- [ ] **Step 4: Run tests and a windowed smoke**

`-- battle_shell` → all `ok`; all suites. Then a scratch windowed scene (deleted afterwards) that hosts a `BattleView`, feeds a route drag and a line drag through `_gui_input` over ~2 s with `--quit-after 240`, and checks the log has no `SCRIPT ERROR` (drawing runs only when windowed).

- [ ] **Step 5: Stage**

```bash
git add game/scripts/ui/battle_view.gd game/tests/test_battle_shell.gd
```
Suggested message: `Battle view: draw routes and formation lines; time slows while you draw`

---

### Task 4: Docs and build

**Files:**
- Modify: `README.md`

- [ ] **Step 1:** Run all suites; every check passes.
- [ ] **Step 2: README.** In "## Playing on a phone", replace the input table rows for the battle (`attack (battle)`, `move (battle)`, `arm an order`) with:

```markdown
| draw a route (battle) | drag from your block | drag from your block |
| attack at the end of a route | end the drag on an enemy | end the drag on an enemy |
| form a line (battle) | select, then drag across the ground | select, then drag across the ground |
| attack (battle) | click an enemy with something selected | tap an enemy with something selected |
| move (battle) | right click on ground | tap ground with something selected |
| deselect (battle) | click empty ground | tap the selected block again |
```

and after the table add:

```markdown
**Drawing orders.** In battle you draw rather than click. Drag from one of
your blocks to draw its route — the whole selection follows it, keeping its
shape, and squeezes into a column where the ground is too narrow; end the
stroke on an enemy and they attack it from wherever the route brought them.
Drag across the ground with blocks selected to set a line: infantry on it,
archers a rank behind, cavalry on the wings, everyone facing the enemy. The
battle runs at a quarter speed while you draw. A stroke over the river is
routed over the bridge.
```

In the "The combat prototype" section, change "four orders (Move / Attack / Hold / Withdraw)" to "Hold / Withdraw plus drawn routes and lines".

- [ ] **Step 3: Build** the Windows exe (`tools/build-windows.ps1 -Godot <the _console.exe>`) and smoke it with `--quit-after 300` (engine banner only).
- [ ] **Step 4: Stage** `README.md docs/superpowers/plans/2026-09-24-drawn-orders.md docs/superpowers/specs/2026-09-24-drawn-orders-design.md`. Suggested message: `Drawn orders: docs`.
