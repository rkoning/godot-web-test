class_name BattleSim
extends RefCounted

## The real-time block battle. Deliberately free of any rendering or input, so
## the same code runs in the browser and headless in the acceptance tests.

const BIG := 10000.0
## A seated pair overlaps by this hair rather than meeting exactly edge to
## edge, so rounding in a push or a turn never reads as the pair parting.
## Keep it larger than the ground one push step can open up in a pair that does
## not move together (push speed × dt) or locks flicker. At push_max 6 u/s and
## 60 Hz a full-speed step is 0.1 u, more than this: that is safe only because a
## loser moves with its winners or holds (see _push). Revisit if that changes.
const SEAT_OVERLAP := 0.05
## Two route points closer than this (u) are the same point.
const ROUTE_EPSILON := 0.01
## A marching block re-cleans its route at most this often (s): sliding round
## a bank corner could otherwise ask for it every tick, an A* each time.
const RECLEAN_EVERY := 0.5

var terrain: Terrain
var field := Rect2()                       # the crop of the strategic map we fight on
var blocks: Array[Block] = []
var time := 0.0
var finished := false
var started := false                       # false while the defender pre-arranges
var result := {}
var events: PackedStringArray = []

## Which way each side runs when it breaks, and which AI drives it.
var home_dir := {}
var behavior := {}                         # side -> "" (player), "attacker", "defender"
var ai_state := {}                         # scratch space for BattleAI
var player_is_defender := false            # the side that did not move gets to pre-arrange
var supply := {}

var _next_id := 1
var _prev_contacts := {}
var locks: Array[Contact] = []             # every lock between touching enemy blocks
var _released := {}                        # pair key -> true: a pair left unlocked until it parts
var _damage_taken := {}                    # id -> damage this step, for morale recovery
var _route_grids := {}                     # role -> AStarGrid2D of the field, for clean_route
var _recleaned_at := {}                   # id -> sim time its route was last re-cleaned

func setup(p_terrain: Terrain, p_field: Rect2) -> void:
	terrain = p_terrain
	field = p_field
	_route_grids.clear()                   # built for the old field

func add_block(side: int, role: int, pos: Vector2, facing: float) -> Block:
	var b := Block.new(_next_id, side, role, pos, facing, supply.get(side, 1.0))
	_next_id += 1
	blocks.append(b)
	return b

func side_blocks(side: int, only_fighting := false) -> Array[Block]:
	var out: Array[Block] = []
	for b in blocks:
		if b.side != side or not b.alive():
			continue
		if only_fighting and b.routing:
			continue
		out.append(b)
	return out

## Forest hides blocks from the other side until they are close.
func visible_to(b: Block, side: int) -> bool:
	if b.side == side or not b.alive():
		return true
	if terrain.biome_at(b.pos) != Terrain.Biome.FOREST:
		return true
	var reach: float = GameConfig.terrain_mods["forest_hidden_range"]
	for watcher in side_blocks(side):
		if watcher.pos.distance_to(b.pos) <= reach:
			return true
	return false

func block_by_id(id: int) -> Block:
	for b in blocks:
		if b.id == id:
			return b
	return null

## Hostile blocks `b` was touching at the end of the last step.
func contacts_of(b: Block) -> Array:
	return _prev_contacts.get(b.id, [])

func is_engaged(b: Block) -> bool:
	return not contacts_of(b).is_empty()

## The arc an attacker at `from` hits `defender` in, bridge rule included.
func arc_of(defender: Block, from: Vector2) -> String:
	return _arc(defender, from)

# --------------------------------------------------------------------- orders

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

func order_attack(b: Block, target: Block) -> void:
	_clear_route(b)
	b.order = Block.OrderType.ATTACK
	b.target_id = target.id
	b.braced = false
	b.hold_time = 0.0
	# Turning on a flanker while engaged is a reform, not a pivot — and asking
	# again (the AI re-issues every 0.4 s) does not start it over. A rout does
	# not reform: it runs.
	if not b.reforming() and not b.routing and contacts_of(b).has(target) \
			and _arc(b, target.pos) != "front":
		b.reform_left = float(b.stats()["reform_time"])
		b.reform_from = b.facing
		b.reform_target_id = target.id
		_log("%s %s reforms to face a flank attack" % [_side_name(b.side), b.stats()["name"].to_lower()])

## Shoot `target` from range: stand and shoot it while it is in reach and in
## sight, otherwise walk toward it until it is. It is shot in preference to
## anything nearer; while it cannot be shot (in melee with one of ours), the
## block shoots whatever else it can. A block with no bow attacks instead.
func order_shoot(b: Block, target: Block) -> void:
	if b.stats()["ranged_dps"] <= 0.0:
		order_attack(b, target)
		return
	_clear_route(b)
	b.order = Block.OrderType.SHOOT
	b.target_id = target.id
	b.braced = false
	b.hold_time = 0.0

func order_hold(b: Block) -> void:
	_clear_route(b)
	b.order = Block.OrderType.HOLD
	b.target_id = -1
	b.hold_time = 0.0

func order_withdraw(b: Block) -> void:
	_clear_route(b)
	b.order = Block.OrderType.WITHDRAW
	b.target_id = -1
	b.braced = false
	b.withdrew = true
	_cancel_reform(b)

func retreat_all(side: int) -> void:
	for b in side_blocks(side):
		order_withdraw(b)

# -------------------------------------------------------------- drawn orders

## A stroke made walkable for `b`: resampled every `route_sample` units, and
## samples on ground `b` cannot stand on or off the field dropped. Where the
## straight leg from the route so far to the next sample is not walkable (it
## would swim, climb a cliff or cross a swamp it cannot), the shortest way
## round on the terrain grid is put in — over a bridge, round a bend of the
## bank — or, when the field offers none, the sample is dropped. So the line
## keeps its shape and never asks a block to swim.
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
	# The stroke's end is always a point; a last sample within half a spacing of
	# it merges into it rather than leaving a stub of a leg.
	var end := points[points.size() - 1]
	if samples.size() > 1 and samples[samples.size() - 1].distance_to(end) < spacing * 0.5:
		samples[samples.size() - 1] = end
	elif samples[samples.size() - 1].distance_to(end) > ROUTE_EPSILON:
		samples.append(end)
	else:
		samples[samples.size() - 1] = end
	# A drag starts wherever the finger or pointer came down on the block, rarely
	# its centre: samples still inside the block or within a spacing of its
	# centre are where it already stands, so they are dropped (never the end) —
	# otherwise a press behind the centre would turn the block round first.
	var lead_in := 0
	while lead_in < samples.size() - 1 and (b.distance_to_point(samples[lead_in]) <= 0.0
			or samples[lead_in].distance_to(b.pos) < spacing):
		lead_in += 1
	if lead_in > 0:
		samples = samples.slice(lead_in)
	var detour: Array[bool] = []          # per point of `out`: put in by a detour
	var last := b.pos
	for p in samples:
		if terrain.is_blocked(p, b.role) or not field.has_point(p):
			continue
		if not _walkable(b.role, last, p):
			var way := _grid_way(b.role, last, p)
			if way.is_empty():
				continue                          # no way there on the field: drop it
			for k in way.size():
				_fill(out, detour, last, way[k], spacing)
				_append(out, detour, way[k], k < way.size() - 1)   # the last is `p`
				last = way[k]
			continue
		_append(out, detour, p, false)
		last = p
	_unkink(b, out, detour)
	_trim_end(b, out, spacing)
	return out

## Append `q` unless it repeats the route's last point.
func _append(out: PackedVector2Array, detour: Array[bool], q: Vector2, is_detour: bool) -> void:
	if out.is_empty() or out[out.size() - 1].distance_to(q) > ROUTE_EPSILON:
		out.append(q)
		detour.append(is_detour)

## Append detour points every `spacing` strictly between `from` and `to`, a
## leg already known to be walkable.
func _fill(out: PackedVector2Array, detour: Array[bool], from: Vector2, to: Vector2, spacing: float) -> void:
	var n := int(from.distance_to(to) / spacing)
	for k in range(1, n + 1):
		_append(out, detour, from.lerp(to, float(k) / float(n + 1)), true)

## Take out the doubling back a detour leaves where the stroke ran on into the
## water before it (the route walks back to go round), where the grid's cell
## centres overshoot a turn, or where the detour arrives beyond a sample the
## stroke then comes back from. Group routes steer by each leg's heading, so a
## reversed leg would swing a whole formation round. Only points at or next
## to a detour move: the stroke's own shape is kept.
func _unkink(b: Block, out: PackedVector2Array, detour: Array[bool]) -> void:
	_drop_reversals(b, out, detour)
	for i in out.size() - 1:
		if detour[i]:
			_straighten(b, out, i)
	_dedupe(out, detour)
	_drop_reversals(b, out, detour)

## Drop the tip of every turn sharper than 120° at or next to a detour point
## whose neighbours can see each other straight. At such a turn the new leg is
## never longer than the longer of the two it replaces, so the route stays as
## dense as it was.
func _drop_reversals(b: Block, out: PackedVector2Array, detour: Array[bool]) -> void:
	var i := 0
	while i < out.size() - 1:
		var a: Vector2 = out[i - 1] if i > 0 else b.pos
		var near := detour[i] or detour[i + 1] or (i > 0 and detour[i - 1])
		if near and _reverses(a, out[i], out[i + 1]) and _walkable(b.role, a, out[i + 1]):
			out.remove_at(i)
			detour.remove_at(i)
			i = maxi(0, i - 1)
		else:
			i += 1

## Does the walk a -> m -> c turn back by more than 120°?
func _reverses(a: Vector2, m: Vector2, c: Vector2) -> bool:
	var u := m - a
	var v := c - m
	var lengths := u.length() * v.length()
	return lengths > 0.0 and u.dot(v) < -0.5 * lengths

## Slide point `i` toward the straight line between its neighbours, as far as
## both of its legs stay walkable (8 halvings).
func _straighten(b: Block, out: PackedVector2Array, i: int) -> void:
	var a: Vector2 = out[i - 1] if i > 0 else b.pos
	var c := out[i + 1]
	var target := Geometry2D.get_closest_point_to_segment(out[i], a, c)
	var lo := 0.0
	var hi := 1.0
	for k in 8:
		var f := hi if k == 0 else (lo + hi) * 0.5
		var q := out[i].lerp(target, f)
		if _walkable(b.role, a, q) and _walkable(b.role, q, c):
			lo = f
			if k == 0:
				break
		elif k > 0:
			hi = f
	out[i] = out[i].lerp(target, lo)

## Drop a point that has come to sit on the one before it (the end is kept).
func _dedupe(out: PackedVector2Array, detour: Array[bool]) -> void:
	var i := 1
	while i < out.size():
		if out[i].distance_to(out[i - 1]) <= ROUTE_EPSILON:
			var gone := i if i < out.size() - 1 else i - 1
			out.remove_at(gone)
			detour.remove_at(gone)
		else:
			i += 1

## No stub of a last leg: while the last leg is under half a spacing, drop the
## point before the end if the one before that (or the block) sees the end.
func _trim_end(b: Block, out: PackedVector2Array, spacing: float) -> void:
	while out.size() >= 2 and out[out.size() - 1].distance_to(out[out.size() - 2]) < spacing * 0.5:
		var a: Vector2 = out[out.size() - 3] if out.size() >= 3 else b.pos
		if not _walkable(b.role, a, out[out.size() - 1]):
			break
		out.remove_at(out.size() - 2)

## Can a block of `role` walk straight from `from` to `to`? Both ends on the
## field (a rectangle, so the whole leg is), and every terrain cell the leg
## touches open to it — found by walking the cells the segment passes through,
## both neighbours counted where it passes exactly through a cell corner. Exact,
## so any point sampled on a walkable leg, at any spacing, is on open ground.
func _walkable(role: int, from: Vector2, to: Vector2) -> bool:
	if not field.has_point(from) or not field.has_point(to):
		return false
	var cell := terrain.cell_of(from)
	var goal := terrain.cell_of(to)
	if _cell_blocked(cell, role):
		return false
	var d := to - from
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var size := Terrain.CELL
	# Exact zero only: a leg a hair off an axis still crosses the boundary it
	# crosses (a huge t step is fine; an approximate zero would miss it).
	var tdx := INF if d.x == 0.0 else size / absf(d.x)
	var tdy := INF if d.y == 0.0 else size / absf(d.y)
	var tx := INF if tdx == INF else absf((cell.x + (1 if sx > 0 else 0)) * size - from.x) / absf(d.x)
	var ty := INF if tdy == INF else absf((cell.y + (1 if sy > 0 else 0)) * size - from.y) / absf(d.y)
	# Step through every cell boundary the leg crosses before its end (t < 1);
	# a boundary met exactly at the end belongs to the goal cell, checked last.
	var guard := absi(goal.x - cell.x) + absi(goal.y - cell.y) + 4
	while minf(tx, ty) < 1.0 - 1e-9:
		guard -= 1
		if guard < 0:
			return false                        # float drift: be safe, not sorry
		if absf(tx - ty) < 1e-9:
			if _cell_blocked(Vector2i(cell.x + sx, cell.y), role) \
					or _cell_blocked(Vector2i(cell.x, cell.y + sy), role):
				return false
			cell += Vector2i(sx, sy)
			tx += tdx
			ty += tdy
		elif tx < ty:
			cell.x += sx
			tx += tdx
		else:
			cell.y += sy
			ty += tdy
		if _cell_blocked(cell, role):
			return false
	return not _cell_blocked(goal, role)

func _cell_blocked(cell: Vector2i, role: int) -> bool:
	return terrain.is_blocked(Vector2((cell.x + 0.5) * Terrain.CELL, (cell.y + 0.5) * Terrain.CELL), role)

## The shortest way on the terrain grid from `from` to `to` for `role`, as the
## points to walk after `from`, ending on `to`: grid cells' centres (kept on
## the field), pulled tight so each leg runs as far as it can straight. Every
## leg is walkable. Empty when the field offers no way.
func _grid_way(role: int, from: Vector2, to: Vector2) -> PackedVector2Array:
	var grid := _route_grid(role)
	var start := terrain.cell_of(from)
	var goal := terrain.cell_of(to)
	if not grid.region.has_point(start) or not grid.region.has_point(goal) \
			or grid.is_point_solid(start) or grid.is_point_solid(goal):
		return PackedVector2Array()
	var cells := grid.get_id_path(start, goal)
	if cells.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array()
	var inner := field.grow(-ROUTE_EPSILON)
	for i in range(1, cells.size() - 1):
		var centre := Vector2((cells[i].x + 0.5) * Terrain.CELL, (cells[i].y + 0.5) * Terrain.CELL)
		pts.append(centre.clamp(inner.position, inner.end))
	pts.append(to)
	var way := PackedVector2Array()
	var anchor := from
	var i := 0
	while i < pts.size():
		if not _walkable(role, anchor, pts[i]):
			return PackedVector2Array()         # cannot happen on a grid path; stay safe
		var j := i
		while j + 1 < pts.size() and _walkable(role, anchor, pts[j + 1]):
			j += 1
		way.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return way

## The field's terrain cells as an A* grid for `role`, built once per battle:
## cells `role` cannot stand on are solid; diagonal steps never cut a corner.
func _route_grid(role: int) -> AStarGrid2D:
	if _route_grids.has(role):
		return _route_grids[role]
	var first := terrain.cell_of(field.position)
	var past := terrain.cell_of(field.end - Vector2.ONE * ROUTE_EPSILON) + Vector2i.ONE
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(first, past - first)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y in range(first.y, past.y):
		for x in range(first.x, past.x):
			if _cell_blocked(Vector2i(x, y), role):
				grid.set_point_solid(Vector2i(x, y), true)
	_route_grids[role] = grid
	return grid

## Every block of `group` follows the lead's cleaned route, offset by where it
## stood relative to the lead, in the route's own frame so the shape turns
## with it: on open ground the line keeps its shape the whole way. Where an
## offset point is blocked or off the field, or the leg to it is not walkable,
## the follower takes the lead's point there instead (round on the terrain grid
## if even that leg is not walkable): the line squeezes into a column through a
## gap and fans out after. Marching blocks pass through friends, so followers
## sharing the lead's points never jam. A follower that cannot end on its own
## offset ends its frontage (and a hair) further back along the lead's route
## than the one before, so no two end on one point. Every leg of every route,
## its first from where the block stands included, is walkable. A follower
## left with no route holds. Routing blocks are left alone.
func order_group_route(group: Array[Block], lead: Block, points: PackedVector2Array,
		end_facing := NAN, target: Block = null) -> void:
	var route := clean_route(lead, points)
	if route.is_empty():
		return
	var heading0 := _route_heading(lead, route)
	var full := PackedVector2Array([lead.pos])
	full.append_array(route)
	var total := _polyline_length(full)
	var ends: Array[Vector2] = [route[route.size() - 1]]   # where blocks will stand at the end
	var plans := []                            # [block, points, last point, ends on its own offset]
	for b in group:
		if not b.alive() or b.routing:
			continue
		if b == lead:
			order_route(b, route, end_facing, target)
			continue
		var offs := _offset_route(route, heading0, (b.pos - lead.pos).rotated(-heading0))
		var pts := PackedVector2Array()
		var last := b.pos
		if not field.has_point(last):              # set down off the field: walk on first
			var inner := field.grow(-ROUTE_EPSILON)
			last = _join(pts, last, last.clamp(inner.position, inner.end))
		for i in route.size() - 1:
			if _offset_ok(b, last, offs[i]):
				last = _join(pts, last, offs[i])
			else:
				last = _join_round(b.role, pts, last, route[i])
		var own := _offset_ok(b, last, offs[route.size() - 1])
		if own:
			last = _join(pts, last, offs[route.size() - 1])
			ends.append(last)
		plans.append([b, pts, last, own])
	# The rest end in column along the lead's route, each at the first place
	# back from its end clear of every end already taken.
	var back := 0.0
	for plan in plans:
		var b: Block = plan[0]
		var pts: PackedVector2Array = plan[1]
		if not plan[3]:
			var at := Vector2.INF
			while at == Vector2.INF or (back < total and _near_any(at, ends, b.frontage())):
				back += b.frontage() + 6.0
				at = _point_along(full, maxf(0.0, total - back))
			ends.append(at)
			_join_round(b.role, pts, plan[2], at)
		if pts.is_empty() and target == null:
			order_hold(b)
		else:
			order_route(b, pts, end_facing, target)

## The heading a group's shape is set in: the stroke's own direction, from its
## first cleaned point to the first one at least a frontage on (so where on the
## lead the drag was pressed cannot skew it); for a route shorter than that,
## the way from the lead to its end if that is a frontage off, else the lead's
## facing.
func _route_heading(lead: Block, route: PackedVector2Array) -> float:
	var reach := lead.frontage()
	for i in range(1, route.size()):
		if route[i].distance_to(route[0]) >= reach:
			return (route[i] - route[0]).angle()
	var whole := route[route.size() - 1] - lead.pos
	return whole.angle() if whole.length() >= reach else lead.facing

## Is `p` within `reach` of any of `points`?
func _near_any(p: Vector2, points: Array[Vector2], reach: float) -> bool:
	for q in points:
		if q.distance_to(p) < reach:
			return true
	return false

## Can `b` stand at `p` and walk to it straight from `last`?
func _offset_ok(b: Block, last: Vector2, p: Vector2) -> bool:
	return not terrain.is_blocked(p, b.role) and field.has_point(p) and _walkable(b.role, last, p)

## The lead's `route` shifted by `local` (an offset in the frame of
## `heading0`, the shape's heading), re-applied at each point's own heading so
## the shape turns with the route. The first point takes `heading0` itself: the
## leg to it from the lead's centre says more about where the drag was pressed
## than where the line is going.
func _offset_route(route: PackedVector2Array, heading0: float,
		local: Vector2) -> PackedVector2Array:
	var offs := PackedVector2Array()
	for i in route.size():
		var ahead := route[i] - route[i - 1] if i > 0 else Vector2.ZERO
		var h := ahead.angle() if ahead.length_squared() > 0.01 else heading0
		offs.append(route[i] + local.rotated(h))
	return offs

## Append `p` (a walkable step on from `last`) unless it repeats it; the new last.
func _join(pts: PackedVector2Array, last: Vector2, p: Vector2) -> Vector2:
	if last.distance_to(p) > ROUTE_EPSILON:
		pts.append(p)
	return p

## Append the way to `p` for `role`: straight if walkable, else round on the
## terrain grid; if the field offers no way, `p` is skipped. The new last.
func _join_round(role: int, pts: PackedVector2Array, last: Vector2, p: Vector2) -> Vector2:
	if _walkable(role, last, p):
		return _join(pts, last, p)
	var way := _grid_way(role, last, p)
	for q in way:
		last = _join(pts, last, q)
	return last

## Where each block of `group` stands on a formation line drawn as `stroke`:
## infantry spread evenly along it at least a frontage apart, archers a rank
## behind, cavalry on the wings past its ends; with no infantry the archers
## take the line. A rank too long for the line spills into further ranks
## behind, and blocks take the slots in their current order along the line, so
## no paths cross. Everyone faces perpendicular to the line, away from home;
## a line drawn straight toward home faces the enemy's blocks instead.
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
	var home: Vector2 = home_dir.get(group[0].side, Vector2.ZERO)
	if absf(normal.dot(home)) < 0.01:
		var enemy := _enemy_centroid(group[0].side)
		if enemy != Vector2.INF and normal.dot(enemy - (a + z) * 0.5) < 0.0:
			normal = -normal
	elif normal.dot(home) > 0.0:
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
	var ranks := _fill_ranks(out, line, stroke, length, facing, normal, 0, gap)
	if not inf.is_empty():
		_fill_ranks(out, arc, stroke, length, facing, normal, ranks, gap)
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
	# A block holding on a bridge deck would close the crossing to every block
	# still to come (a bridge cell holds one block), and one on a standing
	# friend outside the group would stack on it for good: such a slot moves
	# back, a rank gap at a time, clear of the other slots.
	for s in out:
		var p: Vector2 = s["pos"]
		var moves := 0
		while moves < 8 and (terrain.biome_at(p) == Terrain.Biome.BRIDGE \
				or _on_standing_friend(s["block"], p, facing, group) \
				or (moves > 0 and _slot_taken(out, s, p))):
			p -= normal * gap
			moves += 1
		s["pos"] = p
	return out

## Would `b`, standing at `p` facing `facing`, be deep in a live friend outside
## `group` that is not marching (so will stay where it is)?
func _on_standing_friend(b: Block, p: Vector2, facing: float, group: Array[Block]) -> bool:
	var was_pos := b.pos
	var was_facing := b.facing
	b.pos = p
	b.facing = facing
	var hit := false
	for o in blocks:
		if o != b and o.alive() and o.side == b.side and not o.routing and not group.has(o) \
				and not _marching(o) and b.overlaps_deeply(o):
			hit = true
			break
	b.pos = was_pos
	b.facing = was_facing
	return hit

## Is `p` within a frontage of a slot in `out` other than `mine`?
func _slot_taken(out: Array[Dictionary], mine: Dictionary, p: Vector2) -> bool:
	for s in out:
		if s != mine and s["pos"].distance_to(p) < mine["block"].frontage():
			return true
	return false

## The centre of the alive blocks not on `side`, or Vector2.INF if none.
func _enemy_centroid(side: int) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for b in blocks:
		if b.side != side and b.alive():
			sum += b.pos
			n += 1
	return sum / float(n) if n > 0 else Vector2.INF

## Put `blocks` (sorted along the line) along `stroke`, in ranks from
## `first_rank` back (each `gap` behind the one before), as many per rank as
## fit a frontage (and a hair) apart. The blocks standing furthest forward
## (toward the enemy) take the front rank, the next the rank behind, and so on,
## so no block walks through a rank in front of its own; within a rank they
## keep their order along the line, so no two cross. Every slot records its
## rank. Returns the ranks used.
func _fill_ranks(out: Array[Dictionary], blocks: Array[Block], stroke: PackedVector2Array,
		length: float, facing: float, normal: Vector2, first_rank: int, gap: float) -> int:
	if blocks.is_empty():
		return 0
	var w := blocks[0].frontage() + 6.0
	var per_rank := maxi(1, int(length / w))
	var along := {}
	for i in blocks.size():
		along[blocks[i]] = i
	# Furthest forward first; level within a unit counts as level, and then the
	# order along the line decides.
	var forward_first := blocks.duplicate()
	forward_first.sort_custom(func(x: Block, y: Block) -> bool:
		var fx := roundf(x.pos.dot(normal))
		var fy := roundf(y.pos.dot(normal))
		return fx > fy or (fx == fy and along[x] < along[y]))
	var ranks := 0
	var i := 0
	while i < forward_first.size():
		var n := mini(per_rank, forward_first.size() - i)
		var rank: Array = forward_first.slice(i, i + n)
		rank.sort_custom(func(x: Block, y: Block) -> bool: return along[x] < along[y])
		var r := first_rank + ranks
		for k in n:
			var d := length * (float(k) + 0.5) / float(n)
			out.append({"block": rank[k], "pos": _point_along(stroke, d) - normal * (float(r) * gap),
				"facing": facing, "rank": r})
		i += n
		ranks += 1
	return ranks

## Send `group` to its formation slots along cleaned routes (over a bridge,
## round a bank). Marching blocks pass through friends, so crossing ways never
## jam. A slot on blocked ground, or one it has no way to: the block turns to
## the line's facing where it stands.
func order_formation(group: Array[Block], stroke: PackedVector2Array) -> void:
	for s in formation_slots(group, stroke):
		var b: Block = s["block"]
		var slot: Vector2 = s["pos"]
		var route := PackedVector2Array()
		if not terrain.is_blocked(slot, b.role) and field.has_point(slot):
			route = clean_route(b, PackedVector2Array([slot]))
		if route.is_empty():
			route = PackedVector2Array([b.pos])
		order_route(b, route, s["facing"])

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

# ----------------------------------------------------------------- simulation

func step(dt: float) -> void:
	if finished or not started:
		return
	time += dt

	BattleAI.run(self, dt)

	_damage_taken.clear()
	_update_locks(dt)
	for b in blocks:
		if b.alive():
			_move(b, dt)

	var contacts := _find_contacts()
	_sync_locks(contacts)
	_resolve_charges(contacts)
	_resolve_melee(contacts, dt)
	_resolve_ranged(dt)
	_resolve_morale(contacts, dt)
	_resolve_status(contacts, dt)
	for lock in locks:
		lock.settle(dt)
	_tick_reforms(contacts, dt)
	_prev_contacts = contacts
	_check_end()

func _move(b: Block, dt: float) -> void:
	var stats := b.stats()
	var speed: float = stats["speed"] * terrain.speed_multiplier(b.pos, b.role)
	var dest := Vector2.ZERO
	var moving := true
	if b.reforming():
		b.charge_run = 0.0
		return

	# A route drawn onto an enemy attacks it as soon as the block touches it on
	# the way — before the lock gates below, which would hold a Move in place.
	if b.order == Block.OrderType.MOVE and not b.routing:
		var aim := block_by_id(b.route_target_id)
		# (Not while it is stacked in a friend at the enemy: it backs out first.)
		if aim != null and aim.alive() and _prev_contacts.get(b.id, []).has(aim) and _stack_to_leave(b) == null:
			order_attack(b, aim)

	# A block attacking while in contact stays in the fight: it cannot push past
	# the enemy in front of it — which is what makes a screening block a screen.
	# The ways out are the lock rules below: Withdraw, a rout, or a Move by a
	# block winning every lock it is in.
	if (b.order == Block.OrderType.ATTACK or b.order == Block.OrderType.SHOOT) and not b.routing \
			and not _prev_contacts.get(b.id, []).is_empty():
		b.charge_run = 0.0
		return

	# Locked: a Move, an Attack or a Shoot on someone else does not walk a block
	# out of a fight. Withdraw, a rout, or winning every lock it is in are the
	# ways out.
	if not b.routing and b.order != Block.OrderType.WITHDRAW and not locks_of(b).is_empty() \
			and (b.order == Block.OrderType.MOVE or b.order == Block.OrderType.ATTACK
				or b.order == Block.OrderType.SHOOT):
		# A marcher that ended up stacked in a friend at the enemy (the enemy
		# turned or a friend seated into it) lets go and backs out.
		if b.order == Block.OrderType.MOVE and (push_state(b) == 1 or _stack_to_leave(b) != null):
			_release(b)
		else:
			b.charge_run = 0.0
			return

	if b.routing:
		dest = _destination(b)
		speed *= GameConfig.combat["rout_speed_multiplier"]
	else:
		match b.order:
			Block.OrderType.WITHDRAW:
				dest = _destination(b)
				speed *= GameConfig.combat["withdraw_speed_multiplier"]
			Block.OrderType.MOVE:
				var reach := float(GameConfig.combat["route_reach"])
				while b.route.size() > 1 and b.pos.distance_to(b.route[0]) <= reach:
					b.route.remove_at(0)
				dest = _destination(b)
			Block.OrderType.ATTACK:
				dest = _destination(b)
				if dest == Vector2.INF:
					b.order = Block.OrderType.NONE
					moving = false
			Block.OrderType.SHOOT:
				var mark := block_by_id(b.target_id)
				if mark == null or not mark.alive() or mark.status != Block.Status.ACTIVE:
					b.order = Block.OrderType.NONE
					moving = false
				elif in_reach(b, mark):
					# In reach and in sight: stand, face it and shoot.
					b.turn_toward((mark.pos - b.pos).angle(), dt)
					moving = false
				else:
					dest = mark.pos
			_:
				moving = false

	if not moving:
		b.hold_time += dt
		if b.order == Block.OrderType.HOLD and b.stats()["can_brace"] \
				and b.hold_time >= GameConfig.combat["brace_time"]:
			b.braced = true
		b.charge_run = 0.0
		return

	var to_dest := dest - b.pos
	if to_dest.length() < 1.0:
		if b.order == Block.OrderType.MOVE:
			_arrive(b, dt)
		return

	# A marcher stacked in a friend at the enemy backs straight out of it,
	# without turning, and then waits behind (see _stacks_into_fight).
	if _marching(b):
		var stack := _stack_to_leave(b)
		if stack != null:
			var away := b.pos - stack.pos
			if away.length() < 0.01:
				away = Vector2.LEFT.rotated(b.facing)
			_try_step(b, away.normalized(), speed * float(GameConfig.combat["march_overlap_speed"]) * dt)
			b.charge_run = 0.0
			return

	var dir := to_dest.normalized()
	# Turn first: a formed block wheels rather than spinning on the spot. A
	# rout runs while it turns — stopping to pivot in contact would be death.
	var was_facing := b.facing
	var off := b.turn_toward(dir.angle(), dt)
	if not b.routing and off > deg_to_rad(GameConfig.combat["pivot_angle"]):
		b.charge_run = 0.0
		return
	# A small correction never swings a solid block's wide front into a friend
	# coming the other way (two friends passing head-on sidestep with a hair of
	# ground to spare): it keeps its facing and steps on. A marching block walks
	# through friends anyway, slowed while it is deep in one.
	var marching := _marching(b)
	if not b.routing and not marching and _turn_closes_on_friend(b, was_facing, dir):
		b.facing = was_facing
	if marching and _deep_in_friend(b):
		speed *= float(GameConfig.combat["march_overlap_speed"])
	var stride: float = speed * dt
	var blocked_ahead := terrain.is_blocked(b.pos + dir * stride, b.role)
	var moved := _try_step(b, dir, stride, to_dest.length())
	# A route point counts as reached route_reach short of it, and a slide
	# along a bank can leave a block off the cleaned line: when the ground
	# straight ahead is blocked and it cannot walk straight to its next point,
	# it cleans the rest of its route again from where it stands (round the
	# bank, over the bridge) — at most every RECLEAN_EVERY seconds, its
	# destination moving to the new route's end.
	if marching and blocked_ahead and time - float(_recleaned_at.get(b.id, -INF)) >= RECLEAN_EVERY \
			and not _walkable(b.role, b.pos, dest):
		_recleaned_at[b.id] = time
		var again := clean_route(b, b.route)
		if not again.is_empty():
			b.route = again
			b.order_point = again[again.size() - 1]

	if moved > 0.0:
		# A charge needs a straight run-up; turning resets it.
		if b.last_move_dir.dot(dir) > 0.9:
			b.charge_run += moved
		else:
			b.charge_run = moved
		b.last_move_dir = dir
	if terrain.biome_at(b.pos) == Terrain.Biome.FOREST:
		b.charge_run = 0.0

## Where `b`'s order is walking it, or Vector2.INF if it has nowhere to go
## (no walking order, or its Attack target is gone). Pure: `_move` pops the
## reached route points; this reads the first one still ahead, so the
## head-on test in `_heading` sees the real heading of a block on a route.
func _destination(b: Block) -> Vector2:
	if b.routing or b.order == Block.OrderType.WITHDRAW:
		return b.pos + home_dir.get(b.side, Vector2.ZERO) * BIG
	match b.order:
		Block.OrderType.MOVE:
			var reach := float(GameConfig.combat["route_reach"])
			for i in b.route.size():
				if i == b.route.size() - 1 or b.pos.distance_to(b.route[i]) > reach:
					return b.route[i]
			return b.order_point
		Block.OrderType.ATTACK:
			var target := block_by_id(b.target_id)
			if target == null or not target.alive():
				return Vector2.INF
			return target.pos
		Block.OrderType.SHOOT:
			var mark := block_by_id(b.target_id)
			if mark == null or not mark.alive() or in_reach(b, mark):
				return Vector2.INF              # standing and shooting
			return mark.pos
	return Vector2.INF

## The end of a route: attack its target, else turn to its end facing and
## hold, else stop.
func _arrive(b: Block, dt: float) -> void:
	var aim := block_by_id(b.route_target_id)
	if aim != null and aim.alive():
		# A route drawn onto an enemy: archers shoot it from where they stand,
		# everyone else closes and attacks.
		if b.stats()["ranged_dps"] > 0.0:
			order_shoot(b, aim)
		else:
			order_attack(b, aim)
		return
	# Ending deep in a friend that is staying put would stack the pair for good
	# (neither marching, both solid, and a pair may only move apart): walk on
	# to the nearest spot clear of every block first.
	if _deep_in_standing_friend(b):
		var spot := _free_spot(b)
		if spot != Vector2.INF:
			b.route = PackedVector2Array([spot])
			b.order_point = spot
			return
	if not is_nan(b.end_facing):
		if b.turn_toward(b.end_facing, dt) > 0.001:
			return                              # still turning; stays on the spot
		order_hold(b)
		return
	b.route = PackedVector2Array()
	b.order = Block.OrderType.NONE

## Is `b` deep in a live friend that is not marching (so will not walk off)?
func _deep_in_standing_friend(b: Block) -> bool:
	for o in blocks:
		if o != b and o.alive() and o.side == b.side and not o.routing and not _marching(o) \
				and b.overlaps_deeply(o):
			return true
	return false

## The nearest spot to `b` clear of every other block at its end facing: open
## ground on the field that `b` can walk to straight, searched in rings half a
## frontage apart (8 × ring points each, up to 8 rings). Vector2.INF if none.
func _free_spot(b: Block) -> Vector2:
	var facing := b.end_facing if not is_nan(b.end_facing) else b.facing
	var step := b.frontage() * 0.5
	var was_pos := b.pos
	var was_facing := b.facing
	var found := Vector2.INF
	for ring in range(1, 9):
		var n := 8 * ring
		for k in n:
			var p := was_pos + Vector2.RIGHT.rotated(TAU * float(k) / float(n)) * step * float(ring)
			if terrain.is_blocked(p, b.role) or not field.has_point(p) or not _walkable(b.role, was_pos, p):
				continue
			b.pos = p
			b.facing = facing
			var clear := true
			for o in blocks:
				if o != b and o.alive() and not (o.routing and o.side == b.side) and b.overlaps_deeply(o):
					clear = false
					break
			b.pos = was_pos
			b.facing = was_facing
			if clear:
				found = p
				break
		if found != Vector2.INF:
			break
	return found

## Move, sliding along blocked terrain rather than stopping dead on it. A
## friend walking head-on into a block, between it and its goal, is walked
## round: before the axis slides (which, for two friends meeting on an axis,
## are just the heading, or step straight back onto the line), the block
## sidesteps along its own frontage, away from that friend, so the pair step
## apart and pass. A friend standing, or walking the same way (a queue behind a
## slower block), is waited on or slid past as before.
func _try_step(b: Block, dir: Vector2, stride: float, reach := INF) -> float:
	var candidates: Array[Vector2] = [dir]
	var side := _sidestep(b, dir, stride, reach)
	if side != Vector2.ZERO:
		candidates.append(side)
	candidates.append_array([Vector2(dir.x, 0.0).normalized(), Vector2(0.0, dir.y).normalized()])
	for candidate in candidates:
		if candidate.length_squared() < 0.001:
			continue
		var next: Vector2 = b.pos + candidate * stride
		if terrain.is_blocked(next, b.role):
			continue
		# Routing blocks are allowed to run off the field; everyone else is not,
		# though one standing off it (set down or pushed there) may walk back on.
		if not b.routing and not field.has_point(next) \
				and (field.has_point(b.pos) or _off_field(next) >= _off_field(b.pos)):
			continue
		if _blocked(b, next) or _bridge_lane_taken(b, next):
			continue
		b.pos = next
		return stride
	return 0.0

## How far `p` lies outside the field (0 on it).
func _off_field(p: Vector2) -> float:
	return p.distance_to(p.clamp(field.position, field.end))

## Did turning `b` (walking along `dir`) from `was_facing` put it deep into a
## friend coming head-on that it was clear of?
func _turn_closes_on_friend(b: Block, was_facing: float, dir: Vector2) -> bool:
	var now := b.facing
	for other in blocks:
		if other == b or not other.alive() or other.side != b.side or other.routing:
			continue
		if not b.overlaps_deeply(other) or not _head_on(dir, other):
			continue
		b.facing = was_facing
		var before := b.overlaps_deeply(other)
		b.facing = now
		if not before:
			return true
	return false

## The way to sidestep the nearest friend coming head-on that a stride along
## `dir` would close on, if it stands nearer than the goal: along `b`'s
## frontage, away from it (dead ahead: to `b`'s left). ZERO when there is none,
## when `b` is routing, or when `b` is already deep in some block (then it may
## only back out).
func _sidestep(b: Block, dir: Vector2, stride: float, reach: float) -> Vector2:
	if b.routing or _marching(b):
		return Vector2.ZERO                  # it walks through friends instead
	var ahead := b.pos + dir * stride
	var nearest: Block = null
	for other in blocks:
		if other == b or not other.alive():
			continue
		if b.overlaps_deeply(other):
			return Vector2.ZERO
		if other.side != b.side or other.routing or not _head_on(dir, other) \
				or not _closes_on(b, ahead, other):
			continue
		var d := b.pos.distance_to(other.pos)
		if d < reach and (nearest == null or d < b.pos.distance_to(nearest.pos)):
			nearest = other
	if nearest == null:
		return Vector2.ZERO
	var lateral := Vector2.RIGHT.rotated(b.facing).orthogonal()
	return -lateral if lateral.dot(nearest.pos - b.pos) > 0.001 else lateral

## Is `other` walking against a block heading along `dir` (within 60° of
## straight at it)? A friend standing, or merging from the side, is not.
func _head_on(dir: Vector2, other: Block) -> bool:
	return _heading(other).dot(dir) < -0.5

## Which way `b` is trying to walk (unit), or ZERO if it is standing: holding,
## reforming, arrived, or held in a fight.
func _heading(b: Block) -> Vector2:
	if b.routing or b.order == Block.OrderType.WITHDRAW:
		return (_destination(b) - b.pos).normalized()   # home, even while locked
	if b.reforming() or not locks_of(b).is_empty() or is_engaged(b):
		return Vector2.ZERO
	var dest := _destination(b)
	if dest == Vector2.INF:
		return Vector2.ZERO
	var to_dest := dest - b.pos
	return to_dest.normalized() if to_dest.length() >= 1.0 else Vector2.ZERO

## An enemy block is a wall: you may touch it and fight, never walk through it.
## A pair already deep in each other (a turn is not collision-checked, so a
## pivot or a reform can swing a block into its foe) may still move apart.
func _blocked_by_enemy(b: Block, next: Vector2) -> bool:
	for other in blocks:
		if other == b or not other.alive() or other.side == b.side:
			continue
		if _closes_on(b, next, other):
			return true
	return false

## Friends are solid too — a block waits or slides around a friend rather than
## shoving it — except that a pair already overlapping (a rally, a push) may
## move apart, a rout runs straight through its own side, and a marching block
## passes through friends (user decision 2026-09-24): lines squeeze through
## gaps and cross each other's ways without jamming. Passing through never
## moves the friend.
func _blocked(b: Block, next: Vector2) -> bool:
	if _blocked_by_enemy(b, next):
		return true
	if b.routing:
		return false
	if _marching(b):
		return _stacks_into_fight(b, next)
	return _blocked_by_friend(b, next)

## Would a marching `b` stepping to `next` stack onto a fight? Passing through a
## friend is fine, but not reaching an enemy from inside one — the pair would
## lock and fight stacked, two blocks through one frontage — and not walking
## into a friend that is itself in contact with the enemy (it would only wait
## there, stacked, for its turn): it goes round, or waits behind.
func _stacks_into_fight(b: Block, next: Vector2) -> bool:
	for other in blocks:
		if other == b or not other.alive() or other.side != b.side or other.routing:
			continue
		if _closes_on(b, next, other) and _touches_enemy(other):
			return true
	var was := b.pos
	b.pos = next
	var touching := _touches_enemy(b)
	var deep_in: Array[Block] = []
	if touching:
		for other in blocks:
			if other != b and other.alive() and other.side == b.side and b.overlaps_deeply(other):
				deep_in.append(other)
	b.pos = was
	for other in deep_in:
		# Already there and drawing apart: never refused (it is backing out).
		if b.overlaps_deeply(other) and _touches_enemy(b) and not _closes_on(b, next, other):
			continue
		# Two marchers arriving stacked (queued behind a friend that fell): the
		# lower id takes the fight, the other backs out (see _stack_to_leave).
		if other.order == Block.OrderType.MOVE and not other.routing and b.id < other.id:
			continue
		return true
	return false

## The friend a block on a Move must back out of, or null: one it is deep in
## that is touching an enemy — unless both are on a Move and at the enemy and
## `b` has the lower id, when the other one backs out.
func _stack_to_leave(b: Block) -> Block:
	if b.order != Block.OrderType.MOVE or b.routing:
		return null
	for other in blocks:
		if other == b or not other.alive() or other.side != b.side or other.routing:
			continue
		if not b.overlaps_deeply(other) or not _touches_enemy(other):
			continue
		if other.order == Block.OrderType.MOVE and b.id < other.id and _touches_enemy(b):
			continue
		return other
	return null

## Is `b` touching some live enemy?
func _touches_enemy(b: Block) -> bool:
	for other in blocks:
		if other.side != b.side and other.alive() and b.touches(other):
			return true
	return false

## Marching: walking a Move or a route, not locked in a fight, not routing.
## Standing, holding, bracing, fighting, attacking and withdrawing blocks are
## not, and stay solid to friends.
func _marching(b: Block) -> bool:
	return b.order == Block.OrderType.MOVE and not b.routing and locks_of(b).is_empty()

## Is `b` deep in some live friend?
func _deep_in_friend(b: Block) -> bool:
	for other in blocks:
		if other != b and other.alive() and other.side == b.side and b.overlaps_deeply(other):
			return true
	return false

func _blocked_by_friend(b: Block, next: Vector2) -> bool:
	for other in blocks:
		if other == b or not other.alive() or other.side != b.side or other.routing:
			continue
		if _closes_on(b, next, other):
			return true
	return false

## Would stepping `b` to `next` push it into `other`? A new deep overlap does;
## a pair already overlapping may only move apart (never deeper, never through).
func _closes_on(b: Block, next: Vector2, other: Block) -> bool:
	if b.overlaps_deeply(other):
		return next.distance_to(other.pos) < b.pos.distance_to(other.pos)
	var was := b.pos
	b.pos = next
	var after := b.overlaps_deeply(other)
	b.pos = was
	return after

## Somewhere `b` may be put by seating or a push: open ground, on the field
## (unless routing), a free bridge lane, and no new overlap (nor closing on a
## block it already overlaps) with any block
## except those in `ignore` (the ones it is locked with).
func _can_stand(b: Block, next: Vector2, ignore: Array) -> bool:
	if terrain.is_blocked(next, b.role):
		return false
	if not b.routing and not field.has_point(next):
		return false
	if _bridge_lane_taken(b, next):
		return false
	for other in blocks:
		if other == b or not other.alive() or ignore.has(other):
			continue
		if b.routing and other.side == b.side:
			continue
		if _closes_on(b, next, other):
			return false
	return true

## "Only one block wide": a bridge cell holds one block. Blocks may still queue
## along the bridge, one behind the other — that is length, not width.
func _bridge_lane_taken(b: Block, next: Vector2) -> bool:
	if terrain.biome_at(next) != Terrain.Biome.BRIDGE:
		return false
	var cell := terrain.cell_of(next)
	if terrain.cell_of(b.pos) == cell:
		return false                     # already standing there
	for other in blocks:
		if other == b or not other.alive():
			continue
		if terrain.cell_of(other.pos) == cell:
			return true
	return false

## id -> Array[Block] of hostile blocks currently touching it.
func _find_contacts() -> Dictionary:
	var out := {}
	for b in blocks:
		if b.alive():
			out[b.id] = [] as Array[Block]
	for i in blocks.size():
		var a := blocks[i]
		if not a.alive():
			continue
		for j in range(i + 1, blocks.size()):
			var b := blocks[j]
			if not b.alive() or a.side == b.side:
				continue
			if a.touches(b):
				out[a.id].append(b)
				out[b.id].append(a)
	return out

func _contact_key(a: Block, b: Block) -> String:
	return "%d-%d" % [mini(a.id, b.id), maxi(a.id, b.id)]

# ---------------------------------------------------------------------- locks

## Live locks `b` is in. A lock whose partner died, routed or withdrew since the
## last `_sync_locks` is already over and never returned.
func locks_of(b: Block) -> Array[Contact]:
	var out: Array[Contact] = []
	for lock in locks:
		if lock.has(b) and _live(lock):
			out.append(lock)
	return out

func _live(lock: Contact) -> bool:
	return _can_lock(lock.initiator) and _can_lock(lock.target)

func _lock_between(a: Block, b: Block) -> Contact:
	for lock in locks:
		if lock.has(a) and lock.has(b):
			return lock
	return null

func _pair_key(a: Block, b: Block) -> String:
	return _contact_key(a, b)

## A block that can hold a lock: alive, not routing, not pulling back.
func _can_lock(b: Block) -> bool:
	return b.alive() and not b.routing and b.order != Block.OrderType.WITHDRAW

## End locks that broke (no longer touching, a rout, a withdrawal, a death) and
## start one for every touching pair that has none. A pair a winner walked out
## of is left alone until it separates, so the walk-out is not undone.
func _sync_locks(contacts: Dictionary) -> void:
	var kept: Array[Contact] = []
	for lock in locks:
		if _live(lock) and contacts.get(lock.initiator.id, []).has(lock.target):
			kept.append(lock)
	locks = kept
	var touching := {}
	for a in blocks:
		for b in contacts.get(a.id, []):
			if a.id < b.id:
				touching[_pair_key(a, b)] = true
				if _released.has(_pair_key(a, b)) or _lock_between(a, b) != null:
					continue
				if _can_lock(a) and _can_lock(b):
					locks.append(Contact.begin(a, b))
	for key in _released.keys():
		if not touching.has(key):
			_released.erase(key)

## Pull every initiator flush against the face it struck; a front-to-front
## lock squares both blocks. Runs before free movement each step. A block in
## several locks turns once and slides once: its first lock as initiator
## decides both; failing that, its first front lock as target decides its
## heading (a target is never seated). Every heading and goal is read from
## this step's positions once the losers have been pushed, then all are applied.
func _update_locks(dt: float) -> void:
	_push(dt)
	var plan: Array = []                 # [block, heading, goal or null]
	var seen := {}
	for lock in locks:
		for b: Block in [lock.initiator, lock.target]:
			if seen.has(b.id):
				continue
			seen[b.id] = true
			var chosen := _governing_lock(b)
			# A reforming block is disordered: it neither turns nor is seated.
			# It may still be pushed as a loser — it keeps taking the fight.
			if chosen == null or b.reforming():
				continue
			# A losing initiator is pushed off the face, not pulled back onto it.
			var seats := chosen.initiator == b and chosen.loser() != b
			plan.append([b, _seat_heading(chosen, b), _seat_goal(chosen) if seats else null])
	var max_step := float(GameConfig.combat["seat_speed"]) * dt
	for entry in plan:
		entry[0].turn_toward(entry[1], dt)
	for entry in plan:
		if entry[2] != null:
			_slide(entry[0], entry[2], max_step)

## The lock that sets `b`'s heading (and, if `b` initiated it, its seat).
func _governing_lock(b: Block) -> Contact:
	var mine := locks_of(b)
	for lock in mine:
		if lock.initiator == b:
			return lock
	for lock in mine:
		if lock.target == b and lock.squares():
			return lock
	return null

## Front-to-front: face along the line between the pair. Otherwise the
## initiator faces into the struck face.
func _seat_heading(lock: Contact, b: Block) -> float:
	if lock.squares():
		var axis := _seat_axis(lock)
		return axis.angle() if b == lock.initiator else (-axis).angle()
	return (-Contact.normal(lock.target, lock.face)).angle()

## Where the initiator sits flush against the face it struck.
func _seat_goal(lock: Contact) -> Vector2:
	var i := lock.initiator
	var t := lock.target
	if lock.squares():
		return t.pos - _seat_axis(lock) * ((i.depth() + t.depth()) * 0.5 - SEAT_OVERLAP)
	var n := Contact.normal(t, lock.face)
	return t.pos + n * (Contact.half_extent(t, lock.face) + i.depth() * 0.5 - SEAT_OVERLAP)

func _seat_axis(lock: Contact) -> Vector2:
	var axis := lock.target.pos - lock.initiator.pos
	return axis.normalized() if axis.length_squared() > 0.0001 \
		else Vector2.RIGHT.rotated(lock.initiator.facing)

## Move `b` toward `goal` by at most `max_step`, if it may stand there.
func _slide(b: Block, goal: Vector2, max_step: float) -> void:
	var to_goal := goal - b.pos
	if to_goal.length() < 0.0001:
		return
	var next := b.pos + to_goal.limit_length(max_step)
	var partners: Array = []
	for lock in locks_of(b):
		partners.append(lock.other(b))
	if _can_stand(b, next, partners):
		b.pos = next

## Every lock's loser gives ground along the contact line, away from the
## winner, at push_per_dps × the gap (capped); a block losing several locks
## moves once, by their capped sum. Blocked ground stops it — nobody overlaps.
## Every partner winning against the loser steps after it by the same amount,
## so the fight is still touching at this step's contact check; if any of them
## cannot (it is in other fights, or blocked), the loser holds and the fight
## grinds in place. A partner fighting it evenly is not dragged, and the loser
## may not be pushed into it. This runs before seating, so an initiator in
## several fights re-seats onto its pushed target in the same step instead.
## Within the push no block is moved more than once per step; that says nothing
## of seating and free movement, which may move it again in the same step.
func _push(dt: float) -> void:
	var shove := {}                      # loser -> summed push velocity
	var order: Array[Block] = []         # losers, in lock order (deterministic)
	for lock in locks:
		if not _live(lock):
			continue
		var lose := lock.loser()
		if lose == null:
			continue
		var win := lock.other(lose)
		var speed := minf(absf(lock.gap(win)) * float(GameConfig.combat["push_per_dps"]),
			float(GameConfig.combat["push_max"]))
		var n: Vector2                   # from the target toward the initiator
		if lock.squares():
			n = (lock.initiator.pos - lock.target.pos).normalized()
		else:
			n = Contact.normal(lock.target, lock.face)
		var dir := -n if lose == lock.target else n
		if not shove.has(lose):
			order.append(lose)
		shove[lose] = shove.get(lose, Vector2.ZERO) + dir * speed
	var moved := {}                      # block id -> true once pushed or pulled along
	for lose in order:
		var step_v: Vector2 = (shove[lose] as Vector2).limit_length(
			float(GameConfig.combat["push_max"])) * dt
		if moved.has(lose.id):
			continue
		# The fight moves with it: every partner winning against it steps along
		# by the same amount, as one group (not checked against each other; an
		# even partner stays put and is solid). If any winner cannot follow (it
		# is in other fights, was already moved, or is blocked), the loser holds
		# this step instead: giving ground would part that pair and the lock
		# would drop and re-form at zero pressure. (A winner in only this lock
		# is a loser nowhere, so it has no shove of its own.)
		var group: Array = [lose]
		for lock in locks_of(lose):
			if lock.loser() == lose:
				group.append(lock.other(lose))
		if not _can_stand(lose, lose.pos + step_v, group):
			continue
		var held := false
		for p: Block in group:
			if p != lose and (moved.has(p.id) or locks_of(p).size() != 1
					or not _can_stand(p, p.pos + step_v, group)):
				held = true
				break
		if held:
			continue
		for p: Block in group:
			p.pos += step_v
			moved[p.id] = true

## 1: ahead in every lock by more than the dead band. -1: behind in at least
## one. 0: not locked, or even somewhere.
func push_state(b: Block) -> int:
	var mine := locks_of(b)
	if mine.is_empty():
		return 0
	var winning := true
	for lock in mine:
		if lock.loser() == b:
			return -1
		if lock.gap(b) <= float(GameConfig.combat["push_deadband"]):
			winning = false
	return 1 if winning else 0

## A winner walking out: its locks end and the pairs are left alone until they
## separate, so the lock is not re-made the next step.
func _release(b: Block) -> void:
	for lock in locks_of(b):
		_released[_pair_key(lock.initiator, lock.target)] = true
		locks.erase(lock)

# --------------------------------------------------------------------- reform

func _cancel_reform(b: Block) -> void:
	b.reform_left = 0.0
	b.reform_target_id = -1

func reform_facing(b: Block) -> float:
	var target := block_by_id(b.reform_target_id)
	if target == null or not target.alive():
		return b.facing
	return (target.pos - b.pos).angle()

func damage_multiplier(b: Block) -> float:
	return float(GameConfig.combat["reform_damage"]) if b.reforming() else 1.0

## Count reforms down; the one that finishes turns its block to face the
## target, and every lock it is the target of re-reads which face was struck.
## A lock it had initiated on anyone but its reform target is recast with the
## other block striking it: that foe is now off its front, and leaving the
## reformed block the initiator would turn it straight back onto that foe.
## A reform whose target died, broke, pulled back or is no longer touching is
## called off: there is nothing left there to face. So is one whose own block
## can no longer hold a lock (it died, broke or is pulling back).
func _tick_reforms(contacts: Dictionary, dt: float) -> void:
	for b in blocks:
		if not b.reforming():
			continue
		var target := block_by_id(b.reform_target_id)
		if not _can_lock(b) or target == null or not _can_lock(target) \
				or not contacts.get(b.id, []).has(target):
			_cancel_reform(b)
			continue
		b.reform_left -= dt
		if b.reform_left > 0.0:
			continue
		b.reform_left = 0.0
		b.facing = reform_facing(b)
		b.reform_target_id = -1
		for lock in locks_of(b):
			if lock.initiator == b and lock.target != target:
				lock.initiator = lock.target
				lock.target = b
			if lock.target == b:
				lock.face = Contact.face_of(b, lock.initiator.pos)

func _resolve_charges(contacts: Dictionary) -> void:
	for a in blocks:
		if not a.alive() or a.role != GameConfig.Role.CAVALRY:
			continue
		for b in contacts.get(a.id, []):
			if _prev_contacts.has(a.id) and _prev_contacts[a.id].has(b):
				continue    # already in contact last step; not a fresh charge

			# Cavalry catching a routing block destroys it outright.
			if b.routing and not a.routing:
				b.health = 0.0
				b.status = Block.Status.DESTROYED
				_log("%s cavalry ran down a routing block" % _side_name(a.side))
				continue

			if a.routing or a.order == Block.OrderType.WITHDRAW:
				continue
			if a.charge_run < GameConfig.combat["charge_min_distance"] or a.charge_cooldown > 0.0:
				continue

			var burst: float = a.stats()["charge_burst"] * GameConfig.supply_multiplier(a.supply)
			if terrain.biome_at(a.pos) == Terrain.Biome.FOREST:
				burst = 0.0
			if terrain.height_at(b.pos) - terrain.height_at(a.pos) \
					>= GameConfig.terrain_mods["hill_height_threshold"]:
				burst *= GameConfig.terrain_mods["hill_charge_multiplier"]

			var arc := _arc(b, a.pos)
			if b.braced and arc == "front":
				burst *= GameConfig.combat["brace_charge_multiplier"]
				_hurt(a, GameConfig.combat["brace_counter_burst"])
				_log("braced infantry blunted a charge and counter-bursted")
			else:
				_log("%s cavalry charged %s into the %s" % [
					_side_name(a.side), _side_name(b.side), arc,
				])

			_hurt(b, burst)
			var lock := _lock_between(a, b)
			if lock != null:
				lock.record(a, burst)
			b.morale -= burst * GameConfig.combat["morale_per_health"]
			a.charge_cooldown = GameConfig.combat["charge_cooldown"]
			a.charge_run = 0.0

func _resolve_melee(contacts: Dictionary, dt: float) -> void:
	for a in blocks:
		if not a.alive():
			continue
		# Routing and withdrawing blocks deal no damage.
		if a.routing or a.order == Block.OrderType.WITHDRAW:
			continue
		for b in contacts.get(a.id, []):
			if not b.alive():
				continue
			var dps: float = a.stats()["melee_dps"] * GameConfig.supply_multiplier(a.supply) \
				* damage_multiplier(a)
			var arc := _arc(b, a.pos)
			var mult: float = GameConfig.combat["%s_damage" % arc]
			mult *= _uphill_dealt(a, b) * _uphill_taken(b, a)
			if b.routing:
				mult *= GameConfig.combat["rout_damage_multiplier"]
			var dmg: float = dps * mult * dt
			_hurt(b, dmg)
			var lock := _lock_between(a, b)
			if lock != null:
				lock.record(a, dmg)
			b.morale -= dmg * GameConfig.combat["morale_per_health"]
			b.morale -= _arc_morale(b, contacts) * dt

func _resolve_ranged(dt: float) -> void:
	for a in blocks:
		if not a.alive() or a.stats()["ranged_dps"] <= 0.0:
			continue
		a.shooting_id = -1
		if a.routing or a.order == Block.OrderType.WITHDRAW:
			continue
		if not _prev_contacts.get(a.id, []).is_empty():
			continue          # archers in melee fight as weak infantry instead
		var target := _ranged_target(a)
		if target == null:
			continue
		a.shooting_id = target.id
		var dmg: float = a.stats()["ranged_dps"] * GameConfig.supply_multiplier(a.supply) * dt
		_hurt(target, dmg)
		target.morale -= dmg * GameConfig.combat["morale_per_health"]

## How far `a` shoots from where it stands on the flat: its role's range, cut
## in a forest. Shooting down a slope reaches further (hill_range_bonus), which
## `_ranged_target` applies per target; this is the reach the view rings.
func shooting_range(a: Block) -> float:
	var reach: float = a.stats()["range"]
	if terrain.biome_at(a.pos) == Terrain.Biome.FOREST:
		reach *= GameConfig.terrain_mods["forest_archer_range"]
	return reach

## The distance `a` measures to `b` for a shot: shortened when shooting down a
## slope (hill_range_bonus).
func _shot_distance(a: Block, b: Block) -> float:
	var d: float = a.pos.distance_to(b.pos)
	if terrain.height_at(a.pos) - terrain.height_at(b.pos) \
			>= GameConfig.terrain_mods["hill_height_threshold"]:
		d /= GameConfig.terrain_mods["hill_range_bonus"]
	return d

## `b` is within `a`'s reach and in its line of sight — where a Shoot order
## stops walking. Whether `a` may actually loose at it is `can_shoot`.
func in_reach(a: Block, b: Block) -> bool:
	return _shot_distance(a, b) <= shooting_range(a) \
		and not terrain.blocks_line_of_sight(a.pos, b.pos)

## `a` can shoot `b` right now: a live enemy, in reach and sight, and not in
## melee with one of `a`'s side (archers don't shoot into their own melee).
func can_shoot(a: Block, b: Block) -> bool:
	return b.alive() and b.side != a.side and in_reach(a, b) and not _in_melee_with_friend(a, b)

## Who `a` shoots this step: its Shoot target when it can be shot, else the
## nearest enemy it can shoot.
func _ranged_target(a: Block) -> Block:
	if a.order == Block.OrderType.SHOOT:
		var mark := block_by_id(a.target_id)
		if mark != null and can_shoot(a, mark):
			return mark
	var best: Block = null
	var best_d := INF
	for b in blocks:
		if not can_shoot(a, b):
			continue
		var d := _shot_distance(a, b)
		if d < best_d:
			best = b
			best_d = d
	return best

func _in_melee_with_friend(a: Block, target: Block) -> bool:
	for other in _prev_contacts.get(target.id, []):
		if other.side == a.side:
			return true
	return false

func _resolve_morale(contacts: Dictionary, dt: float) -> void:
	for b in blocks:
		if not b.alive():
			continue
		var engaged: Array = contacts.get(b.id, [])

		if engaged.size() >= 2:
			b.morale -= GameConfig.combat["outnumbered_morale"] * dt
		if terrain.biome_at(b.pos) == Terrain.Biome.SWAMP:
			b.morale -= GameConfig.terrain_mods["swamp_morale_drain"] * dt
		if engaged.is_empty() and not b.routing and _damage_taken.get(b.id, 0.0) <= 0.0:
			b.morale += GameConfig.combat["morale_recovery"] * dt

		b.morale = clampf(b.morale, 0.0, b.max_morale)

func _resolve_status(contacts: Dictionary, dt: float) -> void:
	for b in blocks:
		# Kills are settled first: alive() is false the moment health hits zero,
		# so anything that skipped dead blocks would never mark them destroyed.
		if b.status == Block.Status.ACTIVE and b.health <= 0.0:
			b.status = Block.Status.DESTROYED
			_log("%s %s destroyed" % [_side_name(b.side), b.stats()["name"].to_lower()])
			continue
		if not b.alive():
			continue
		b.charge_cooldown = maxf(0.0, b.charge_cooldown - dt)
		b.hit_flash = maxf(0.0, b.hit_flash - dt)

		var engaged: bool = not contacts.get(b.id, []).is_empty()

		if not b.routing and b.morale <= 0.0:
			b.routing = true
			b.ever_routed = true
			b.braced = false
			b.rout_recover = 0.0
			_cancel_reform(b)
			_log("%s %s routs" % [_side_name(b.side), b.stats()["name"].to_lower()])
			_spread_panic(b)
			continue

		if b.routing:
			if engaged:
				b.rout_recover = 0.0
			else:
				b.rout_recover += dt
				if b.rout_recover >= GameConfig.combat["rout_recover_time"]:
					b.routing = false
					b.morale = GameConfig.combat["rout_recover_morale"]
					b.rout_recover = 0.0
					b.order = Block.OrderType.NONE
					_log("%s %s rallies" % [_side_name(b.side), b.stats()["name"].to_lower()])
			if not field.has_point(b.pos):
				b.status = Block.Status.FLED
				_log("%s %s fled the field" % [_side_name(b.side), b.stats()["name"].to_lower()])

		elif b.order == Block.OrderType.WITHDRAW and not field.has_point(b.pos):
			b.status = Block.Status.FLED

## A block breaking shakes everyone who can see it, once.
func _spread_panic(router: Block) -> void:
	for other in blocks:
		if other == router or other.side != router.side or not other.alive():
			continue
		if other.seen_ally_rout or other.pos.distance_to(router.pos) > GameConfig.combat["ally_rout_radius"]:
			continue
		other.seen_ally_rout = true
		other.morale -= GameConfig.combat["ally_rout_morale"]

# ------------------------------------------------------------------- modifiers

## Arc of an attack, with the bridge rule folded in: a block on a bridge has no
## exposed flanks, so side attacks resolve as front or rear.
func _arc(defender: Block, from: Vector2) -> String:
	var arc := defender.arc_from(from)
	if arc == "flank" and terrain.biome_at(defender.pos) == Terrain.Biome.BRIDGE:
		var angle := absf(rad_to_deg(Vector2.RIGHT.rotated(defender.facing).angle_to(from - defender.pos)))
		return "front" if angle <= 90.0 else "rear"
	return arc

## Morale drain per second on `b` from the arcs it is being hit from, doubled
## when it is held by the front and hit from the side or back.
func _arc_morale(b: Block, contacts: Dictionary) -> float:
	var drain := 0.0
	var has_front := false
	var has_side := false
	for a in contacts.get(b.id, []):
		if a.routing or a.order == Block.OrderType.WITHDRAW:
			continue
		var arc := _arc(b, a.pos)
		drain += GameConfig.combat["%s_morale" % arc]
		if arc == "front":
			has_front = true
		else:
			has_side = true
	if has_front and has_side:
		drain *= GameConfig.combat["flanked_morale_multiplier"]
	# _resolve_melee calls this once per attacker, so share it out.
	var attackers: int = maxi(1, contacts.get(b.id, []).size())
	return drain / float(attackers)

func _uphill_dealt(attacker: Block, defender: Block) -> float:
	if _ground_height(attacker) - _ground_height(defender) \
			>= GameConfig.terrain_mods["hill_height_threshold"]:
		return GameConfig.terrain_mods["hill_damage_dealt"]
	return 1.0

func _uphill_taken(defender: Block, attacker: Block) -> float:
	if _ground_height(defender) - _ground_height(attacker) \
			>= GameConfig.terrain_mods["hill_height_threshold"]:
		return GameConfig.terrain_mods["hill_damage_taken"]
	return 1.0

## The height a block fights from: its rear rank. Two blocks in contact share
## a front line, so the ground under their backs is what tells them apart.
func _ground_height(b: Block) -> float:
	return terrain.height_at(b.pos - Vector2.RIGHT.rotated(b.facing) * b.depth() * 0.5)

func _hurt(b: Block, amount: float) -> void:
	b.health -= amount
	b.hit_flash = 0.3
	_damage_taken[b.id] = _damage_taken.get(b.id, 0.0) + amount

# ----------------------------------------------------------------------- end

func _check_end() -> void:
	var player_left := side_blocks(GameConfig.Side.PLAYER, true).size()
	var enemy_left := side_blocks(GameConfig.Side.ENEMY, true).size()

	if time >= GameConfig.combat["battle_seconds"]:
		_finish("time")
	elif player_left == 0 and enemy_left == 0:
		_finish("mutual collapse")
	elif player_left == 0:
		_finish("enemy broke the line")
	elif enemy_left == 0:
		_finish("player broke the line")

func _finish(reason: String) -> void:
	finished = true
	var centre := field.get_center()
	var holder := -1
	var best := INF
	for b in blocks:
		if not b.alive() or b.routing:
			continue
		var d: float = b.pos.distance_to(centre)
		if d < best:
			best = d
			holder = b.side

	var rows: Array = []
	var losses := {GameConfig.Side.PLAYER: 0, GameConfig.Side.ENEMY: 0}
	for b in blocks:
		var fate := "held"
		if b.status == Block.Status.DESTROYED:
			fate = "destroyed"
		elif b.status == Block.Status.FLED:
			fate = "fled"
		elif b.routing:
			fate = "routing"
		elif b.withdrew:
			fate = "withdrew"
		if fate == "destroyed" or fate == "fled" or fate == "routing":
			losses[b.side] += 1
		rows.append({
			"side": b.side,
			"role": b.role,
			"name": b.stats()["name"],
			"health": maxf(0.0, b.health),
			"max_health": b.max_health,
			"fate": fate,
			# Campaign stub: a block that fled survives at half strength.
			"carries_forward": (b.health * 0.5) if fate == "fled" else maxf(0.0, b.health),
		})

	result = {
		"reason": reason,
		"seconds": time,
		"holder": holder,
		"feature": terrain.feature_at(centre).get("type", "open ground"),
		"rows": rows,
		"losses": losses,
	}
	_log("battle over: %s" % reason)

func _side_name(side: int) -> String:
	return "player" if side == GameConfig.Side.PLAYER else "enemy"

func _log(text: String) -> void:
	events.append("%5.1fs  %s" % [time, text])
	if events.size() > 60:
		events.remove_at(0)
