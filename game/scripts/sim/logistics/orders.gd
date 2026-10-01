class_name Orders
extends RefCounted

## Everything a player or an AI can tell an army to do. The only code that
## writes Stack.path and Stack.order, so the UI, the scripted enemies and WS-D's
## planner all go through one door.

static func move(world: World, s: Stack, to_site: int) -> bool:
	if to_site == s.site_id:
		return false
	var path := Pathing.shortest(world, s.site_id, to_site, s.nation_id)
	if path.is_empty():
		return false
	s.path = path
	s.order = ""
	return true

static func hold(world: World, s: Stack) -> void:
	s.path.clear()
	s.order = "hold"

## Take the order back: no route and no standing posture, so the army simply
## waits where it is. The UI's "Clear order" goes through here rather than
## writing `path` and `order` itself, so this file stays the only writer.
static func clear(world: World, s: Stack) -> void:
	s.path.clear()
	s.order = ""

## Split the last `n` regiments off as their own stack and send them to
## `to_site`. A detachment with no leader of its own fights at a discount;
## `then_hold` makes it garrison where it arrives.
static func detach(world: World, s: Stack, n: int, to_site: int, then_hold := false) -> Stack:
	if n < 1 or n >= s.size():
		return null
	var roster: Array = []
	for i in range(s.size() - n, s.size()):
		roster.append(s.regiments[i])
	var d := world.add_stack(s.nation_id, s.site_id, roster, s.supply)
	d.quality = s.quality * float(GameConfig.logistics["detach_quality"])
	d.leader_id = -1
	d.label = "%s detachment %d" % [world.nation(s.nation_id).name, d.id]
	if to_site != s.site_id and not move(world, d, to_site):
		world.remove_stack(d)
		return null
	s.regiments.resize(s.size() - n)
	if then_hold:
		d.order = "hold"
	world.record("%s detached %d regiments toward %s" % [s.label, n, world.graph.site(to_site).name])
	return d

## "" when a depot can go here, otherwise why not — the UI shows the reason.
static func can_build_depot(world: World, nation: Nation, site: Site) -> String:
	var L := GameConfig.logistics
	if not Holdings.is_friendly(world, site, nation.id):
		return "%s is not yours" % site.name
	if site.kind != Site.Kind.FARM and site.kind != Site.Kind.VILLAGE and site.kind != Site.Kind.FEATURE:
		return "a depot needs a farm, a village or open ground"
	for other in world.graph.sites_in(site.region_id, Site.Kind.DEPOT):
		return "%s already has a depot at %s" % [world.graph.region_of(site.id).name, other.name]
	if nation.coin < float(L["depot_cost"]):
		return "needs %d coin" % int(L["depot_cost"])
	return ""

static func build_depot(world: World, nation: Nation, site: Site) -> bool:
	if can_build_depot(world, nation, site) != "":
		return false
	var L := GameConfig.logistics
	nation.coin -= float(L["depot_cost"])
	site.kind = Site.Kind.DEPOT
	site.stock = 0.0
	site.depot_ready_turn = world.turn + int(L["depot_build_turns"])
	world.record("%s began a depot at %s" % [nation.name, site.name])
	return true
