class_name WorldGraph
extends RefCounted

## The site graph: the campaign map as data. Ids are array indices, checked at
## load, so lookups are O(1) and the AI can index arrays by id.

var sites: Array[Site] = []
var edges: Array[Edge] = []
var regions: Array[Region] = []
var _adj := {}                    # site id -> Array of Edge

## Every way a hand-authored map can be malformed, as human-readable lines
## naming the offending id. Ids are array indices everywhere in the simulation,
## so a map that breaks that assumption would fail much later as a wrong lookup
## rather than as a bad map — this is the one place to catch it.
##
## Returns an empty array for a clean map.
static func validate(data: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	var regions: Array = data.get("regions", [])
	var sites: Array = data.get("sites", [])
	var edges: Array = data.get("edges", [])

	for i in regions.size():
		var rid := int(regions[i].get("id", -1))
		if rid != i:
			problems.append("region %d: id is %d, but region ids must be 0..n-1 in order" % [i, rid])

	for i in sites.size():
		var sd: Dictionary = sites[i]
		var sid := int(sd.get("id", -1))
		if sid != i:
			problems.append("site %d: id is %d, but site ids must be 0..n-1 in order" % [i, sid])
		var reg := int(sd.get("region", -1))
		if reg < 0 or reg >= regions.size():
			problems.append("site %d: region %d is out of range 0..%d" % [i, reg, regions.size() - 1])

	var seen := {}
	for i in edges.size():
		var ed: Dictionary = edges[i]
		var a := int(ed.get("a", -1))
		var b := int(ed.get("b", -1))
		if a < 0 or a >= sites.size():
			problems.append("edge %d: endpoint %d is out of range 0..%d" % [i, a, sites.size() - 1])
		if b < 0 or b >= sites.size():
			problems.append("edge %d: endpoint %d is out of range 0..%d" % [i, b, sites.size() - 1])
		if a == b:
			problems.append("edge %d: joins site %d to itself" % [i, a])
			continue
		var key := "%d:%d" % [mini(a, b), maxi(a, b)]
		if seen.has(key):
			problems.append("edge %d: duplicates edge %d between sites %d and %d"
				% [i, int(seen[key]), mini(a, b), maxi(a, b)])
			continue
		seen[key] = i

	return problems

## A malformed map yields an empty graph, one `push_error` per problem, rather
## than a half-built one: a world with a silently missing region is harder to
## diagnose than a world with nothing in it. The asserts below stay for debug
## builds, where a map error should stop the editor on the offending line.
static func from_data(data: Dictionary) -> WorldGraph:
	var problems := validate(data)
	if not problems.is_empty():
		for p in problems:
			push_error("map data invalid: %s" % p)
		return WorldGraph.new()

	var g := WorldGraph.new()
	for rd in data["regions"]:
		var r := Region.new()
		r.id = int(rd["id"])
		assert(r.id == g.regions.size(), "region ids must be 0..n-1 in order")
		r.name = str(rd.get("name", "Region %d" % r.id))
		r.owner = int(rd.get("owner", -1))
		r.posture = Region.Posture[str(rd.get("posture", "economic")).to_upper()]
		g.regions.append(r)
	for sd in data["sites"]:
		var s := Site.from_dict(sd)
		assert(s.id == g.sites.size(), "site ids must be 0..n-1 in order")
		g.sites.append(s)
		g.regions[s.region_id].sites.append(s.id)
	for i in data["edges"].size():
		var e := Edge.from_dict(data["edges"][i], i)
		g.edges.append(e)
		g._adj.get_or_add(e.a, []).append(e)
		g._adj.get_or_add(e.b, []).append(e)
	return g

func site(id: int) -> Site:
	return sites[id]

func region(id: int) -> Region:
	return regions[id]

func region_of(site_id: int) -> Region:
	return regions[sites[site_id].region_id]

## The live adjacency array for a site — **read-only**. It is the graph's own
## storage, not a copy, so mutating it corrupts the graph; a caller that needs
## to filter or sort makes its own array. Returned by reference because pathing
## and supply walk it once per hop per turn.
func edges_of(site_id: int) -> Array:
	return _adj.get(site_id, [])

func neighbors(site_id: int) -> Array[int]:
	var out: Array[int] = []
	for e in edges_of(site_id):
		out.append(e.other(site_id))
	return out

func edge_between(a: int, b: int) -> Edge:
	if a == b:
		return null
	for e in edges_of(a):
		if e.other(a) == b:
			return e
	return null

func sites_in(region_id: int, kind := -1) -> Array[Site]:
	var out: Array[Site] = []
	for sid in regions[region_id].sites:
		if kind < 0 or sites[sid].kind == kind:
			out.append(sites[sid])
	return out
