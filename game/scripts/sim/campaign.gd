class_name Campaign
extends RefCounted

## Strategic zoom: armies as points, turn-based movement over the same terrain
## the battle uses. Paths are A* over the terrain grid, so they follow roads
## wherever roads are cheaper without any special-casing.

var terrain: Terrain
var armies: Array[Army] = []
var turn := 1
var selected: Army = null

func _init(p_terrain: Terrain) -> void:
	terrain = p_terrain

func player_army() -> Army:
	for a in armies:
		if a.side == GameConfig.Side.PLAYER:
			return a
	return null

func army_at(pos: Vector2, radius := 24.0) -> Army:
	for a in armies:
		if a.pos.distance_to(pos) <= radius:
			return a
	return null

# ------------------------------------------------------------------ pathing

func _cell_cost(cell: Vector2i) -> float:
	var centre := Vector2(cell.x * Terrain.CELL + Terrain.CELL * 0.5, cell.y * Terrain.CELL + Terrain.CELL * 0.5)
	if terrain.is_blocked(centre, GameConfig.Role.INFANTRY):
		return -1.0
	return Terrain.CELL / terrain.speed_multiplier(centre, GameConfig.Role.INFANTRY)

## A* across the terrain grid. Cost is distance divided by the terrain's speed
## multiplier, which is what makes roads win without a "snap to road" rule.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := terrain.cell_of(from)
	var goal := terrain.cell_of(to)
	if _cell_cost(goal) < 0.0:
		return PackedVector2Array()

	var open := [[0.0, start]]
	var came := {}
	var best := {start: 0.0}

	while not open.is_empty():
		open.sort_custom(func(a, b): return a[0] < b[0])
		var current: Vector2i = open.pop_front()[1]
		if current == goal:
			break
		for d: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var next: Vector2i = current + d
			if next.x < 0 or next.y < 0 or next.x >= Terrain.COLS or next.y >= Terrain.ROWS:
				continue
			var cost := _cell_cost(next)
			if cost < 0.0:
				continue
			if d.x != 0 and d.y != 0:
				cost *= sqrt(2.0)
			var tentative: float = best[current] + cost
			if tentative < float(best.get(next, INF)):
				best[next] = tentative
				came[next] = current
				var h: float = Vector2(next - goal).length() * Terrain.CELL
				open.append([tentative + h, next])

	if not came.has(goal) and start != goal:
		return PackedVector2Array()

	var points := PackedVector2Array()
	var node := goal
	while node != start:
		points.append(Vector2(node.x * Terrain.CELL + Terrain.CELL * 0.5, node.y * Terrain.CELL + Terrain.CELL * 0.5))
		node = came[node]
	points.reverse()
	if points.size() > 0:
		points[points.size() - 1] = to
	return points

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
