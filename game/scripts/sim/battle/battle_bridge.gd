class_name BattleBridge
extends RefCounted

## WS-C: a campaign battle (an entry of `World.pending_battles`) becomes the
## combat prototype's `BattleSim`, and the sim's result becomes lost regiments
## and a retreat. No rules of the fight live here — only the translation.

## The player's stack in this battle, or null when the player is not in it.
static func player_stack(world: World, battle: Dictionary) -> Stack:
	for key in ["attacker", "defender"]:
		var s: Stack = battle[key]
		if world.nation(s.nation_id).is_player:
			return s
	return null

## The opponent of `s` in this battle.
static func other(battle: Dictionary, s: Stack) -> Stack:
	return battle["defender"] if s == battle["attacker"] else battle["attacker"]

## False once SupplyPhase (or anything else after EngagementPhase) has pulled
## a stack out from under a pending battle: both sides must still exist, both
## still on the battle's site, both still holding regiments.
static func valid(world: World, battle: Dictionary) -> bool:
	var att: Stack = battle.get("attacker")
	var def: Stack = battle.get("defender")
	if att == null or def == null:
		return false
	if not (world.stacks.has(att) and world.stacks.has(def)):
		return false
	var site_id := int(battle.get("site_id", -1))
	if att.site_id != site_id or def.site_id != site_id:
		return false
	return att.size() > 0 and def.size() > 0

## [Stack on Side.PLAYER, Stack on Side.ENEMY]. The player's stack is always
## Side.PLAYER so the view's colours and controls are the player's; with no
## player in the fight, the attacker is. Remembered on the battle so the result
## maps back onto the same stacks the sim was built from.
static func sides(world: World, battle: Dictionary) -> Array:
	var mine := player_stack(world, battle)
	var first: Stack = mine if mine != null else battle["attacker"]
	var out: Array = []
	out.resize(2)
	out[GameConfig.Side.PLAYER] = first
	out[GameConfig.Side.ENEMY] = other(battle, first)
	battle["sides"] = out
	return out

const ROLE_ORDER := [GameConfig.Role.INFANTRY, GameConfig.Role.CAVALRY, GameConfig.Role.ARCHERS]

## The regiments that take the field: all of them up to `max_blocks`, and past
## that one of each role in turn, so a big stack's reserve does not strip it of
## its only cavalry. The rest stay in reserve and are never lost in the battle.
static func fielded(s: Stack) -> Array[int]:
	var cap := int(GameConfig.battle_bridge["max_blocks"])
	var pools := {}
	for role in ROLE_ORDER:
		pools[role] = s.regiments.count(role)
	var out: Array[int] = []
	while out.size() < cap:
		var took := false
		for role in ROLE_ORDER:
			if out.size() >= cap:
				break
			if pools[role] > 0:
				pools[role] -= 1
				out.append(role)
				took = true
		if not took:
			break
	return out

## [Side.PLAYER army, Side.ENEMY army]. The defender stands on the site; the
## attacker arrives `approach_distance` back along the edge it marched in on,
## turned off water or cliffs if the straight line lands there. Supply crosses
## scales here and nowhere else: campaign 0..100, battle 0..1.
static func to_armies(world: World, terrain: Terrain, battle: Dictionary) -> Array[Army]:
	var side_stacks := sides(world, battle)
	var site: Site = world.graph.sites[battle["site_id"]]
	var dir := Vector2.RIGHT
	var from_id := int(battle["from_site"])
	if from_id >= 0:
		var d: Vector2 = world.graph.sites[from_id].pos - site.pos
		if d.length_squared() > 0.01:
			dir = d.normalized()
	var reach := float(GameConfig.battle_bridge["approach_distance"])
	var attack_pos := site.pos + dir * reach
	for turn in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]:
		if not terrain.is_blocked(attack_pos, GameConfig.Role.INFANTRY):
			break
		attack_pos = site.pos + dir.rotated(deg_to_rad(turn)) * reach

	var out: Array[Army] = []
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		var s: Stack = side_stacks[side]
		var attacking: bool = s == battle["attacker"]
		var army := Army.new(side, attack_pos if attacking else site.pos, fielded(s), s.supply / 100.0)
		army.label = s.label
		army.moved_this_turn = attacking
		out.append(army)
	return out

## Build the battle. The attacker's side runs the attacker AI and the
## defender's the defender AI, except a side the human plays; `ai_plays_player`
## hands that side to the AI too (headless tests, and a future "let the general
## fight it"). A human defender gets the prototype's pre-arrange phase.
static func start(world: World, terrain: Terrain, battle: Dictionary,
		crop := Vector2.ZERO, ai_plays_player := false) -> BattleSim:
	var armies := to_armies(world, terrain, battle)
	var sim := Scenarios.start_battle(terrain, armies[GameConfig.Side.PLAYER],
		armies[GameConfig.Side.ENEMY], crop)
	var side_stacks: Array = battle["sides"]
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.behavior[side] = "attacker" if side_stacks[side] == battle["attacker"] else "defender"
	var human := player_stack(world, battle) != null and not ai_plays_player
	if human:
		sim.behavior[GameConfig.Side.PLAYER] = ""
	else:
		sim.started = true
	return sim

## Write a finished battle back to the campaign. Destroyed blocks cost a
## regiment of their role; a block that fled, routed, withdrew or held lives
## (Design §4: retreat costs position and supply, not regiments). Whoever
## holds the field wins; if nobody does, the defender kept its ground.
static func apply_result(world: World, sim: BattleSim, battle: Dictionary) -> Dictionary:
	# Not battle.get("sides", sides(...)): the default would be evaluated (and
	# stored) even when the battle already remembers its sides.
	var side_stacks: Array = battle["sides"] if battle.has("sides") else sides(world, battle)
	var lost := {}
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		var roles: Array[int] = []
		for row in sim.result.get("rows", []):
			if int(row["side"]) == side and str(row["fate"]) == "destroyed":
				roles.append(int(row["role"]))
		lost[side_stacks[side]] = roles
	var holder := int(sim.result.get("holder", -1))
	var winner: Stack = side_stacks[holder] if holder >= 0 else battle["defender"]
	return conclude(world, battle, winner, lost,
		"after %0.0fs (%s)" % [float(sim.result.get("seconds", 0.0)), str(sim.result.get("reason", ""))])

## The shared end of every battle, played or auto-resolved: regiments come off
## by role, empty stacks go, the loser falls back, one log line, and the
## battle leaves `pending_battles`.
static func conclude(world: World, battle: Dictionary, winner: Stack, lost: Dictionary, how: String) -> Dictionary:
	var loser := other(battle, winner)
	var by_nation := {}
	for s in lost:
		var n := 0
		for role in lost[s]:
			var i: int = s.regiments.rfind(role)
			if i >= 0:
				s.regiments.remove_at(i)
				n += 1
		by_nation[s.nation_id] = int(by_nation.get(s.nation_id, 0)) + n
	var site_name: String = world.graph.sites[battle["site_id"]].name
	var text := "Battle at %s %s: %s holds, %s falls back (losses %d / %d)" % [
		site_name, how, winner.label, loser.label,
		int(by_nation.get(winner.nation_id, 0)), int(by_nation.get(loser.nation_id, 0)),
	]
	var retreat_site := -1
	for s in [winner, loser]:
		if s.size() == 0 and world.stacks.has(s):
			world.remove_stack(s)
			text += "; %s is destroyed" % s.label
	if world.stacks.has(loser):
		retreat_site = retreat(world, loser, battle)
		if retreat_site < 0:
			text += "; %s had nowhere to go and is lost" % loser.label
	world.record(text)
	world.pending_battles.erase(battle)
	return {
		"winner": winner if world.stacks.has(winner) else null,
		"loser": loser,
		"lost": by_nation,
		"retreat_to": retreat_site,
		"text": text,
	}

## One hop out of the fight, or -1 (and the stack removed) when every way out
## is held by the enemy. See the Interfaces block for the order of preference.
static func retreat(world: World, s: Stack, battle: Dictionary) -> int:
	var site_id := int(battle["site_id"])
	var to := -1
	var back := int(battle.get("from_site", -1))
	if s == battle["attacker"] and back >= 0 and not world.hostile_presence(back, s.nation_id):
		to = back
	if to < 0:
		var nd := Pathing.nearest_depot(world, site_id, s.nation_id, false)
		if not nd.is_empty() and nd["sites"].size() > 0:
			var hop: int = nd["sites"][0]
			if not world.hostile_presence(hop, s.nation_id):
				to = hop
	if to < 0:
		var friendly := -1
		var any := -1
		for e in world.graph.edges:
			if e.a != site_id and e.b != site_id:
				continue
			var n := e.other(site_id)
			if world.hostile_presence(n, s.nation_id):
				continue
			if Holdings.is_friendly(world, world.graph.sites[n], s.nation_id) and (friendly < 0 or n < friendly):
				friendly = n
			if any < 0 or n < any:
				any = n
		to = friendly if friendly >= 0 else any
	if to < 0:
		world.remove_stack(s)
		return -1
	s.site_id = to
	s.retreat_to = to
	s.supply = maxf(0.0, s.supply - float(GameConfig.battle_bridge["retreat_supply_cost"]))
	Orders.clear(world, s)
	return to
