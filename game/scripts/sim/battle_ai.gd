class_name BattleAI
extends RefCounted

## Deliberately minimal and legible: the player should be able to read what the
## enemy is doing from the blocks alone. Two behaviours, picked per scenario.

const RETHINK_SECONDS := 0.4
const FLANK_OFFSET := 60.0
const COUNTER_CHARGE_RANGE := 60.0
const PULL_OUT_DISTANCE := 70.0

static func run(sim: BattleSim, dt: float) -> void:
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		var mode: String = sim.behavior.get(side, "")
		if mode == "":
			continue                     # player-controlled

		var timer: float = sim.ai_state.get(side, 0.0) - dt
		if timer > 0.0:
			sim.ai_state[side] = timer
			continue
		sim.ai_state[side] = RETHINK_SECONDS

		match mode:
			"attacker": _attacker(sim, side)
			"defender": _defender(sim, side)

static func _attacker(sim: BattleSim, side: int) -> void:
	var foes := sim.side_blocks(_other(side))
	if foes.is_empty():
		return

	for b in sim.side_blocks(side):
		if b.routing:
			continue
		var target := _nearest(b, foes)
		match b.role:
			GameConfig.Role.CAVALRY:
				_cavalry(sim, b, target, foes)
			GameConfig.Role.ARCHERS:
				# Archers walk into range and then stand and shoot.
				var reach: float = b.stats()["range"]
				if b.pos.distance_to(target.pos) > reach * 0.8:
					_move_to(sim, b, target.pos)
				else:
					sim.order_hold(b)
			_:
				sim.order_attack(b, target)

static func _defender(sim: BattleSim, side: int) -> void:
	var own := sim.side_blocks(side)
	if own.is_empty():
		return

	# Break off once the line is visibly going; half the blocks shaken is enough.
	var shaken := 0
	for b in own:
		if b.morale < 30.0:
			shaken += 1
	if shaken * 2 >= own.size():
		sim.retreat_all(side)
		return

	var foes := sim.side_blocks(_other(side))
	for b in own:
		if b.routing or b.order == Block.OrderType.WITHDRAW:
			continue
		if b.role == GameConfig.Role.CAVALRY:
			var threat := _flank_threat(b, own, foes)
			if threat != null:
				_cavalry(sim, b, threat, foes)
			else:
				sim.order_hold(b)
		else:
			# Infantry brace by holding; archers shoot from wherever they stand.
			sim.order_hold(b)

## Cavalry: swing wide to the target's flank, charge, then pull out to reset.
static func _cavalry(sim: BattleSim, b: Block, target: Block, foes: Array[Block]) -> void:
	if target == null:
		return

	# Fresh off a charge and still stuck in: back out rather than grind.
	if b.charge_cooldown > GameConfig.combat["charge_cooldown"] * 0.4:
		var away := (b.pos - target.pos).normalized() * PULL_OUT_DISTANCE
		_move_to(sim, b, b.pos + away)
		return

	# Prefer something already pinned by a friendly — that is where a flank hurts.
	var pinned := _pinned_target(sim, b, foes)
	if pinned != null:
		target = pinned

	var flank := _flank_point(target)
	if b.pos.distance_to(flank) > GameConfig.combat["charge_min_distance"]:
		_move_to(sim, b, flank)
	else:
		sim.order_attack(b, target)

static func _flank_point(target: Block) -> Vector2:
	var side_dir := Vector2.UP.rotated(target.facing)
	return target.pos + side_dir * FLANK_OFFSET

static func _pinned_target(sim: BattleSim, b: Block, foes: Array[Block]) -> Block:
	var best: Block = null
	var best_d := INF
	for f in foes:
		var engaged := false
		for other in sim.blocks:
			if other.alive() and other.side == b.side and other.role != GameConfig.Role.CAVALRY \
					and other.touches(f):
				engaged = true
				break
		if not engaged:
			continue
		var d: float = b.pos.distance_to(f.pos)
		if d < best_d:
			best_d = d
			best = f
	return best

## An enemy block sitting off the flank of one of ours, worth counter-charging.
static func _flank_threat(cav: Block, own: Array[Block], foes: Array[Block]) -> Block:
	for f in foes:
		for friend in own:
			if friend.role == GameConfig.Role.CAVALRY:
				continue
			if friend.pos.distance_to(f.pos) > COUNTER_CHARGE_RANGE:
				continue
			if friend.arc_from(f.pos) != "front":
				return f
	return null

## Straight line, except that water is routed around via the nearest bridge.
static func _move_to(sim: BattleSim, b: Block, dest: Vector2) -> void:
	var crossing := sim.terrain.crosses_water(b.pos, dest)
	if crossing:
		var bridge := sim.terrain.nearest_bridge(b.pos)
		if bridge != Vector2.INF and b.pos.distance_to(bridge) > 20.0:
			sim.order_move(b, bridge)
			return
	sim.order_move(b, dest)

static func _nearest(b: Block, others: Array[Block]) -> Block:
	var best: Block = null
	var best_d := INF
	for o in others:
		var d: float = b.pos.distance_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	return best

static func _other(side: int) -> int:
	return GameConfig.Side.ENEMY if side == GameConfig.Side.PLAYER else GameConfig.Side.PLAYER
