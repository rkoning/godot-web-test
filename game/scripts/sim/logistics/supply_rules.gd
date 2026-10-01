class_name SupplyRules
extends RefCounted

## Appendix B's supply arithmetic as pure functions: nothing here mutates the
## world, and every number comes from GameConfig.logistics. SupplyPhase applies
## them each turn, the AI's projection (WS-D) replays them along a candidate
## path, and the tooltip shows their breakdown, so all three agree by
## construction.

static func upkeep(regiments: int) -> float:
	var L := GameConfig.logistics
	var base: float = float(regiments) * float(L["upkeep_per_regiment"])
	if regiments > int(L["huge_stack"]):
		return base * float(L["huge_stack_upkeep"])
	if regiments > int(L["big_stack"]):
		return base * float(L["big_stack_upkeep"])
	return base

## True when a site feeds out of its own stock (a ready depot) rather than off
## the land. SupplyPhase drains the stock by what was eaten.
static func local_from_stock(world: World, site: Site) -> bool:
	return Holdings.depot_ready(world, site)

## What the ground feeds: up to the site's forage capacity, one regiment's
## upkeep each, never more than the regiments standing there eat. A depot
## feeds any number, from stock.
static func local_feed(world: World, site: Site, regiments: int) -> float:
	var per: float = float(GameConfig.logistics["upkeep_per_regiment"])
	var asked := float(regiments) * per
	if local_from_stock(world, site):
		return minf(asked, maxf(0.0, site.stock))
	var cap := Yields.forage_regiments(site, world.graph.region_of(site.id), world)
	return float(mini(cap, regiments)) * per

static func hop_loss(kind: int) -> float:
	var L := GameConfig.logistics
	match kind:
		Edge.Kind.RIVER: return float(L["hop_loss_river"])
		Edge.Kind.TRAIL: return float(L["hop_loss_trail"])
		Edge.Kind.MOUNTAIN: return float(L["hop_loss_mountain"])
	return float(L["hop_loss_road"])

## The fraction of a shipment that survives a chain of edges.
static func delivery_factor(edges: Array) -> float:
	var f := 1.0
	for e in edges:
		f *= 1.0 - hop_loss(e.kind)
	return f

static func delivered(requested: float, edges: Array) -> float:
	return requested * delivery_factor(edges)

static func level_delta(shortfall: float, regiments: int) -> float:
	var L := GameConfig.logistics
	if shortfall <= 0.0:
		return float(L["level_gain"])
	return -(shortfall / float(maxi(1, regiments))) * float(L["level_loss_per_shortfall"])

static func move_cost(kind: int) -> int:
	var L := GameConfig.logistics
	match kind:
		Edge.Kind.RIVER: return int(L["move_cost_river"])
		Edge.Kind.TRAIL: return int(L["move_cost_trail"])
		Edge.Kind.MOUNTAIN: return int(L["move_cost_mountain"])
	return int(L["move_cost_road"])

static func is_raider(stack: Stack) -> bool:
	return stack.size() > 0 and stack.size() <= int(GameConfig.logistics["raider_max_regiments"])

## Movement points this turn: big stacks are slow, raiders fast, the starving
## slower still.
static func move_points(stack: Stack) -> int:
	var L := GameConfig.logistics
	var pts := int(L["move_points"])
	if is_raider(stack):
		pts = int(L["raider_move_points"])
	elif stack.size() > int(L["huge_stack"]):
		pts = int(L["move_points_huge"])
	elif stack.size() > int(L["big_stack"]):
		pts = int(L["move_points_big"])
	if stack.supply < float(L["slow_below"]):
		pts = maxi(1, pts / 2)
	return pts

## The whole per-turn breakdown for one stack, without applying it. Appendix
## B's order: upkeep, local feed, depot feed, shortfall, level change. Keys are
## the tooltip's words; WS-D's projection replays this along a candidate path.
static func report(world: World, stack: Stack) -> Dictionary:
	var site := world.graph.site(stack.site_id)
	var n := stack.size()
	var up := upkeep(n)
	var from_stock := local_from_stock(world, site)
	var local := minf(up, local_feed(world, site, n))
	var request := maxf(0.0, up - local)
	var depot := {}
	var draw := 0.0
	var arrived := 0.0
	if request > 0.0:
		depot = Pathing.nearest_depot(world, stack.site_id, stack.nation_id, true)
		if not depot.is_empty():
			var ds: Site = world.graph.site(depot["site_id"])
			# Stock already eaten from underfoot is not on the shelf any more.
			var available: float = ds.stock - (local if from_stock and ds.id == site.id else 0.0)
			draw = minf(request, maxf(0.0, available))
			arrived = draw * float(depot["factor"])
			if draw <= 0.0:
				depot = {}
	var shortfall := up - local - arrived
	return {
		"upkeep": up,
		"local": local,
		"local_from_stock": from_stock,
		"foraging": Holdings.is_hostile_ground(world, site, stack.nation_id),
		"requested": request,
		"depot_draw": draw,
		"delivered": arrived,
		"depot_id": depot.get("site_id", -1),
		"hops": depot.get("hops", -1),
		"route": depot.get("sites", [] as Array[int]),
		"shortfall": shortfall,
		"delta": level_delta(shortfall, n),
	}
