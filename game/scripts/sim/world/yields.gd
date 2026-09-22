class_name Yields
extends RefCounted

## Per-turn base yields by site kind. WS-F layers posture, culture and unrest
## on top by editing these functions; everyone else calls them and never
## reads GameConfig.sites directly.

static func supply(site: Site, _region: Region, world: World) -> float:
	if site.kind != Site.Kind.FARM or world.turn < site.pillaged_until:
		return 0.0
	return GameConfig.sites["farm_supply"]

static func coin(site: Site, _region: Region, world: World) -> float:
	if world.turn < site.pillaged_until:
		return 0.0
	match site.kind:
		Site.Kind.MINE: return GameConfig.sites["mine_coin"]
		Site.Kind.MARKET: return GameConfig.sites["market_coin"]
		Site.Kind.NODE: return GameConfig.sites["node_coin"]
	return 0.0

## How many regiments a site can feed off the land. The region and the world are
## in the signature though the base rule ignores them: WS-F's posture, culture
## and unrest all scale this, and a caller that had to find out whether they
## mattered would be reading the tables it is supposed to leave alone.
static func forage_regiments(site: Site, _region: Region, _world: World) -> int:
	match site.kind:
		Site.Kind.FARM: return GameConfig.sites["farm_forage_regiments"]
		Site.Kind.VILLAGE: return GameConfig.sites["village_forage_regiments"]
		Site.Kind.MARKET: return GameConfig.sites["market_forage_regiments"]
	return 0

## How much a depot can hold. The one place the capacity is read, so WS-A can
## make it depend on the site (a built-up depot) and WS-F on the region without
## every caller learning about it. The map's depot fill bar reads this too.
static func depot_capacity(_site: Site, _world: World) -> float:
	return GameConfig.sites["depot_max_stock"]
