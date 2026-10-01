class_name OccupationPhase
extends RefCounted

## WS-A. Holding a region is splitting: it belongs to whoever garrisons most
## of its villages and its market town. A stack passing through changes
## nothing, and an empty region keeps its owner.
##
## A constant, because `LogisticsScenarios` dates The March's capture by finding
## this line in the log: rewording it here without there would break the
## scenario silently.

const NOW_HELD := "is now held by"

static func run(world: World) -> void:
	for site in world.graph.sites:
		site.garrison_nation = -1
	for s in world.stacks:
		if s.order == "hold" and s.path.is_empty() and s.size() > 0:
			world.graph.site(s.site_id).garrison_nation = s.nation_id
	for r in world.graph.regions:
		var total := 0
		var held := {}
		for sid in r.sites:
			var site := world.graph.site(sid)
			if site.kind != Site.Kind.VILLAGE and site.kind != Site.Kind.MARKET:
				continue
			total += 1
			if site.garrison_nation >= 0:
				held[site.garrison_nation] = int(held.get(site.garrison_nation, 0)) + 1
		for nation_id in held:
			if int(held[nation_id]) * 2 > total and r.owner != nation_id:
				r.owner = nation_id
				world.record("%s %s %s" % [r.name, NOW_HELD, world.nation(nation_id).name])
