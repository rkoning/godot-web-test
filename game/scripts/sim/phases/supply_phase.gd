class_name SupplyPhase
extends RefCounted

## WS-A. Depots fill from the farms that can reach them, then every stack eats
## in id order (so two stacks leaning on one depot always split it the same
## way), then hunger takes its toll.
##
## The three lines this phase writes are constants because they are read back:
## `LogisticsScenarios` decides won and lost by searching the log for them, so
## rewording one here without the other would quietly break a scenario. Anything
## that looks for these lines matches against these names.

const SHORT_ON_SUPPLY := "is short on supply"
const DESERTION := "lost a regiment to desertion"
const DISSOLVED := "dissolved"

static func run(world: World) -> void:
	refill_depots(world)
	var ordered: Array = world.stacks.duplicate()
	ordered.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	for s in ordered:
		feed(world, s)
	for s in ordered:
		if world.stacks.has(s):
			_starve(world, s)

## Each farm's yield goes to the nearest friendly, ready depot within reach
## (hops); a farm with none keeps its yield for foragers only.
static func refill_depots(world: World) -> void:
	var reach := int(GameConfig.logistics["depot_farm_reach"])
	for farm in world.graph.sites:
		if farm.kind != Site.Kind.FARM:
			continue
		var owner := Holdings.site_owner(world, farm)
		if owner < 0:
			continue
		var amount := Yields.supply(farm, world.graph.region_of(farm.id), world)
		if amount <= 0.0:
			continue
		var ex := Pathing.explore(world, farm.id, owner, Pathing.Cost.HOPS)
		var best: Site = null
		var best_d := INF
		for s in world.graph.sites:
			if not Holdings.is_friendly_depot(world, s, owner):
				continue
			var d: float = ex["dist"][s.id]
			if d <= float(reach) and d < best_d:
				best_d = d
				best = s
		if best != null:
			best.stock = minf(Yields.depot_capacity(best, world), best.stock + amount)

## Apply one stack's report: drain what it ate, pillage if it foraged hostile
## ground, move the level, and leave the breakdown on the stack for the UI.
static func feed(world: World, s: Stack) -> void:
	var r := SupplyRules.report(world, s)
	var site := world.graph.site(s.site_id)
	if r["local_from_stock"]:
		site.stock = maxf(0.0, site.stock - float(r["local"]))
	if int(r["depot_id"]) >= 0:
		var depot := world.graph.site(int(r["depot_id"]))
		depot.stock = maxf(0.0, depot.stock - float(r["depot_draw"]))
	if r["foraging"]:
		pillage(world, site, s.nation_id)
	var warn := float(GameConfig.logistics["supply_warning"])
	var before := s.supply
	s.supply = clampf(s.supply + float(r["delta"]), 0.0, 100.0)
	if before >= warn and s.supply < warn:
		world.record("%s %s (%d%%)" % [s.label, SHORT_ON_SUPPLY, int(round(s.supply))])
	s.supply_report = r

## Appendix B's pillage table. A site already pillaged pays no coin again but
## its ruin extends; a farm's ruin accumulates per turn stood on.
static func pillage(world: World, site: Site, by_nation: int) -> void:
	var L := GameConfig.logistics
	var fresh := world.turn >= site.pillaged_until
	var n := world.nation(by_nation)
	match site.kind:
		Site.Kind.FARM:
			site.pillaged_until = maxi(site.pillaged_until, world.turn) + int(L["pillage_farm_turns"])
		Site.Kind.VILLAGE:
			if fresh:
				n.coin += float(L["pillage_village_coin"])
				site.pillaged_until = world.turn + int(L["pillage_village_turns"])
		Site.Kind.MINE:
			if fresh:
				n.coin += float(L["pillage_mine_coin"])
				site.pillaged_until = world.turn + int(L["pillage_mine_turns"])
		Site.Kind.MARKET:
			if fresh:
				n.coin += float(L["pillage_market_coin"])
				site.pillaged_until = world.turn + int(L["pillage_market_turns"])
		Site.Kind.NODE:
			if fresh:
				site.pillaged_until = world.turn + int(L["pillage_node_turns"])
		# DEPOT: its stock is eaten through local feed; taking it is Occupation's business.
		# FEATURE: nothing to ruin.

## Under the desertion threshold a regiment walks away every `desertion_every`
## turns; being fed again resets the count.
static func _starve(world: World, s: Stack) -> void:
	var L := GameConfig.logistics
	if s.supply >= float(L["desertion_below"]):
		s.hunger = 0
		return
	s.hunger += 1
	if s.hunger < int(L["desertion_every"]):
		return
	s.hunger = 0
	if s.size() > 0:
		s.regiments.remove_at(s.size() - 1)
		world.record("%s %s" % [s.label, DESERTION])
	if s.size() == 0:
		world.record("%s %s" % [s.label, DISSOLVED])
		world.remove_stack(s)
