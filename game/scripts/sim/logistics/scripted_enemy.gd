class_name ScriptedEnemy
extends RefCounted

## Appendix B's two scripted enemies, until WS-D's real AI exists. A nation
## whose `weights` has "scripted": "marcher" | "raider" is driven here from
## MovementPhase. Both re-decide every turn from the visible world, through
## Orders and Pathing like everyone else.
##
## WS-D's `AiPhase` must skip every nation `is_scripted()` returns true for, or
## two planners will fight over the same stacks' orders in the same turn. Ask
## through that function rather than reading `weights["scripted"]` directly, so
## the key lives in one file.

## True when this nation is driven by this file rather than by a real planner.
static func is_scripted(nation: Nation) -> bool:
	return str(nation.weights.get("scripted", "")) != ""

static func issue_orders(world: World) -> void:
	for n in world.nations:
		if not is_scripted(n):
			continue
		var mode := str(n.weights.get("scripted", ""))
		var mine: Array = world.stacks_of(n.id).duplicate()
		mine.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
		for s in mine:
			if not world.stacks.has(s):
				continue
			match mode:
				"marcher":
					_marcher(world, s)
				"raider":
					_raider(world, s)

## One big stack follows the road toward the player's depot, foraging as it
## goes, and splits in two when it starts to starve.
static func _marcher(world: World, s: Stack) -> void:
	var L := GameConfig.logistics
	var player := world.player()
	if player == null:
		return
	# A detachment already walking to a farm keeps walking: re-planning every
	# turn would turn a foraging party round the moment the depot looked nearer,
	# and it would arrive nowhere and eat nothing. It re-decides once it lands.
	if not s.path.is_empty() and world.graph.site(s.path[s.path.size() - 1]).kind == Site.Kind.FARM:
		return
	if s.supply < float(L["marcher_split_below"]) and s.size() > int(L["big_stack"]):
		var farm := _nearest_site(world, s, Site.Kind.FARM, true)
		if farm >= 0:
			Orders.detach(world, s, s.size() / 2, farm)
	var target := _nearest_depot_of(world, s, player.id)
	if target < 0 or target == s.site_id or not Orders.move(world, s, target):
		Orders.hold(world, s)

## Three fast regiments sit on the road between the player's depot and their
## biggest army, and run from anything that could catch them.
static func _raider(world: World, s: Stack) -> void:
	var player := world.player()
	if player == null:
		return
	# Never "hold": a raider that garrisoned a village would occupy it.
	s.order = ""
	var threat := _threat_adjacent(world, s)
	var target := _escape(world, s) if threat >= 0 else _raid_target(world, player)
	if target < 0 or target == s.site_id or not Orders.move(world, s, target):
		# The one place this file writes a path directly. Nowhere to run, no road
		# worth cutting, or no route to it: stand still rather than walk last
		# turn's route into a site Pathing just refused us.
		s.path.clear()

static func _raid_target(world: World, player: Nation) -> int:
	var largest: Stack = null
	for st in world.stacks_of(player.id):
		if largest == null or st.size() > largest.size():
			largest = st
	if largest != null:
		var d := Pathing.nearest_depot(world, largest.site_id, player.id, false)
		if not d.is_empty() and int(d["hops"]) >= 2:
			return int(d["sites"][0])
	# No route to cut: the nearest player farm will do.
	var best := -1
	var best_d := INF
	for site in world.graph.sites:
		if site.kind == Site.Kind.FARM and Holdings.is_friendly(world, site, player.id):
			var dist: float = site.pos.distance_to(world.graph.site(largest.site_id).pos) if largest != null else 0.0
			if dist < best_d:
				best_d = dist
				best = site.id
	return best

## A hostile stack too big to be a raider on this site or the next.
static func _threat_adjacent(world: World, s: Stack) -> int:
	var raider_max := int(GameConfig.logistics["raider_max_regiments"])
	for other in world.stacks:
		if not world.hostile(other.nation_id, s.nation_id) or other.size() <= raider_max:
			continue
		if other.site_id == s.site_id or world.graph.edge_between(other.site_id, s.site_id) != null:
			return other.site_id
	return -1

## An adjacent site with nobody hostile on it and no big hostile stack next to it.
static func _escape(world: World, s: Stack) -> int:
	var raider_max := int(GameConfig.logistics["raider_max_regiments"])
	for nb in world.graph.neighbors(s.site_id):
		if world.hostile_presence(nb, s.nation_id):
			continue
		var safe := true
		for other in world.stacks:
			if world.hostile(other.nation_id, s.nation_id) and other.size() > raider_max \
					and (other.site_id == nb or world.graph.edge_between(other.site_id, nb) != null):
				safe = false
				break
		if safe:
			return nb
	return -1

static func _nearest_depot_of(world: World, s: Stack, nation_id: int) -> int:
	var ex := Pathing.explore(world, s.site_id, s.nation_id, Pathing.Cost.MOVEMENT)
	var best := -1
	var best_d := INF
	for site in world.graph.sites:
		if Holdings.is_friendly_depot(world, site, nation_id) and ex["dist"][site.id] < best_d:
			best_d = ex["dist"][site.id]
			best = site.id
	return best

## Nearest reachable site of a kind that is not hostile ground, other than here.
static func _nearest_site(world: World, s: Stack, kind: int, not_here: bool) -> int:
	var ex := Pathing.explore(world, s.site_id, s.nation_id, Pathing.Cost.MOVEMENT)
	var best := -1
	var best_d := INF
	for site in world.graph.sites:
		if site.kind != kind or (not_here and site.id == s.site_id):
			continue
		if Holdings.is_hostile_ground(world, site, s.nation_id) or world.hostile_presence(site.id, s.nation_id):
			continue
		if ex["dist"][site.id] < best_d:
			best_d = ex["dist"][site.id]
			best = site.id
	return best
