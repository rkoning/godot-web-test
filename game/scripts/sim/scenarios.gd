class_name Scenarios
extends RefCounted

## The three shipped set-pieces. Each one is data: army placement, rosters,
## supply, and which battle behaviour the enemy runs.

const INF_ := GameConfig.Role.INFANTRY
const CAV := GameConfig.Role.CAVALRY
const ARC := GameConfig.Role.ARCHERS

static func all() -> Array[Dictionary]:
	return [
		{
			"name": "The Ford",
			"lesson": "Brace on the bridge: only the front and back of a block on it can be hit.",
			"player": {
				"pos": Vector2(660, 400),
				"supply": 1.0,
				"roster": [INF_, INF_, ARC, CAV],
			},
			"enemy": {
				"pos": Vector2(480, 415),
				"supply": 0.6,
				"roster": [INF_, INF_, INF_, CAV, CAV, ARC],
				"behavior": "attacker",
				# Walks the road east, straight at the crossing.
				"scripted": PackedVector2Array([Vector2(560, 405), Vector2(600, 400)]),
			},
		},
		{
			"name": "The Hill",
			"lesson": "One turn to take the high ground. Uphill defenders deal +25% and take −25%.",
			"player": {
				"pos": Vector2(700, 490),
				"supply": 1.0,
				"roster": [INF_, INF_, ARC, CAV],
			},
			"enemy": {
				"pos": Vector2(1090, 490),
				"supply": 1.0,
				"roster": [INF_, INF_, ARC, CAV],
				"behavior": "attacker",
				"scripted": PackedVector2Array([Vector2(960, 490), Vector2(900, 490)]),
			},
		},
		{
			"name": "The Forest Ambush",
			"lesson": "Withdraw behind a screen. An uncovered withdrawal under cavalry is a massacre.",
			"player": {
				"pos": Vector2(880, 292),
				"supply": 1.0,
				"roster": [INF_, INF_, INF_, ARC],
			},
			"enemy": {
				"pos": Vector2(880, 200),
				"supply": 1.0,
				"roster": [CAV, CAV],
				"behavior": "attacker",
				"scripted": PackedVector2Array([Vector2(880, 250)]),
			},
		},
	]

static func build(index: int, terrain: Terrain) -> Campaign:
	var spec := all()[index]
	var campaign := Campaign.new(terrain)

	var p: Dictionary = spec["player"]
	var player := Army.new(GameConfig.Side.PLAYER, p["pos"], _roles(p["roster"]), p["supply"])
	player.label = "Your army"

	var e: Dictionary = spec["enemy"]
	var enemy := Army.new(GameConfig.Side.ENEMY, e["pos"], _roles(e["roster"]), e["supply"])
	enemy.label = "Enemy army"
	enemy.behavior = e["behavior"]
	enemy.scripted = e.get("scripted", PackedVector2Array())

	campaign.armies = [player, enemy]
	campaign.selected = player
	return campaign

## Dictionary literals give untyped arrays; Army wants Array[int].
static func _roles(raw: Array) -> Array[int]:
	var out: Array[int] = []
	for r in raw:
		out.append(int(r))
	return out

## Spawn both armies' blocks into a battle: a line with infantry in the centre,
## archers behind and cavalry on the outer flanks.
static func deploy(sim: BattleSim, army: Army, facing_dir: Vector2) -> void:
	var forward := facing_dir.normalized()
	var across := Vector2(-forward.y, forward.x)

	var infantry: Array[int] = []
	var cavalry: Array[int] = []
	var archers: Array[int] = []
	for role in army.roster:
		match role:
			GameConfig.Role.CAVALRY: cavalry.append(role)
			GameConfig.Role.ARCHERS: archers.append(role)
			_: infantry.append(role)

	var spacing := 30.0
	_line(sim, army, infantry, army.pos, across, spacing, forward)
	_line(sim, army, archers, army.pos - forward * 32.0, across, spacing, forward)

	# Cavalry sits outside the infantry line, one block per flank.
	var wing := (float(infantry.size()) * spacing) * 0.5 + spacing
	for i in cavalry.size():
		var offset: float = wing * (1.0 if i % 2 == 0 else -1.0) + float(i / 2) * spacing
		var pos: Vector2 = army.pos + across * offset
		sim.add_block(army.side, GameConfig.Role.CAVALRY,
			_free_spot(sim, pos, forward, army.pos), forward.angle())

static func _line(sim: BattleSim, army: Army, roles: Array[int], centre: Vector2,
		across: Vector2, spacing: float, forward: Vector2) -> void:
	for i in roles.size():
		var offset: float = (float(i) - (float(roles.size()) - 1.0) * 0.5) * spacing
		var slot: Vector2 = _free_spot(sim, centre + across * offset, forward, centre)
		sim.add_block(army.side, roles[i], slot, forward.angle())

## Find somewhere real for a block to stand.
##
## A slot that lands in the river, off a cliff or on top of an already-placed
## block collapses toward the centre of the line and falls in behind it. That is
## what turns a line abreast into a column when the front is one block wide, as
## it is on a bridge.
static func _free_spot(sim: BattleSim, pos: Vector2, forward: Vector2, centre: Vector2) -> Vector2:
	var back := -forward.normalized()
	if _spot_is_free(sim, pos):
		return pos
	for step in 8:
		var candidate: Vector2 = centre + back * (float(step) * 24.0)
		if _spot_is_free(sim, candidate):
			return candidate
	for step in 8:
		var candidate: Vector2 = pos + back * (float(step) * 24.0)
		if _spot_is_free(sim, candidate):
			return candidate
	for radius in [20.0, 40.0, 60.0, 80.0]:
		for step in 12:
			var angle := TAU * float(step) / 12.0
			var candidate: Vector2 = pos + Vector2.RIGHT.rotated(angle) * radius
			if _spot_is_free(sim, candidate):
				return candidate
	return pos

static func _spot_is_free(sim: BattleSim, pos: Vector2) -> bool:
	if sim.terrain.is_blocked(pos, GameConfig.Role.INFANTRY) or not sim.field.has_point(pos):
		return false
	for b in sim.blocks:
		if b.pos.distance_to(pos) < 22.0:
			return false
	return true

## Build a battle from two armies that just met on the strategic map.
##
## `crop` overrides the configured field size; the shell passes a portrait
## crop on a portrait phone so the field fills the screen instead of a strip.
static func start_battle(terrain: Terrain, player: Army, enemy: Army, crop := Vector2.ZERO) -> BattleSim:
	var sim := BattleSim.new()
	var mid: Vector2 = (player.pos + enemy.pos) * 0.5
	if crop == Vector2.ZERO:
		crop = GameConfig.strategic["battle_crop"]
	# The crop is the spec's 300x200 whenever the armies are in engagement range,
	# and grows only if they somehow met further apart than that.
	var span := Rect2(player.pos, Vector2.ZERO).expand(enemy.pos).grow(70.0)
	var field_size := Vector2(maxf(crop.x, span.size.x), maxf(crop.y, span.size.y)).min(Terrain.SIZE)
	var origin: Vector2 = (mid - field_size * 0.5).clamp(Vector2.ZERO, Terrain.SIZE - field_size)
	sim.setup(terrain, Rect2(origin, field_size))

	sim.supply[GameConfig.Side.PLAYER] = player.supply
	sim.supply[GameConfig.Side.ENEMY] = enemy.supply
	sim.behavior[GameConfig.Side.PLAYER] = player.behavior
	sim.behavior[GameConfig.Side.ENEMY] = enemy.behavior

	var axis: Vector2 = enemy.pos - player.pos
	if axis.length_squared() < 1.0:
		axis = Vector2.RIGHT
	axis = axis.normalized()
	sim.home_dir[GameConfig.Side.PLAYER] = -axis
	sim.home_dir[GameConfig.Side.ENEMY] = axis

	deploy(sim, player, axis)
	deploy(sim, enemy, -axis)

	# Whoever stood still is the defender, and only they get to re-arrange
	# before the clock starts.
	sim.player_is_defender = not player.moved_this_turn
	sim.started = not sim.player_is_defender
	return sim
