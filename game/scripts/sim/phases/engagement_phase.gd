class_name EngagementPhase
extends RefCounted

## WS-C. Hostile stacks on one site fight. MovementPhase has already recorded
## every march that stopped on an enemy; this turns those, and any standoff
## left from an earlier turn, into battles — at most one per site per turn.

## AI against AI is the battle stub; the player's side trivially stronger is
## auto-resolved in the open; every other fight the player is in waits in
## `pending_battles` for BattleLayer to put on screen.
static func run(world: World) -> void:
	for s in world.stacks:
		s.retreat_to = -1
	var waiting: Array = []
	for battle in collect(world):
		var att: Stack = battle["attacker"]
		var def: Stack = battle["defender"]
		# An earlier resolution this turn may have moved or removed one of them.
		if not (world.stacks.has(att) and world.stacks.has(def)) or att.site_id != def.site_id:
			continue
		var mine := BattleBridge.player_stack(world, battle)
		if mine == null:
			AutoResolve.resolve(world, battle)
			continue
		var theirs := BattleBridge.other(battle, mine)
		battle["ratio"] = AutoResolve.ratio(mine, theirs)
		if AutoResolve.trivial(world, mine, theirs):
			AutoResolve.resolve(world, battle)
		else:
			waiting.append(battle)
	world.pending_battles = waiting

## This turn's battles, arrivals first in the order they happened, then
## standoffs (hostile stacks still sharing a site because the player did not
## fight last turn). A standoff is found again every turn until somebody leaves
## or somebody wins, so ending a turn never silently cancels a battle.
static func collect(world: World) -> Array:
	var out: Array = []
	var seen := {}
	for p in world.pending_battles:
		var site_id := int(p["site_id"])
		if seen.has(site_id):
			continue
		var b := _battle_at(world, site_id, p.get("attacker"), int(p.get("from_site", -1)))
		if not b.is_empty():
			out.append(b)
			seen[site_id] = true
	for s in _by_id(world.stacks):
		if seen.has(s.site_id) or not world.hostile_presence(s.site_id, s.nation_id):
			continue
		var b := _battle_at(world, s.site_id, null, -1)
		if not b.is_empty():
			out.append(b)
			seen[s.site_id] = true
	return out

static func _battle_at(world: World, site_id: int, arrived: Stack, from_site: int) -> Dictionary:
	var here := _by_id(world.stacks_at(site_id))
	var attacker: Stack = null
	var defender: Stack = null
	if arrived != null:
		# The marcher may have been folded into a friend by Movement.merge_all;
		# the survivor of that nation on this site carries its regiments.
		attacker = arrived if (world.stacks.has(arrived) and arrived.site_id == site_id) \
			else _first_of(here, arrived.nation_id)
		if attacker != null:
			defender = _first_hostile(world, here, attacker.nation_id)
	else:
		var owner := Holdings.site_owner(world, world.graph.sites[site_id])
		defender = _first_of(here, owner)
		if defender == null or _first_hostile(world, here, defender.nation_id) == null:
			defender = here[0] if here.size() > 0 else null
		if defender != null:
			attacker = _first_hostile(world, here, defender.nation_id)
	if attacker == null or defender == null:
		return {}
	if from_site < 0 or world.graph.edge_between(site_id, from_site) == null:
		from_site = _approach(world, site_id, attacker.nation_id)
	return {
		"attacker": attacker,
		"defender": defender,
		"site_id": site_id,
		"from_site": from_site,
	}

## A neighbour to come from when nobody recorded one: the first by id with no
## enemy of the attacker on it, else simply the first.
static func _approach(world: World, site_id: int, nation_id: int) -> int:
	var best := -1
	var fallback := -1
	for e in world.graph.edges:
		if e.a != site_id and e.b != site_id:
			continue
		var n := e.other(site_id)
		if fallback < 0 or n < fallback:
			fallback = n
		if not world.hostile_presence(n, nation_id) and (best < 0 or n < best):
			best = n
	return best if best >= 0 else fallback

static func _first_of(stacks: Array, nation_id: int) -> Stack:
	for s in stacks:
		if s.nation_id == nation_id:
			return s
	return null

static func _first_hostile(world: World, stacks: Array, nation_id: int) -> Stack:
	for s in stacks:
		if world.hostile(s.nation_id, nation_id):
			return s
	return null

static func _by_id(stacks: Array) -> Array:
	var out: Array = stacks.duplicate()
	out.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	return out
