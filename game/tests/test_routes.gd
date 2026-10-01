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
	_test_same_bank_stroke_never_swims()
	_test_route_from_the_bridge_deck()
	_test_stroke_ending_on_the_bridge()
	_test_clean_route_is_cheap()
	_test_straight_strokes_never_reverse()
	_test_resetup_rebuilds_the_grid()
	_test_near_axis_leg_sees_the_water()
	_test_losing_block_ignores_a_route()
	_test_winning_block_walks_its_route_out()
	_test_group_keeps_its_shape()
	_test_group_squeezes_over_the_bridge()
	_test_group_follower_legs_are_walkable()
	_test_formation_slots()
	_test_formation_is_walked()
	_test_group_column_through_a_gap()
	_test_stranded_follower_holds()
	_test_formation_over_the_river()
	_test_formation_ranks_a_frontage_apart()
	_test_formation_spill_keeps_order()
	_test_formation_from_in_front()
	_test_formation_parallel_to_home_faces_the_enemy()
	_test_formation_sweeps()
	_test_formation_seed3_l12()
	_test_no_stacks_on_arrival()
	_test_off_centre_press_keeps_the_shape()
	_test_off_centre_press_never_turns_back()
	_test_reclean_is_throttled()

# ------------------------------------------------------------------ helpers

## A started battle on `field`, both sides player-controlled, with one idle
## sentinel per side in far corners so the arena never counts as won.
func _arena(field := Rect2(10, 10, 220, 160), ground: Terrain = null) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(ground if ground != null else terrain, field)
	for side in [P, E]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[P] = Vector2.LEFT
	sim.home_dir[E] = Vector2.RIGHT
	sim.started = true
	# Sturdy, so archers passing in range cannot break one and end the battle.
	for sentinel in [sim.add_block(P, INF_, field.position + Vector2(8, 8), 0.0),
			sim.add_block(E, INF_, field.end - Vector2(8, 8), 0.0)]:
		sentinel.max_health = 1e6
		sentinel.health = 1e6
		sentinel.max_morale = 1e6
		sentinel.morale = 1e6
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
	# The step at which the block first comes within 3 u of each point.
	var first := [-1, -1, -1]
	for i in int(20.0 / TestHarness.DT):
		for k in pts.size():
			if first[k] < 0 and b.pos.distance_to(pts[k]) <= 3.0:
				first[k] = i
		if first[2] >= 0:
			break
		sim.step(TestHarness.DT)
	t.check("it passes near every point, the (100, 40) corner included",
		first[0] >= 0 and first[1] >= 0 and first[2] >= 0, str(first))
	t.check("in route order", first[0] < first[1] and first[1] < first[2], str(first))
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

## Legs of `route` that cross open water (a leg over the bridge does not).
func _wet_legs(route: PackedVector2Array) -> int:
	var n := 0
	for i in range(1, route.size()):
		if terrain.crosses_water(route[i - 1], route[i]):
			if terrain.biome_at(route[i - 1].lerp(route[i], 0.5)) != Terrain.Biome.BRIDGE:
				n += 1
	return n

func _has_near(route: PackedVector2Array, at: Vector2, reach: float) -> bool:
	for p in route:
		if p.distance_to(at) <= reach:
			return true
	return false

func _test_same_bank_stroke_never_swims() -> void:
	print("\nclean_route: a stroke that clips the river bend stays on its bank")
	var strokes := [
		PackedVector2Array([Vector2(520, 300), Vector2(590, 300), Vector2(592, 330),
			Vector2(555, 345), Vector2(540, 420)]),
		PackedVector2Array([Vector2(520, 300), Vector2(600, 300), Vector2(550, 360)]),
	]
	for i in strokes.size():
		var sim := _arena(Rect2(480, 250, 240, 200))
		var b := sim.add_block(P, INF_, Vector2(520, 300), 0.0)
		var route := sim.clean_route(b, strokes[i])
		t.check("stroke %d: no leg crosses open water" % i, _wet_legs(route) == 0, str(route))
		var on_start := 0
		for p in route:
			if absf(p.y - 300.0) < 0.5:
				on_start += 1
		# The block stands on the stroke's first point, so its first cleaned
		# point is the first sample a spacing on (off-centre presses, final review).
		t.check("stroke %d: it keeps its y-300 start" % i,
			_has_near(route, Vector2(532, 300), 1.0) and on_start >= 4, "%d on y 300: %s" % [on_start, route])
		var end: Vector2 = strokes[i][strokes[i].size() - 1]
		t.check("stroke %d: and its end, round the bend" % i,
			route.size() > 0 and route[route.size() - 1].distance_to(end) < 0.01, str(route))
		var east := false
		for p in route:
			if p.x >= 620.0:
				east = true
		t.check("stroke %d: it never goes to the far bank" % i, not east, str(route))

## The uphill fixture of test_contact: `up` (P, higher) beats `down` (E).
func _uphill_fight() -> Array:
	var sim := _arena(Rect2(860, 400, 180, 180))
	var up := sim.add_block(P, INF_, Vector2(944, 490), 0.0)
	var down := sim.add_block(E, INF_, Vector2(956, 490), PI)
	for blk in [up, down]:
		blk.max_health = 1000.0
		blk.health = 1000.0
		blk.max_morale = 1000.0
		blk.morale = 1000.0
	sim.order_attack(up, down)
	sim.order_attack(down, up)
	_run(sim, 3.0)
	return [sim, up, down]

func _test_losing_block_ignores_a_route() -> void:
	print("\nroute: a locked, losing block cannot walk a route out")
	var f := _uphill_fight()
	var sim: BattleSim = f[0]
	var down: Block = f[2]
	t.check("fixture: the downhill block is losing", sim.push_state(down) == -1)
	sim.order_route(down, PackedVector2Array([Vector2(990, 490), Vector2(1020, 460)]))
	_run(sim, 1.0)
	t.check("it is still locked", not sim.locks_of(down).is_empty())
	t.check("it is nowhere near its route", down.pos.distance_to(Vector2(990, 490)) > 20.0, str(down.pos))

func _test_winning_block_walks_its_route_out() -> void:
	print("\nroute: a locked, winning block's route walks it out")
	var f := _uphill_fight()
	var sim: BattleSim = f[0]
	var up: Block = f[1]
	var down: Block = f[2]
	t.check("fixture: the uphill block is winning", sim.push_state(up) == 1)
	sim.order_hold(down)             # left on Attack, it would chase and re-lock
	sim.order_route(up,PackedVector2Array([Vector2(900, 490), Vector2(900, 440)]))
	_run(sim, 1.0)
	t.check("its lock is over", sim.locks_of(up).is_empty())
	t.check("and it walks the route to its end", _time_to(sim, up, Vector2(900, 440), 1.5, 12.0) >= 0.0,
		str(up.pos))

func _test_route_from_the_bridge_deck() -> void:
	print("\nclean_route: a block on the bridge deck routes off it")
	var sim := _arena(Rect2(480, 250, 240, 200))
	var b := sim.add_block(P, INF_, Vector2(590, 390), 0.0)
	var route := sim.clean_route(b, PackedVector2Array([Vector2(590, 390), Vector2(500, 300)]))
	t.check("no leg crosses open water", _wet_legs(route) == 0, str(route))
	t.check("it ends at the stroke's end", route.size() > 0 and route[route.size() - 1].distance_to(Vector2(500, 300)) < 1.0,
		str(route))
	sim.order_route(b, route)
	t.check("the block walks it there", _time_to(sim, b, Vector2(500, 300), 3.0, 30.0) >= 0.0, str(b.pos))

func _test_stroke_ending_on_the_bridge() -> void:
	print("\nclean_route: a stroke may end on the bridge deck")
	var sim := _arena(Rect2(480, 250, 240, 200))
	var b := sim.add_block(P, INF_, Vector2(530, 340), 0.0)
	var route := sim.clean_route(b, PackedVector2Array([Vector2(530, 340), Vector2(590, 390)]))
	t.check("no leg crosses open water", _wet_legs(route) == 0, str(route))
	t.check("it ends on the bridge", route.size() > 0 and route[route.size() - 1].distance_to(Vector2(590, 390)) < 1.0,
		str(route))
	var dup := false
	for i in range(1, route.size()):
		if route[i].distance_to(route[i - 1]) < 0.01:
			dup = true
	t.check("no point is repeated", not dup, str(route))

## clean_route runs every frame of a stroke preview: it must stay cheap.
func _test_clean_route_is_cheap() -> void:
	print("\nclean_route: a 300-u stroke over the river is cheap")
	var sim := _arena(Rect2(440, 120, 340, 280))
	var b := sim.add_block(P, INF_, Vector2(460, 200), 0.0)
	var stroke := PackedVector2Array([Vector2(460, 200), Vector2(760, 200)])
	var route := sim.clean_route(b, stroke)
	t.check("no leg crosses open water", _wet_legs(route) == 0, str(route))
	t.check("it reaches the far bank", route.size() > 0 and route[route.size() - 1].distance_to(Vector2(760, 200)) < 1.0,
		str(route))
	var start := Time.get_ticks_usec()
	for i in 20:
		sim.clean_route(b, stroke)
	var avg := float(Time.get_ticks_usec() - start) / 20.0 / 1000.0
	t.check("under 5 ms a call", avg < 5.0, "%.2f ms" % avg)

## Sharpest turn inside `route`, in degrees (0 for a straight line).
func _sharpest_turn(route: PackedVector2Array) -> float:
	var worst := 0.0
	for i in range(1, route.size() - 1):
		var u := route[i] - route[i - 1]
		var v := route[i + 1] - route[i]
		if u.length() > 0.0 and v.length() > 0.0:
			worst = maxf(worst, rad_to_deg(absf(u.angle_to(v))))
	return worst

## Group routes (Task 2) take each point's heading from the leg before it: a
## cleaned straight stroke must never double back on itself.
func _test_straight_strokes_never_reverse() -> void:
	print("\nclean_route: straight strokes round the Ford never double back")
	var field := Rect2(480, 250, 240, 200)
	var sim := _arena(field)
	var b := sim.add_block(P, INF_, Vector2(520, 300), 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	var half := float(GameConfig.combat["route_sample"]) * 0.5
	var strokes := 0
	var reversed: Array[String] = []
	var wet: Array[String] = []
	var stub: Array[String] = []
	while strokes < 60:
		var a := Vector2(rng.randf_range(field.position.x, field.end.x), rng.randf_range(field.position.y, field.end.y))
		var z := Vector2(rng.randf_range(field.position.x, field.end.x), rng.randf_range(field.position.y, field.end.y))
		if terrain.is_blocked(a, INF_):
			continue
		strokes += 1
		b.pos = a
		var route := sim.clean_route(b, PackedVector2Array([a, z]))
		var tag := "%s->%s" % [a.round(), z.round()]
		if _sharpest_turn(route) > 120.0:
			reversed.append("%s %.0f° %s" % [tag, _sharpest_turn(route), route])
		if _wet_legs(route) > 0:
			wet.append(tag)
		var n := route.size()
		if n > 1 and route[n - 1].distance_to(route[n - 2]) < half:
			stub.append("%s %s" % [tag, route])
	t.check("no route turns back sharper than 120° (of %d)" % strokes, reversed.is_empty(),
		"%d: %s" % [reversed.size(), reversed.slice(0, 3)])
	t.check("no leg crosses open water", wet.is_empty(), str(wet))
	t.check("no last leg shorter than route_sample / 2", stub.is_empty(),
		"%d: %s" % [stub.size(), stub.slice(0, 3)])

func _test_resetup_rebuilds_the_grid() -> void:
	print("\nclean_route: a new field gets a new grid")
	var sim := _arena(Rect2(480, 250, 240, 200))
	var b := sim.add_block(P, INF_, Vector2(520, 330), 0.0)
	sim.clean_route(b, PackedVector2Array([Vector2(520, 330), Vector2(690, 330)]))   # builds the grid
	sim.setup(terrain, Rect2(440, 120, 340, 280))
	b.pos = Vector2(460, 200)
	var route := sim.clean_route(b, PackedVector2Array([Vector2(460, 200), Vector2(760, 200)]))
	t.check("the y-200 stroke on the new field still reaches the far bank",
		route.size() > 0 and route[route.size() - 1].distance_to(Vector2(760, 200)) < 0.01, str(route))

func _test_near_axis_leg_sees_the_water() -> void:
	print("\nclean_route: a leg a hair off vertical still sees the cell it crosses into")
	var wet := Terrain.new()
	wet.biome[5 * Terrain.COLS + 1] = Terrain.Biome.WATER      # x 20-40, y 100-120
	var sim := BattleSim.new()
	sim.setup(wet, Rect2(Vector2.ZERO, Terrain.SIZE))
	var a := Vector2(20.0 - 2e-6, 50)        # column 0 ...
	var z := Vector2(20.0 + 2e-6, 150)       # ... to column 1, over the water at y 100-120
	t.check("fixture: the leg crosses x 20", a.x < 20.0 and z.x >= 20.0, "%s %s" % [a, z])
	t.check("fixture: it passes over the water", wet.is_blocked(a.lerp(z, 0.55), INF_))
	t.check("it is not walkable", not sim._walkable(INF_, a, z))

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

## Step `sim` until no block of `group` is still marching, at most `limit` s.
## Seconds taken, or -1 if some block was still walking.
func _march(sim: BattleSim, group: Array, limit: float) -> float:
	for i in int(limit / TestHarness.DT):
		var moving := false
		for b in group:
			if b.alive() and b.order == Block.OrderType.MOVE:
				moving = true
		if not moving:
			return float(i) * TestHarness.DT
		sim.step(TestHarness.DT)
	return -1.0

## Pairs of `group` still deep in each other.
func _stacked(group: Array) -> Array:
	var out := []
	for x in group:
		for y in group:
			if x.id < y.id and x.overlaps_deeply(y):
				out.append([x.id, y.id])
	return out

## A line of `n` infantry at x `x`, `spread` apart about y `y`; the middle one leads.
func _line(sim: BattleSim, n: int, x: float, y: float, spread: float) -> Array[Block]:
	var group: Array[Block] = []
	for k in n:
		group.append(sim.add_block(P, INF_, Vector2(x, y + spread * (float(k) - float(n - 1) * 0.5)), 0.0))
	return group

func _test_group_squeezes_over_the_bridge() -> void:
	print("\ngroup route: a line squeezes into a column over the bridge and fans out")
	# 3 at spread 30, and the reviewer's 5 at spread 45 and 60 (which jammed at
	# the lead's start before soft marching).
	for c in [[3, 30.0], [5, 45.0], [5, 60.0]]:
		var sim := _arena(Rect2(480, 250, 240, 250))
		var group := _line(sim, c[0], 520, 390, c[1])
		var lead := group[int(c[0] / 2)]
		sim.order_group_route(group, lead, PackedVector2Array([Vector2(520, 390), Vector2(690, 390)]))
		var took := _march(sim, group, 45.0)
		var where := []
		var across := true
		for b in group:
			where.append(b.pos.round())
			if b.pos.x < 660.0:
				across = false
		var tag := "%d at spread %d" % [c[0], c[1]]
		t.check("%s: all cross to the east bank within 45 s" % tag, took >= 0.0 and across, "%.1f s %s" % [took, where])
		t.check("%s: and stand apart there" % tag, _stacked(group).is_empty(), str(_stacked(group)))


## Legs of `b`'s route it could not walk: its first, from where it stands, and
## each after.
func _unwalkable_legs(sim: BattleSim, b: Block) -> Array[String]:
	var bad: Array[String] = []
	var last := b.pos
	for p in b.route:
		if not sim._walkable(b.role, last, p):
			bad.append("%s->%s" % [last, p])
		last = p
	return bad

func _test_group_follower_legs_are_walkable() -> void:
	print("\ngroup route: every follower leg over the bridge is walkable")
	# A line crossing east over the bridge: the outer blocks' offset points lie
	# on dry ground either side of the river, but legs between them clip it.
	for spread in [30.0, 45.0, 60.0]:
		var sim := _arena(Rect2(480, 250, 240, 250))
		var a := sim.add_block(P, INF_, Vector2(530, 390 - spread), 0.0)
		var lead := sim.add_block(P, INF_, Vector2(530, 390), 0.0)
		var c := sim.add_block(P, INF_, Vector2(530, 390 + spread), 0.0)
		var group: Array[Block] = [a, lead, c]
		sim.order_group_route(group, lead, PackedVector2Array([Vector2(530, 390), Vector2(690, 390)]))
		for b in group:
			var bad := _unwalkable_legs(sim, b)
			t.check("spread %d: block %d's route has no unwalkable leg" % [spread, b.id],
				not b.route.is_empty() and bad.is_empty(), "%s in %s" % [bad, b.route])

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

## Plain level ground over x 0-420, y 0-320, with a water wall at x 200-220
## open only at y 140-160: one block wide.
func _gap_terrain() -> Terrain:
	var g := Terrain.new()
	for y in 16:
		for x in 21:
			g.biome[y * Terrain.COLS + x] = Terrain.Biome.PLAIN
			g.height[y * Terrain.COLS + x] = 0.0
	for y in 16:
		if y != 7:
			g.biome[y * Terrain.COLS + 10] = Terrain.Biome.WATER
	return g

func _test_group_column_through_a_gap() -> void:
	print("\ngroup route: a line marches through a one-block gap and out the far side")
	var ground := _gap_terrain()
	# [blocks, the lead's x]: the first review's 3 and 5 from x 100, and the
	# re-review's 7 from x 50 and 120 (all spread 30).
	for c in [[3, 100.0], [5, 100.0], [7, 50.0], [7, 120.0]]:
		var sim := _arena(Rect2(10, 10, 390, 290), ground)
		var group := _line(sim, c[0], c[1], 150, 30.0)
		var lead := group[int(c[0] / 2)]
		sim.order_group_route(group, lead, PackedVector2Array([Vector2(c[1], 150), Vector2(360, 150)]))
		var tag := "%d from x %d" % [c[0], c[1]]
		var bad := 0
		for b in group:
			bad += _unwalkable_legs(sim, b).size()
		t.check("%s: no unwalkable leg" % tag, bad == 0)
		var took := _march(sim, group, 60.0)
		var where := []
		var through := true
		for b in group:
			where.append(b.pos.round())
			if b.pos.x < 230.0:
				through = false
		t.check("%s: all arrive through the gap within 60 s" % tag, took >= 0.0 and through,
			"%.1f s %s" % [took, where])
		t.check("%s: and stand apart there" % tag, _stacked(group).is_empty(), str(_stacked(group)))

## Plain ground over x 0-400, y 0-400, as in the reviewer's sweeps.
func _plain_terrain() -> Terrain:
	var g := Terrain.new()
	for y in 20:
		for x in 20:
			g.biome[y * Terrain.COLS + x] = Terrain.Biome.PLAIN
	return g

## Every block of `slots` within 2 u of its slot and within 0.1 rad of its facing;
## the ones that are not, described.
func _off_slot(slots: Array[Dictionary]) -> Array:
	var out := []
	for s in slots:
		var b: Block = s["block"]
		if b.pos.distance_to(s["pos"]) > 2.0 or _off(b.facing, s["facing"]) > 0.1:
			out.append("%d at %s for %s f%.2f/%.2f" % [b.id, b.pos.round(), s["pos"].round(), b.facing, s["facing"]])
	return out

func _test_formation_sweeps() -> void:
	print("\nformation: random layouts (the reviewer's sweeps) all reach their slots")
	var plain := _plain_terrain()
	for river in [false, true]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var want := 15 if river else 30
		var used := 0
		var tries := 0
		var stranded := []
		while used < want and tries < 200:
			tries += 1
			var field := Rect2(480, 250, 240, 250) if river else Rect2(10, 10, 380, 380)
			var sim := _arena(field, terrain if river else plain)
			var group: Array[Block] = []
			var n := rng.randi_range(3, 7)
			var picks := 0
			while group.size() < n and picks < 200:
				picks += 1
				var p := Vector2(rng.randf_range(495, 580), rng.randf_range(270, 480)) if river \
					else Vector2(rng.randf_range(40, 340), rng.randf_range(40, 340))
				if sim.terrain.is_blocked(p, INF_):
					continue
				var clash := false
				for o in group:
					if o.pos.distance_to(p) < 34.0:
						clash = true
				if clash:
					continue
				var role := INF_ if rng.randf() < 0.75 else ARC
				group.append(sim.add_block(P, role, p, rng.randf_range(-PI, PI)))
			var stroke: PackedVector2Array
			if river:
				var y0 := rng.randf_range(290, 380)
				stroke = PackedVector2Array([Vector2(690, y0), Vector2(690, y0 + rng.randf_range(50, 110))])
			else:
				var c := Vector2(rng.randf_range(120, 260), rng.randf_range(120, 260))
				var along := Vector2.RIGHT.rotated(rng.randf_range(-PI, PI)) * rng.randf_range(50, 130) * 0.5
				stroke = PackedVector2Array([c - along, c + along])
			var slots := sim.formation_slots(group, stroke)
			var fits := true
			for s in slots:
				if sim.terrain.is_blocked(s["pos"], s["block"].role) or not field.grow(-12).has_point(s["pos"]):
					fits = false
			if not fits:
				continue
			used += 1
			sim.order_formation(group, stroke)
			_march(sim, group, 60.0)
			var off := _off_slot(slots)
			if not off.is_empty():
				stranded.append("layout %d: %s" % [tries, off])
		var tag := "across the river" if river else "on plain ground"
		t.check("%s: %d layouts tried" % [tag, want], used == want, "%d" % used)
		t.check("%s: every block reached its slot and faces the line's way within 60 s" % tag,
			stranded.is_empty(), "%d stranded: %s" % [stranded.size(), stranded.slice(0, 3)])

func _test_formation_seed3_l12() -> void:
	print("\nformation: the re-review's seed-3 layout 12 reaches its slots")
	var sim := _arena(Rect2(10, 10, 380, 380), _plain_terrain())
	var group: Array[Block] = [
		sim.add_block(P, INF_, Vector2(224.2, 85.7), -1.84),
		sim.add_block(P, INF_, Vector2(260.6, 170.5), 2.78),
		sim.add_block(P, ARC, Vector2(212.5, 257.9), 1.79),
		sim.add_block(P, ARC, Vector2(54.2, 143.2), 0.05),
		sim.add_block(P, ARC, Vector2(311.5, 260.2), 1.78),
	]
	var stroke := PackedVector2Array([Vector2(232.6, 110.7), Vector2(138.1, 188.4)])
	var slots := sim.formation_slots(group, stroke)
	sim.order_formation(group, stroke)
	var took := _march(sim, group, 60.0)
	t.check("every block reached its slot and faces the line's way within 60 s",
		took >= 0.0 and _off_slot(slots).is_empty(), "%.1f s %s" % [took, _off_slot(slots)])


func _test_stranded_follower_holds() -> void:
	print("\ngroup route: a follower with no way anywhere holds")
	var ground := _gap_terrain()
	for y in range(11, 14):
		for x in range(4, 7):
			if x != 5 or y != 12:
				ground.biome[y * Terrain.COLS + x] = Terrain.Biome.WATER   # a moat round x 100-120, y 240-260
	var sim := _arena(Rect2(10, 10, 390, 290), ground)
	var lead := sim.add_block(P, INF_, Vector2(100, 150), 0.0)
	var stuck := sim.add_block(P, INF_, Vector2(110, 250), 0.0)
	sim.order_move(stuck, Vector2(300, 250))
	var group: Array[Block] = [lead, stuck]
	sim.order_group_route(group, lead, PackedVector2Array([Vector2(100, 150), Vector2(360, 150)]))
	t.check("the lead has its route", lead.order == Block.OrderType.MOVE and not lead.route.is_empty())
	t.check("the stranded block holds instead of its old move", stuck.order == Block.OrderType.HOLD,
		str(stuck.order))

func _test_formation_over_the_river() -> void:
	print("\nformation: a line drawn over the river is reached by the bridge")
	var sim := _arena(Rect2(480, 250, 240, 250))
	var i1 := sim.add_block(P, INF_, Vector2(520, 360), 0.0)
	var i2 := sim.add_block(P, INF_, Vector2(520, 420), 0.0)
	var group: Array[Block] = [i1, i2]
	var stroke := PackedVector2Array([Vector2(690, 340), Vector2(690, 440)])
	var slots := sim.formation_slots(group, stroke)
	sim.order_formation(group, stroke)
	for b in group:
		var bad := _unwalkable_legs(sim, b)
		t.check("block %d's route has no unwalkable leg" % b.id, bad.is_empty(), str(bad))
	_run(sim, 40.0)
	for s in slots:
		var b: Block = s["block"]
		t.near("block %d reached its slot" % b.id, b.pos.distance_to(s["pos"]), 0.0, 2.0)
		t.check("block %d holds" % b.id, b.order == Block.OrderType.HOLD)

func _test_formation_ranks_a_frontage_apart() -> void:
	print("\nformation: blocks on one rank stand at least a frontage apart")
	var sim := _arena()
	var group: Array[Block] = []
	for k in 4:
		group.append(sim.add_block(P, INF_, Vector2(60, 40.0 + 30.0 * float(k)), 0.0))
	var slots := sim.formation_slots(group, PackedVector2Array([Vector2(150, 60), Vector2(150, 120)]))
	var close := []
	for s in slots:
		for r in slots:
			if s != r and absf(s["pos"].x - r["pos"].x) < 1.0 \
					and s["pos"].distance_to(r["pos"]) < s["block"].frontage():
				close.append([s["pos"], r["pos"]])
	t.check("every block has a slot", slots.size() == 4)
	t.check("no two on a rank closer than a frontage", close.is_empty(), str(close))
	_formation_arrives("4 on a 60-u line", sim, group, PackedVector2Array([Vector2(150, 60), Vector2(150, 120)]))

func _test_formation_spill_keeps_order() -> void:
	print("\nformation: a rank that spills strands nobody and keeps each rank's order")
	var sim := _arena()
	var group: Array[Block] = []
	for k in 5:
		group.append(sim.add_block(P, INF_, Vector2(60, 30.0 + 30.0 * float(k)), 0.0))
	_formation_arrives("5 on an 80-u line", sim, group, PackedVector2Array([Vector2(150, 50), Vector2(150, 130)]))

func _test_formation_from_in_front() -> void:
	print("\nformation: blocks starting in front of the line fall back to it")
	var sim := _arena()
	var group: Array[Block] = []
	for k in 5:
		group.append(sim.add_block(P, INF_, Vector2(195, 20.0 + 30.0 * float(k)), 0.0))
	_formation_arrives("5 from in front", sim, group, PackedVector2Array([Vector2(150, 50), Vector2(150, 130)]), 25.0)

## Order `group` onto `stroke` and check, after `seconds`: every block within
## 2 u of its slot, facing the formation's facing; and on each rank, the
## blocks' order along the line is the one they started in, both in their
## slots and where they stand.
func _formation_arrives(label: String, sim: BattleSim, group: Array[Block], stroke: PackedVector2Array,
		seconds := 15.0) -> void:
	var slots := sim.formation_slots(group, stroke)
	t.check("%s: every block has a slot" % label, slots.size() == group.size())
	var dir := (stroke[stroke.size() - 1] - stroke[0]).normalized()
	var before := {}
	for b in group:
		before[b] = b.pos.dot(dir)
	var slot_crossed := []
	for s in slots:
		for r in slots:
			if s["rank"] == r["rank"] and before[s["block"]] < before[r["block"]] - 0.01 \
					and s["pos"].dot(dir) > r["pos"].dot(dir) + 0.01:
				slot_crossed.append([s["block"].id, r["block"].id])
	t.check("%s: on each rank the slots keep the blocks' order" % label, slot_crossed.is_empty(), str(slot_crossed))
	sim.order_formation(group, stroke)
	_run(sim, seconds)
	var stranded := []
	var walked_crossed := []
	for s in slots:
		var b: Block = s["block"]
		if b.pos.distance_to(s["pos"]) > 2.0 or _off(b.facing, s["facing"]) > 0.05:
			stranded.append("%d at %s (slot %s, facing %.2f)" % [b.id, b.pos.round(), s["pos"], b.facing])
		for r in slots:
			if s["rank"] == r["rank"] and before[b] < before[r["block"]] - 0.01 \
					and b.pos.dot(dir) > r["block"].pos.dot(dir) + 1.0:
				walked_crossed.append([b.id, r["block"].id])
	t.check("%s: every block reached its slot facing the line's way within %.0f s" % [label, seconds],
		stranded.is_empty(), str(stranded))
	t.check("%s: and on each rank they stand in the same order" % label, walked_crossed.is_empty(), str(walked_crossed))

func _test_formation_parallel_to_home_faces_the_enemy() -> void:
	print("\nformation: a line drawn toward home faces the enemy's blocks")
	var sim := _arena()                  # the enemy sentinel stands south-east, at (222, 162)
	var i1 := sim.add_block(P, INF_, Vector2(80, 60), 0.0)
	var i2 := sim.add_block(P, INF_, Vector2(140, 60), 0.0)
	var group: Array[Block] = [i1, i2]
	for stroke in [PackedVector2Array([Vector2(60, 90), Vector2(180, 90)]),
			PackedVector2Array([Vector2(180, 90), Vector2(60, 90)])]:
		var slots := sim.formation_slots(group, stroke)
		t.check("drawn %s: faces south, toward the enemy" % ("east" if stroke[0].x < stroke[1].x else "west"),
			slots.size() == 2 and _off(slots[0]["facing"], PI / 2.0) < 0.01, str(slots[0]["facing"] if slots.size() > 0 else "-"))

## Pairs of `side`'s live blocks deep in each other.
func _friend_stacks(sim: BattleSim, side: int) -> Array:
	var group := sim.side_blocks(side)
	return _stacked(group)

func _test_no_stacks_on_arrival() -> void:
	print("\narrival: no two friends end stacked in each other")
	var field := Rect2(10, 10, 380, 380)
	# Two routes ending 6 u apart.
	var sim := _arena(field, _plain_terrain())
	var a := sim.add_block(P, INF_, Vector2(80, 150), 0.0)
	var b := sim.add_block(P, INF_, Vector2(80, 250), 0.0)
	sim.order_route(a, PackedVector2Array([Vector2(200, 200)]), 0.0)
	sim.order_route(b, PackedVector2Array([Vector2(206, 200)]), 0.0)
	_run(sim, 25.0)
	t.check("two routes ending 6 u apart: settled apart", _friend_stacks(sim, P).is_empty() \
		and a.order == Block.OrderType.HOLD and b.order == Block.OrderType.HOLD, "%s %s" % [a.pos, b.pos])
	# A move onto a holding friend.
	sim = _arena(field, _plain_terrain())
	a = sim.add_block(P, INF_, Vector2(200, 200), 0.0)
	sim.order_hold(a)
	b = sim.add_block(P, INF_, Vector2(80, 200), 0.0)
	sim.order_move(b, Vector2(200, 200))
	_run(sim, 20.0)
	t.check("a move onto a holding friend: settled beside it", _friend_stacks(sim, P).is_empty() \
		and b.order != Block.OrderType.MOVE and a.pos == Vector2(200, 200), "%s %s" % [a.pos, b.pos])
	# A formation slot on a standing friend outside the group.
	sim = _arena(field, _plain_terrain())
	var stand := sim.add_block(P, INF_, Vector2(150, 150), 0.0)
	sim.order_hold(stand)
	var group: Array[Block] = [sim.add_block(P, INF_, Vector2(60, 120), 0.0), sim.add_block(P, INF_, Vector2(60, 180), 0.0)]
	var clear_of := true
	for s in sim.formation_slots(group, PackedVector2Array([Vector2(150, 120), Vector2(150, 200)])):
		if s["pos"].distance_to(stand.pos) < s["block"].frontage():
			clear_of = false
	t.check("no formation slot is put on the standing friend", clear_of)
	sim.order_formation(group, PackedVector2Array([Vector2(150, 120), Vector2(150, 200)]))
	_run(sim, 30.0)
	t.check("a formation over a standing friend: nobody stacked on it", _friend_stacks(sim, P).is_empty(),
		"%s %s %s" % [stand.pos, group[0].pos, group[1].pos])
	# A group route whose column end would land on another follower's own end.
	var wet := _plain_terrain()
	wet.biome[6 * Terrain.COLS + 15] = Terrain.Biome.WATER      # x 300-320, y 120-140
	sim = _arena(field, wet)
	var lead := sim.add_block(P, INF_, Vector2(100, 150), 0.0)
	var behind := sim.add_block(P, INF_, Vector2(70, 150), 0.0)
	var beside := sim.add_block(P, INF_, Vector2(100, 120), 0.0)
	var line: Array[Block] = [lead, behind, beside]
	sim.order_group_route(line, lead, PackedVector2Array([Vector2(100, 150), Vector2(310, 150)]), 0.0)
	var last: Array[Vector2] = []
	for x in line:
		last.append(x.route[x.route.size() - 1])
	t.check("a group's ends are all a frontage apart", last[0].distance_to(last[1]) >= 24.0 \
		and last[0].distance_to(last[2]) >= 24.0 and last[1].distance_to(last[2]) >= 24.0, str(last))
	_run(sim, 40.0)
	t.check("and the group settles unstacked", _friend_stacks(sim, P).is_empty(),
		"%s %s %s" % [lead.pos, behind.pos, beside.pos])

## A drag rarely starts on a block's exact centre (the hit pad is a finger
## wide): the stroke's first samples inside the lead or right next to it are
## dropped and the shape's heading is the stroke's own, so a press a few units
## behind or beside the centre neither mirrors nor rotates the group.
func _test_off_centre_press_keeps_the_shape() -> void:
	print("\ngroup route: an off-centre press keeps the shape")
	for press in [Vector2(56, 90), Vector2(60, 96), Vector2(56, 96), Vector2(64, 84)]:
		var sim := _arena()
		var lead := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
		var f := sim.add_block(P, INF_, Vector2(60, 125), 0.0)
		var group: Array[Block] = [lead, f]
		sim.order_group_route(group, lead, PackedVector2Array([press, Vector2(150, press.y)]), 0.0)
		var lead_end := lead.route[lead.route.size() - 1]
		var f_end := f.route[f.route.size() - 1]
		t.near("press %s: the follower's route ends on its offset" % press,
			f_end.distance_to(lead_end + Vector2(0, 35)), 0.0, 3.0)
		_march(sim, group, 20.0)
		t.near("press %s: the follower stands on its offset" % press,
			f.pos.distance_to(lead.pos + Vector2(0, 35)), 0.0, 3.0)

func _test_off_centre_press_never_turns_back() -> void:
	print("\nroute: a press behind the centre does not turn the block round")
	var sim := _arena()
	var b := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
	var group: Array[Block] = [b]
	sim.order_group_route(group, b, PackedVector2Array([Vector2(55, 90), Vector2(85, 90), Vector2(150, 90)]))
	var worst := 0.0
	var arrived := -1.0
	for i in int(8.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		worst = maxf(worst, _off(b.facing, 0.0))
		if arrived < 0.0 and b.pos.x >= 140.0:
			arrived = sim.time
	t.check("it never turns more than 30 degrees off the stroke", worst <= deg_to_rad(30.0), "%.1f deg" % rad_to_deg(worst))
	# 4.5 s at the old 20 u/s; scaled for the 2026-09-30 speed change (infantry 14 u/s).
	var by := 4.5 * 20.0 / 14.0
	t.check("and arrives as fast as a centred press (x 140 by %.1f s)" % by, arrived > 0.0 and arrived <= by, str(arrived))

## A marching block with blocked ground ahead that cannot walk straight to its
## next point cleans the rest of its route again, but at most every half
## second (cleaning can run an A* per point), and its destination follows the
## new route's end.
func _test_reclean_is_throttled() -> void:
	print("\nroute: re-cleaning a route is throttled and keeps the destination")
	var sim := _arena(Rect2(480, 250, 240, 200))
	var b := sim.add_block(P, INF_, Vector2(620, 300), 0.0)
	sim.order_route(b, PackedVector2Array([Vector2(620, 420)]))      # straight over open water
	var times: Array[float] = []
	var last := -1.0
	for i in int(10.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		var at: float = sim._recleaned_at.get(b.id, -1.0)
		if at != last:
			times.append(at)
			last = at
	var gap := INF
	for k in range(1, times.size()):
		gap = minf(gap, times[k] - times[k - 1])
	t.check("fixture: it re-cleaned more than once", times.size() > 1, str(times.size()))
	t.check("never twice within half a second", gap >= 0.5 - 0.001, "%d re-cleans, min gap %.3f s" % [times.size(), gap])
	# A hand-made route ending in the water: the re-clean drops that end, and
	# the destination becomes the new route's last point.
	sim = _arena(Rect2(480, 250, 240, 200))
	b = sim.add_block(P, INF_, Vector2(560, 300), 0.0)
	sim.order_route(b, PackedVector2Array([Vector2(620, 380), Vector2(625, 320)]))
	var checked := false
	for i in int(10.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		if sim._recleaned_at.has(b.id):
			checked = true
			t.check("after a re-clean order_point is the route's end", b.route.is_empty() \
				or b.order_point == b.route[b.route.size() - 1], "%s vs %s" % [b.order_point, b.route])
			break
	t.check("fixture: that route was re-cleaned", checked)
