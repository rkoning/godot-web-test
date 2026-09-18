class_name BattleSim
extends RefCounted

## The real-time block battle. Deliberately free of any rendering or input, so
## the same code runs in the browser and headless in the acceptance tests.

const BIG := 10000.0

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
var _damage_taken := {}                    # id -> damage this step, for morale recovery

func setup(p_terrain: Terrain, p_field: Rect2) -> void:
	terrain = p_terrain
	field = p_field

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

# --------------------------------------------------------------------- orders

func order_move(b: Block, point: Vector2) -> void:
	b.order = Block.OrderType.MOVE
	b.order_point = point
	b.target_id = -1
	b.braced = false
	b.hold_time = 0.0

func order_attack(b: Block, target: Block) -> void:
	b.order = Block.OrderType.ATTACK
	b.target_id = target.id
	b.braced = false
	b.hold_time = 0.0

func order_hold(b: Block) -> void:
	b.order = Block.OrderType.HOLD
	b.target_id = -1
	b.hold_time = 0.0

func order_withdraw(b: Block) -> void:
	b.order = Block.OrderType.WITHDRAW
	b.target_id = -1
	b.braced = false
	b.withdrew = true

func retreat_all(side: int) -> void:
	for b in side_blocks(side):
		order_withdraw(b)

# ----------------------------------------------------------------- simulation

func step(dt: float) -> void:
	if finished or not started:
		return
	time += dt

	BattleAI.run(self, dt)

	_damage_taken.clear()
	for b in blocks:
		if b.alive():
			_move(b, dt)

	_separate()

	var contacts := _find_contacts()
	_resolve_charges(contacts)
	_resolve_melee(contacts, dt)
	_resolve_ranged(dt)
	_resolve_morale(contacts, dt)
	_resolve_status(contacts, dt)
	_prev_contacts = contacts
	_check_end()

func _move(b: Block, dt: float) -> void:
	var stats := b.stats()
	var speed: float = stats["speed"] * terrain.speed_multiplier(b.pos, b.role)
	var dest := Vector2.ZERO
	var moving := true

	# A block already in contact is locked in melee: it cannot push past the
	# enemy in front of it. Only an explicit Move (or a withdrawal, or a rout)
	# breaks contact — which is what makes a screening block a screen.
	if b.order == Block.OrderType.ATTACK and not b.routing \
			and not _prev_contacts.get(b.id, []).is_empty():
		b.charge_run = 0.0
		return

	if b.routing:
		dest = b.pos + home_dir[b.side] * BIG
		speed *= GameConfig.combat["rout_speed_multiplier"]
	else:
		match b.order:
			Block.OrderType.WITHDRAW:
				dest = b.pos + home_dir[b.side] * BIG
				speed *= GameConfig.combat["withdraw_speed_multiplier"]
			Block.OrderType.MOVE:
				dest = b.order_point
			Block.OrderType.ATTACK:
				var target := block_by_id(b.target_id)
				if target == null or not target.alive():
					b.order = Block.OrderType.NONE
					moving = false
				else:
					dest = target.pos
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
		b.order = Block.OrderType.NONE if b.order == Block.OrderType.MOVE else b.order
		return

	var dir := to_dest.normalized()
	var stride: float = speed * dt
	var moved := _try_step(b, dir, stride)

	if moved > 0.0:
		b.face_towards(dir)
		# A charge needs a straight run-up; turning resets it.
		if b.last_move_dir.dot(dir) > 0.9:
			b.charge_run += moved
		else:
			b.charge_run = moved
		b.last_move_dir = dir
	if terrain.biome_at(b.pos) == Terrain.Biome.FOREST:
		b.charge_run = 0.0

## Move, sliding along blocked terrain rather than stopping dead on it.
func _try_step(b: Block, dir: Vector2, stride: float) -> float:
	for candidate in [dir, Vector2(dir.x, 0.0).normalized(), Vector2(0.0, dir.y).normalized()]:
		if candidate.length_squared() < 0.001:
			continue
		var next: Vector2 = b.pos + candidate * stride
		if terrain.is_blocked(next, b.role):
			continue
		# Routing blocks are allowed to run off the field; everyone else is not.
		if not b.routing and not field.has_point(next):
			continue
		if _blocked_by_enemy(b, next) or _bridge_lane_taken(b, next):
			continue
		b.pos = next
		return stride
	return 0.0

## An enemy block is a wall: you may touch it and fight, never walk through it.
## Friendly blocks are not walls — they give way (see _separate) — because three
## blocks converging on one gap would otherwise wedge each other solid.
func _blocked_by_enemy(b: Block, next: Vector2) -> bool:
	var was := b.pos
	b.pos = next
	for other in blocks:
		if other == b or not other.alive() or other.side == b.side:
			continue
		if b.overlaps_deeply(other):
			b.pos = was
			return true
	b.pos = was
	return false

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

## Nudge blocks of the same side out of each other. Without this, friendlies
## converging on a gap lock solid and an attack simply stops arriving.
func _separate() -> void:
	for i in blocks.size():
		var a := blocks[i]
		if not a.alive():
			continue
		for j in range(i + 1, blocks.size()):
			var b := blocks[j]
			if not b.alive() or b.side != a.side:
				continue
			if not a.overlaps_deeply(b):
				continue
			var away := a.pos - b.pos
			if away.length_squared() < 0.01:
				away = Vector2.RIGHT.rotated(float(a.id))
			away = away.normalized() * 0.6
			_nudge(a, away)
			_nudge(b, -away)

func _nudge(b: Block, delta: Vector2) -> void:
	var next: Vector2 = b.pos + delta
	if terrain.is_blocked(next, b.role):
		return
	if not b.routing and not field.has_point(next):
		return
	if _bridge_lane_taken(b, next) or _blocked_by_enemy(b, next):
		return
	b.pos = next

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
			var dps: float = a.stats()["melee_dps"] * GameConfig.supply_multiplier(a.supply)
			var arc := _arc(b, a.pos)
			var mult: float = GameConfig.combat["%s_damage" % arc]
			mult *= _uphill_dealt(a, b) * _uphill_taken(b, a)
			if b.routing:
				mult *= GameConfig.combat["rout_damage_multiplier"]
			var dmg: float = dps * mult * dt
			_hurt(b, dmg)
			b.morale -= dmg * GameConfig.combat["morale_per_health"]
			b.morale -= _arc_morale(b, contacts) * dt

func _resolve_ranged(dt: float) -> void:
	for a in blocks:
		if not a.alive() or a.stats()["ranged_dps"] <= 0.0:
			continue
		if a.routing or a.order == Block.OrderType.WITHDRAW:
			continue
		if not _prev_contacts.get(a.id, []).is_empty():
			continue          # archers in melee fight as weak infantry instead
		var target := _ranged_target(a)
		if target == null:
			continue
		var dmg: float = a.stats()["ranged_dps"] * GameConfig.supply_multiplier(a.supply) * dt
		_hurt(target, dmg)
		target.morale -= dmg * GameConfig.combat["morale_per_health"]

func _ranged_target(a: Block) -> Block:
	var reach: float = a.stats()["range"]
	if terrain.biome_at(a.pos) == Terrain.Biome.FOREST:
		reach *= GameConfig.terrain_mods["forest_archer_range"]
	var best: Block = null
	var best_d := INF
	for b in blocks:
		if not b.alive() or b.side == a.side:
			continue
		var d: float = a.pos.distance_to(b.pos)
		if terrain.height_at(a.pos) - terrain.height_at(b.pos) \
				>= GameConfig.terrain_mods["hill_height_threshold"]:
			d /= GameConfig.terrain_mods["hill_range_bonus"]
		if d > reach or d >= best_d:
			continue
		if terrain.blocks_line_of_sight(a.pos, b.pos):
			continue
		if _in_melee_with_friend(a, b):
			continue          # don't shoot into our own melee
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

		var engaged: bool = not contacts.get(b.id, []).is_empty()

		if not b.routing and b.morale <= 0.0:
			b.routing = true
			b.ever_routed = true
			b.braced = false
			b.rout_recover = 0.0
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
	if terrain.height_at(attacker.pos) - terrain.height_at(defender.pos) \
			>= GameConfig.terrain_mods["hill_height_threshold"]:
		return GameConfig.terrain_mods["hill_damage_dealt"]
	return 1.0

func _uphill_taken(defender: Block, attacker: Block) -> float:
	if terrain.height_at(defender.pos) - terrain.height_at(attacker.pos) \
			>= GameConfig.terrain_mods["hill_height_threshold"]:
		return GameConfig.terrain_mods["hill_damage_taken"]
	return 1.0

func _hurt(b: Block, amount: float) -> void:
	b.health -= amount
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
