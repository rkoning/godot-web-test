class_name Holdings
extends RefCounted

## Who holds a site right now. The one place "friendly ground" is decided, so
## free feeding, foraging, pillage and depot access can never disagree.
##
## A garrison (a stack ordered to hold, see OccupationPhase) owns the site it
## stands on; otherwise the site belongs to whoever owns its region.

static func site_owner(world: World, site: Site) -> int:
	if site.garrison_nation >= 0:
		return site.garrison_nation
	return world.graph.region_of(site.id).owner

static func is_friendly(world: World, site: Site, nation_id: int) -> bool:
	return site_owner(world, site) == nation_id

## Owned by somebody we are at war with. Unowned or neutral ground is neither
## friendly nor hostile: it feeds an army for free and is not pillaged.
static func is_hostile_ground(world: World, site: Site, nation_id: int) -> bool:
	var owner := site_owner(world, site)
	return owner >= 0 and world.hostile(owner, nation_id)

static func depot_ready(world: World, site: Site) -> bool:
	return site.kind == Site.Kind.DEPOT and world.turn >= site.depot_ready_turn

static func is_friendly_depot(world: World, site: Site, nation_id: int) -> bool:
	return depot_ready(world, site) and is_friendly(world, site, nation_id)
