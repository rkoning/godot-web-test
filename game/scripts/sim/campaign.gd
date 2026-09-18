class_name Campaign
extends RefCounted

## Strategic zoom: armies as points, turn-based movement over the same terrain
## the battle uses. Paths are A* over the terrain grid, so they follow roads
## wherever roads are cheaper without any special-casing.

var terrain: Terrain
var armies: Array[Army] = []
var turn := 1
var selected: Army = null

var _grid: AStarGrid2D

func _init(p_terrain: Terrain) -> void:
	terrain = p_terrain
	_build_grid()

func player_army() -> Army:
	for a in armies:
		if a.side == GameConfig.Side.PLAYER:
			return a
	return null

## Army marker under a point. `radius` is in world units; the caller widens it
## for touch, where a fingertip is a lot bigger than a cursor.
func army_at(pos: Vector2, radius := 24.0) -> Army:
	for a in armies:
		if a.pos.distance_to(pos) <= radius:
			return a
	return null

# ------------------------------------------------------------------ pathing

## The terrain grid as an A* grid. Cost is distance divided by the terrain's
## speed multiplier, which is what makes roads win without a "snap to road"
## rule; water and cliffs are solid.
func _build_grid() -> void:
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, Terrain.COLS, Terrain.ROWS)
	_grid.cell_size = Vector2(Terrain.CELL, Terrain.CELL)
	_grid.offset = Vector2(Terrain.CELL, Terrain.CELL) * 0.5      # cell centres
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()

	# Weights are relative to the fastest ground, so the road is 1.0 and
	# everything else costs more; A* wants weights of at least one.
	var fastest: float = GameConfig.terrain_mods["road_speed"]
	for r in Terrain.ROWS:
		for c in Terrain.COLS:
			var cell := Vector2i(c, r)
			var centre := Vector2(c * Terrain.CELL + Terrain.CELL * 0.5, r * Terrain.CELL + Terrain.CELL * 0.5)
			if terrain.is_blocked(centre, GameConfig.Role.INFANTRY):
				_grid.set_point_solid(cell, true)
			else:
				_grid.set_point_weight_scale(cell,
					fastest / terrain.speed_multiplier(centre, GameConfig.Role.INFANTRY))

## Waypoints from `from` to `to`, ending exactly on `to`. Empty if unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not terrain.in_bounds(to):
		return PackedVector2Array()
	var start := terrain.cell_of(from)
	var goal := terrain.cell_of(to)
	if _grid.is_point_solid(goal):
		return PackedVector2Array()
	var points := _grid.get_point_path(start, goal)
	if points.is_empty():
		return PackedVector2Array()
	points.remove_at(0)                 # the army is already standing on the first cell
	if points.is_empty():
		points.append(to)
	else:
		points[points.size() - 1] = to
	return points

## Grow a path being drawn by hand: route from wherever it currently ends to
## the next point under the finger. Unreachable points are simply skipped, so
## a stroke dragged across the river still produces a legal route around it.
func extend_path(from: Vector2, path: PackedVector2Array, to: Vector2) -> PackedVector2Array:
	var tail: Vector2 = path[path.size() - 1] if path.size() > 0 else from
	var segment := find_path(tail, to)
	if segment.is_empty():
		return path
	var out := path.duplicate()
	out.append_array(segment)
	return out

## Movement cost of a polyline, in the same units as the movement budget.
func path_cost(from: Vector2, points: PackedVector2Array) -> float:
	var total := 0.0
	var prev := from
	for p in points:
		var seg := prev.distance_to(p)
		var mid: Vector2 = prev.lerp(p, 0.5)
		total += seg / terrain.speed_multiplier(mid, GameConfig.Role.INFANTRY)
		prev = p
	return total

func turns_for(from: Vector2, points: PackedVector2Array) -> int:
	var budget: float = GameConfig.strategic["army_move_budget"]
	return int(ceil(path_cost(from, points) / maxf(1.0, budget)))

# -------------------------------------------------------------------- turns

## Advance every army along its path, then report an engagement if one happened.
## Returns the two armies that met, or an empty array.
func end_turn() -> Array[Army]:
	for a in armies:
		a.moved_this_turn = false
		if a.side == GameConfig.Side.ENEMY and a.path.is_empty() and not a.scripted.is_empty():
			a.path = a.scripted.duplicate()
			a.scripted = PackedVector2Array()
		_advance(a)
	turn += 1
	return _engagement()

func _advance(a: Army) -> void:
	if a.path.is_empty():
		return
	var budget: float = GameConfig.strategic["army_move_budget"]
	while budget > 0.0 and not a.path.is_empty():
		var next: Vector2 = a.path[0]
		var seg := a.pos.distance_to(next)
		var mid: Vector2 = a.pos.lerp(next, 0.5)
		var cost := seg / terrain.speed_multiplier(mid, GameConfig.Role.INFANTRY)
		if cost <= budget:
			a.pos = next
			a.path.remove_at(0)
			budget -= cost
			a.moved_this_turn = true
		else:
			var t := budget / cost
			a.pos = a.pos.lerp(next, t)
			a.moved_this_turn = true
			budget = 0.0

func _engagement() -> Array[Army]:
	var reach: float = GameConfig.strategic["engagement_range"]
	for i in armies.size():
		for j in range(i + 1, armies.size()):
			var a := armies[i]
			var b := armies[j]
			if a.side != b.side and a.pos.distance_to(b.pos) <= reach:
				return [a, b] as Array[Army]
	return [] as Array[Army]
