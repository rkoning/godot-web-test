class_name Terrain
extends RefCounted

## The one terrain dataset, rendered at both zooms. Nothing is authored twice.
##
## The map is hand-authored as two character grids: biome and height. Features
## (hills, forests, the river, bridges) are derived from those grids at load, so
## editing the art below is the only way to change the map.

enum Biome { PLAIN, FOREST, SWAMP, CLIFF, WATER, BRIDGE }

const CELL := 20.0
const COLS := 60
const ROWS := 40
const SIZE := Vector2(COLS * CELL, ROWS * CELL)

## . plain   f forest   s swamp   ^ cliff   ~ water   = bridge
const BIOME_ART: PackedStringArray = [
	"............................~~~......................^^^^^^^",
	"............................~~~......................^^^^^^^",
	"............................~~~......................^^^^^^^",
	"............................~~~......................^^^^^^^",
	"............................~~~.....fffffffffff......^^^^^^^",
	"............................~~~.....fffffffffff......^^^^^^^",
	"............................~~~.....fffffffffff.............",
	"............................~~~.....fffffffffff.............",
	"..............................~~~...fffffffffff.............",
	"..............................~~~...fffffffffff.............",
	"..............................~~~...fffffffffff.............",
	"..............................~~~...fffffffffff.............",
	"..............................~~~...........................",
	"..............................~~~...........................",
	"..............................~~~...........................",
	"..............................~~~...........................",
	"..............................~~~...........................",
	"............................~~~.............................",
	"............................~~~.............................",
	"............................===.............................",
	"............................~~~.............................",
	"............................~~~.............................",
	"............................~~~.............................",
	"............................~~~.............................",
	"............................~~~.............................",
	"............................~~~.............................",
	"........fffffffff...........~~~.............................",
	"........fffffffff...........~~~.............................",
	"........fffffffff...........~~~.............................",
	"........fffffffff...........~~~.............................",
	"........fffffffff...sssssss~~~..............................",
	"........fffffffff...sssssss~~~..............................",
	"........fffffffff...sssssss~~~..............................",
	"........fffffffff...sssssss~~~..............................",
	"....................sssssss~~~..............................",
	"....................sssssss~~~..............................",
	"....................sssssss~~~..............................",
	"...........................~~~..............................",
	"...........................~~~..............................",
	"...........................~~~..............................",
]

## Height in steps of HEIGHT_STEP world units; hills are bumps in this grid.
const HEIGHT_STEP := 8.0
const HEIGHT_ART: PackedStringArray = [
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000001111100000000000000000000000000000000000000000",
	"000000000000122232221000000000000000000000000000000000000000",
	"000000000001233444332100000000000000000000000000000000000000",
	"000000000002344555443200000000000000000000000000000000000000",
	"000000000012345666543210000000000000000000000000000000000000",
	"000000000012456787654210000000000000000000000000000000000000",
	"000000000013456898654310000000000000000000000000111110000000",
	"000000000012456787654210000000000000000000000001122211000000",
	"000000000012345666543210000000000000000000000011233321100000",
	"000000000002344555443200000000000000000000000012344432100000",
	"000000000001233444332100000000000000000000000012345432100000",
	"000000000000122232221000000000000000000000000012344432100000",
	"000000000000001111100000000000000000000000000011233321100000",
	"000000000000000000000000000000000000000000111111122211000000",
	"000000000000000000000000000000000000000011222221111110000000",
	"000000000000000000000000000000000000000122333332210000000000",
	"000000000000000000000000000000000000001233444443321000000000",
	"000000000000000000000000000000000000001234556554321000000000",
	"000000000000000000000000000000000000012345667665432100000000",
	"000000000000000000000000000000000000012345678765432100000000",
	"000000000000000000000000000000000000012346789876432100000000",
	"000000000000000000000000000000000000012345678765432100000000",
	"000000000000000000000000000000000000012345667665432100000000",
	"000000000000000000000000000000000000001234556554321000000000",
	"000000000000000000000000000000000000001233444443321000000000",
	"000000000000000000000000000000000000000122333332210000000000",
	"000000000000000000000000000000000000000011222221100000000000",
	"000000000000000000000000000000000000000000111110000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
	"000000000000000000000000000000000000000000000000000000000000",
]

## Roads as polylines in world units. Movement is cheaper along them.
static var ROADS: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(0, 430), Vector2(240, 445), Vector2(480, 415), Vector2(590, 400), Vector2(700, 385), Vector2(940, 360), Vector2(1200, 345)]),
	PackedVector2Array([Vector2(700, 385), Vector2(800, 330), Vector2(900, 285), Vector2(1010, 250)]),
]

const ROAD_WIDTH := 26.0

var height: PackedFloat32Array = PackedFloat32Array()
var biome: PackedByteArray = PackedByteArray()
var features: Array[Dictionary] = []

func _init() -> void:
	_parse_art()
	_derive_features()

# ---------------------------------------------------------------- grid access

func in_bounds(pos: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x < SIZE.x and pos.y < SIZE.y

func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(pos.x / CELL), 0, COLS - 1),
		clampi(int(pos.y / CELL), 0, ROWS - 1),
	)

func biome_at(pos: Vector2) -> int:
	var c := cell_of(pos)
	return biome[c.y * COLS + c.x]

func height_at(pos: Vector2) -> float:
	var c := cell_of(pos)
	return height[c.y * COLS + c.x]

## Terrain a block cannot stand on at all.
func is_blocked(pos: Vector2, role: int) -> bool:
	if not in_bounds(pos):
		return true
	var b := biome_at(pos)
	if b == Biome.CLIFF:
		return true
	if b == Biome.WATER:
		return true
	if b == Biome.SWAMP and role == GameConfig.Role.CAVALRY:
		return true
	return false

func on_road(pos: Vector2) -> bool:
	for road in ROADS:
		for i in road.size() - 1:
			var d := Geometry2D.get_closest_point_to_segment(pos, road[i], road[i + 1])
			if pos.distance_to(d) <= ROAD_WIDTH * 0.5:
				return true
	return false

## Speed multiplier for a role at a position.
func speed_multiplier(pos: Vector2, role: int) -> float:
	var mult := 1.0
	match biome_at(pos):
		Biome.FOREST:
			if role == GameConfig.Role.CAVALRY:
				mult *= GameConfig.terrain_mods["forest_cavalry_speed"]
		Biome.SWAMP:
			mult *= GameConfig.terrain_mods["swamp_speed"]
	if on_road(pos):
		mult *= GameConfig.terrain_mods["road_speed"]
	return mult

## Does a straight segment cross terrain that blocks line of sight?
func blocks_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var steps := maxi(2, int(from.distance_to(to) / (CELL * 0.5)))
	var eye_height: float = maxf(height_at(from), height_at(to))
	for i in range(1, steps):
		var p: Vector2 = from.lerp(to, float(i) / float(steps))
		if biome_at(p) == Biome.FOREST:
			return true
		# A hill between the two ends blocks sight unless the viewer is on it.
		if height_at(p) > eye_height + GameConfig.terrain_mods["hill_height_threshold"]:
			return true
	return false

# ------------------------------------------------------------------- features

## Human-readable description used by the strategic hover tooltip.
func describe(pos: Vector2) -> Dictionary:
	if not in_bounds(pos):
		return {"name": "off map", "effect": ""}
	var b := biome_at(pos)
	var h := height_at(pos)
	if b == Biome.BRIDGE:
		return {
			"name": "Bridge",
			"effect": "One block wide; a block here can only be engaged from front and back.",
		}
	if b == Biome.WATER:
		return {"name": "River", "effect": "Impassable except at bridges."}
	if b == Biome.CLIFF:
		return {"name": "Cliff", "effect": "Impassable edge; blocks cannot be pushed through."}
	if b == Biome.FOREST:
		return {
			"name": "Forest",
			"effect": "Blocks hidden until within 40u; cavalry at 50% speed and no charge; archers lose half their range.",
		}
	if b == Biome.SWAMP:
		return {
			"name": "Swamp",
			"effect": "Everything moves at 50%; cavalry cannot enter; morale drains while inside.",
		}
	if h >= GameConfig.terrain_mods["hill_height_threshold"]:
		return {
			"name": "Hill (height %d)" % int(h),
			"effect": "Uphill defender deals +25% and takes −25%; charges uphill lose half their bonus.",
		}
	if on_road(pos):
		return {"name": "Road", "effect": "Movement +25%."}
	return {"name": "Plain", "effect": "No modifiers."}

## Nearest derived feature to a point, or {} if none is close.
func feature_at(pos: Vector2, radius: float = 60.0) -> Dictionary:
	var best := {}
	var best_d := radius
	for f in features:
		var d: float = pos.distance_to(f["centroid"])
		if d < best_d:
			best_d = d
			best = f
	return best

## True when a straight line between two points passes over water.
func crosses_water(from: Vector2, to: Vector2) -> bool:
	var steps := maxi(2, int(from.distance_to(to) / (CELL * 0.5)))
	for i in range(1, steps + 1):
		var p: Vector2 = from.lerp(to, float(i) / float(steps))
		if in_bounds(p) and biome_at(p) == Biome.WATER:
			return true
	return false

## Centre of the closest bridge feature, or Vector2.INF when the map has none.
func nearest_bridge(pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for f in features:
		if f["type"] != "bridge":
			continue
		var d: float = pos.distance_to(f["centroid"])
		if d < best_d:
			best_d = d
			best = f["centroid"]
	return best

# -------------------------------------------------------------------- parsing

func _parse_art() -> void:
	height.resize(COLS * ROWS)
	biome.resize(COLS * ROWS)
	for r in ROWS:
		var brow: String = BIOME_ART[r]
		var hrow: String = HEIGHT_ART[r]
		for c in COLS:
			var i := r * COLS + c
			biome[i] = _biome_char(brow[c])
			height[i] = float(hrow[c].to_int()) * HEIGHT_STEP

func _biome_char(ch: String) -> int:
	match ch:
		"f": return Biome.FOREST
		"s": return Biome.SWAMP
		"^": return Biome.CLIFF
		"~": return Biome.WATER
		"=": return Biome.BRIDGE
		_: return Biome.PLAIN

## Flood-fill the grids into contiguous regions, so features are derived rather
## than authored a second time.
func _derive_features() -> void:
	features.clear()
	var seen := {}
	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			if seen.has(i):
				continue
			var kind := _feature_kind(i)
			if kind == "":
				continue
			var cells := _flood(i, kind, seen)
			if cells.size() < 3:
				continue
			var centroid := Vector2.ZERO
			var lo := Vector2(SIZE)
			var hi := Vector2.ZERO
			for ci in cells:
				var p := Vector2(
					(ci % COLS) * CELL + CELL * 0.5,
					(ci / COLS) * CELL + CELL * 0.5,
				)
				centroid += p
				lo = lo.min(p)
				hi = hi.max(p)
			features.append({
				"type": kind,
				"centroid": centroid / float(cells.size()),
				"bounds": Rect2(lo, hi - lo),
				"cells": cells.size(),
			})

func _feature_kind(i: int) -> String:
	match biome[i]:
		Biome.FOREST: return "forest"
		Biome.SWAMP: return "swamp"
		Biome.WATER: return "river"
		Biome.BRIDGE: return "bridge"
		Biome.CLIFF: return "cliff"
	if height[i] >= GameConfig.terrain_mods["hill_height_threshold"]:
		return "hill"
	return ""

func _flood(start: int, kind: String, seen: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var stack: Array[int] = [start]
	seen[start] = true
	while not stack.is_empty():
		var i: int = stack.pop_back()
		out.append(i)
		var c := i % COLS
		var r := i / COLS
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: int = c + d.x
			var nr: int = r + d.y
			if nc < 0 or nr < 0 or nc >= COLS or nr >= ROWS:
				continue
			var ni: int = nr * COLS + nc
			if seen.has(ni) or _feature_kind(ni) != kind:
				continue
			seen[ni] = true
			stack.append(ni)
	return out
