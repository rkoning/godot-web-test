class_name Pathing
extends RefCounted

## Dijkstra over the site graph, in three currencies: movement points (what an
## order costs), hops (what a farm's reach is measured in), and supply loss
## (what a depot route is judged by). Deterministic: the graph is walked in id
## order.
##
## Presence severs, precisely:
##   * an **interior** site with hostile presence is never expanded — nothing
##     routes *through* an enemy army;
##   * the **start** site always is, so an army standing under an enemy is not
##     frozen by its own predicament;
##   * the **destination** may be hostile, which is how an attack is ordered —
##     but `nearest_depot` never draws from a depot with hostile presence,
##     because a besieged depot ships nothing.
##
## O(V²) with plain arrays: fine for 60 sites, and still under a millisecond
## for the 300 the full map will have. Revisit with a heap if WS-D's profiler
## says so, not before.

enum Cost { MOVEMENT, HOPS, SUPPLY }

static func edge_cost(e: Edge, mode: int) -> float:
	match mode:
		Cost.HOPS:
			return 1.0
		Cost.SUPPLY:
			return -log(1.0 - SupplyRules.hop_loss(e.kind))
	return float(SupplyRules.move_cost(e.kind))

## Distances and predecessors from `from` for `nation_id`, indexed by site id.
## Unreachable sites have INF distance and -1 predecessor.
static func explore(world: World, from: int, nation_id: int, mode: int) -> Dictionary:
	var n := world.graph.sites.size()
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var prev_site := PackedInt32Array()
	prev_site.resize(n)
	prev_site.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	done.fill(0)
	# One pass over the stacks instead of a `hostile_presence` scan per settled
	# node: the answer cannot change while a single Dijkstra runs, and the old
	# shape was O(V × stacks).
	var blocked := _blocked_sites(world, nation_id, n)
	dist[from] = 0.0
	while true:
		var u := -1
		var best := INF
		for i in n:
			if done[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0:
			break
		done[u] = 1
		# You can arrive at a hostile-held site, but nothing passes through it.
		if u != from and blocked[u] == 1:
			continue
		for e in world.graph.edges_of(u):
			var v: int = e.other(u)
			var d: float = best + edge_cost(e, mode)
			if d < dist[v]:
				dist[v] = d
				prev_site[v] = u
	return {"dist": dist, "prev_site": prev_site}

## Sites with a stack hostile to `nation_id` standing on them, as a flag per id.
static func _blocked_sites(world: World, nation_id: int, n: int) -> PackedByteArray:
	var blocked := PackedByteArray()
	blocked.resize(n)
	blocked.fill(0)
	for s in world.stacks:
		if s.site_id >= 0 and s.site_id < n and world.hostile(s.nation_id, nation_id):
			blocked[s.site_id] = 1
	return blocked

static func _walk_back(ex: Dictionary, from: int, to: int) -> Array[int]:
	var out: Array[int] = []
	var cur := to
	while cur != from and cur >= 0:
		out.push_front(cur)
		cur = ex["prev_site"][cur]
	return out

## The sites after `from`, ending at `to`. Empty when unreachable or already there.
static func shortest(world: World, from: int, to: int, nation_id: int, mode := Cost.MOVEMENT) -> Array[int]:
	if from == to:
		return [] as Array[int]
	var ex := explore(world, from, nation_id, mode)
	if ex["dist"][to] == INF:
		return [] as Array[int]
	return _walk_back(ex, from, to)

static func edges_along(world: World, from: int, sites: Array[int]) -> Array:
	var out: Array = []
	var cur := from
	for s in sites:
		out.append(world.graph.edge_between(cur, s))
		cur = s
	return out

## The friendly, ready depot that delivers the most of what it sends, and the
## route to it. {} when none is reachable. `with_stock` false is for planners
## asking "where would I be fed from" rather than "feed me now".
static func nearest_depot(world: World, from: int, nation_id: int, with_stock := true) -> Dictionary:
	var ex := explore(world, from, nation_id, Cost.SUPPLY)
	var best := -1
	var best_d := INF
	for s in world.graph.sites:
		if not Holdings.is_friendly_depot(world, s, nation_id):
			continue
		# A besieged depot ships nothing: the enemy is standing on the shelves.
		# Its own garrison still eats off it through `local_feed`, which asks the
		# site rather than this route.
		if world.hostile_presence(s.id, nation_id):
			continue
		if with_stock and s.stock <= 0.0:
			continue
		var d: float = ex["dist"][s.id]
		if d < best_d:
			best_d = d
			best = s.id
	if best < 0:
		return {}
	var sites := _walk_back(ex, from, best)
	var edges := edges_along(world, from, sites)
	return {
		"site_id": best,
		"hops": sites.size(),
		"sites": sites,
		"edges": edges,
		"factor": SupplyRules.delivery_factor(edges),
	}
