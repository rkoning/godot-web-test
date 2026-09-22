extends RefCounted

## Phase 0: the campaign world model. Every workstream builds on these shapes.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_graph_loads()
	_test_graph_queries()
	_test_graph_validation()
	_test_prototype_map_is_well_formed()
	_test_prototype_map_survives_one_loss()
	_test_world_stacks_and_relations()
	_test_map_stacks_and_setup_hooks()
	_test_presence_severs()
	_test_turn_pipeline_runs_every_phase()
	_test_eras()
	_test_era_edges_fire()

func _test_graph_loads() -> void:
	var g := WorldGraph.from_data({
		"regions": [{"id": 0, "name": "Home", "owner": 0}, {"id": 1, "name": "Away", "owner": 1, "posture": "military"}],
		"sites": [
			{"id": 0, "region": 0, "kind": "farm", "pos": [100, 100]},
			{"id": 1, "region": 0, "kind": "depot", "pos": [140, 100]},
			{"id": 2, "region": 1, "kind": "node", "pos": [200, 100], "tag": "iron"},
		],
		"edges": [{"a": 0, "b": 1}, {"a": 1, "b": 2, "kind": "trail"}],
	})
	t.check("two regions", g.regions.size() == 2)
	t.check("three sites", g.sites.size() == 3)
	t.check("site kind parsed", g.site(0).kind == Site.Kind.FARM)
	t.check("node tag parsed", g.site(2).node_tag == "iron")
	t.check("posture parsed", g.region(1).posture == Region.Posture.MILITARY)
	t.check("default posture economic", g.region(0).posture == Region.Posture.ECONOMIC)
	t.check("edge kind parsed", g.edges[1].kind == Edge.Kind.TRAIL)
	t.check("default edge kind road", g.edges[0].kind == Edge.Kind.ROAD)
	t.check("region lists its sites", g.region(0).sites == ([0, 1] as Array[int]))
	t.check("a region starts with no authored polygon", g.region(0).polygon.is_empty())

## PrototypeMap does not exist until Task 0.3, so this test builds its own
## inline fixture: two regions and five sites in a chain plus one branch, so
## neighbors/edge_between have both hits and misses and region 0 has both a
## FARM and a non-FARM site.
func _test_graph_queries() -> void:
	var g := WorldGraph.from_data({
		"regions": [{"id": 0, "name": "Home", "owner": 0}, {"id": 1, "name": "Away", "owner": 1}],
		"sites": [
			{"id": 0, "region": 0, "kind": "farm", "pos": [0, 0]},
			{"id": 1, "region": 0, "kind": "depot", "pos": [40, 0]},
			{"id": 2, "region": 0, "kind": "village", "pos": [80, 0]},
			{"id": 3, "region": 1, "kind": "market", "pos": [120, 0]},
			{"id": 4, "region": 1, "kind": "mine", "pos": [80, 40]},
		],
		"edges": [
			{"a": 0, "b": 1},
			{"a": 1, "b": 2},
			{"a": 2, "b": 3},
			{"a": 2, "b": 4},
		],
	})
	var s := g.site(0)
	t.check("region_of", g.region_of(0).id == s.region_id)
	t.check("neighbors are symmetric",
		g.neighbors(g.neighbors(0)[0]).has(0))
	var n: int = g.neighbors(0)[0]
	t.check("edge_between finds the edge", g.edge_between(0, n) != null)
	t.check("edge_between is symmetric", g.edge_between(n, 0) == g.edge_between(0, n))
	t.check("edge_between misses", g.edge_between(0, 0) == null)
	t.check("sites_in filters by kind",
		g.sites_in(s.region_id, Site.Kind.FARM).all(func(x): return x.kind == Site.Kind.FARM))

# ------------------------------------------------------------------ validation

## A minimal well-formed map, broken one way at a time below. Ids are array
## indices everywhere in the simulation, so a map that breaks that assumption
## has to be rejected at load rather than mis-looked-up ten systems later.
func _valid_map() -> Dictionary:
	return {
		"regions": [{"id": 0, "name": "Home", "owner": 0}, {"id": 1, "name": "Away", "owner": 1}],
		"sites": [
			{"id": 0, "region": 0, "kind": "depot", "pos": [0, 0]},
			{"id": 1, "region": 0, "kind": "market", "pos": [40, 0]},
			{"id": 2, "region": 1, "kind": "farm", "pos": [80, 0]},
		],
		"edges": [{"a": 0, "b": 1}, {"a": 1, "b": 2}],
	}

## One problem class: `validate` must reject `data` with a message naming the
## offending id, so a map author is told which line to fix.
func _rejects(label: String, data: Dictionary, needle: String) -> void:
	var problems := WorldGraph.validate(data)
	var joined := " | ".join(problems)
	t.check("validate rejects %s" % label,
		not problems.is_empty() and joined.contains(needle), joined)

func _test_graph_validation() -> void:
	t.check("validate accepts a well-formed map", WorldGraph.validate(_valid_map()).is_empty(),
		" | ".join(WorldGraph.validate(_valid_map())))

	var out_of_order_region := _valid_map()
	out_of_order_region["regions"][1]["id"] = 5
	_rejects("a region id out of order", out_of_order_region, "5")

	var out_of_order_site := _valid_map()
	out_of_order_site["sites"][2]["id"] = 7
	_rejects("a site id out of order", out_of_order_site, "7")

	var bad_region := _valid_map()
	bad_region["sites"][2]["region"] = 9
	_rejects("a site in a region that does not exist", bad_region, "9")

	var bad_endpoint := _valid_map()
	bad_endpoint["edges"][1]["b"] = 9
	_rejects("an edge endpoint out of range", bad_endpoint, "9")

	var self_edge := _valid_map()
	self_edge["edges"][1] = {"a": 1, "b": 1}
	_rejects("an edge from a site to itself", self_edge, "1")

	var duplicate := _valid_map()
	duplicate["edges"].append({"a": 1, "b": 0})
	_rejects("a duplicate undirected edge", duplicate, "2")

	# A rejected map yields nothing rather than a half-built graph. This logs
	# one push_error per problem, which is the point: the console names the map.
	t.check("from_data returns an empty graph for a rejected map",
		WorldGraph.from_data(self_edge).sites.is_empty())

# --------------------------------------------------------------- prototype map

func _test_prototype_map_is_well_formed() -> void:
	var data := PrototypeMap.data()
	t.check("the prototype map validates clean", WorldGraph.validate(data).is_empty(),
		" | ".join(WorldGraph.validate(data)))
	var g := WorldGraph.from_data(data)
	var terrain := Terrain.new()
	t.check("12 regions", g.regions.size() == 12, str(g.regions.size()))
	var kinds := {}
	for r in g.regions:
		t.check("%s has 3–6 sites" % r.name, r.sites.size() >= 3 and r.sites.size() <= 6, str(r.sites.size()))
	for s in g.sites:
		kinds[s.kind] = true
		t.check("%s on land" % s.name, not terrain.is_blocked(s.pos, GameConfig.Role.INFANTRY) or s.kind == Site.Kind.FEATURE)
		t.check("%s is connected" % s.name, g.neighbors(s.id).size() > 0)
	for k in Site.Kind.values():
		t.check("map has a %s" % Site.Kind.keys()[k], kinds.has(k))
	var edge_kinds := {}
	for e in g.edges:
		edge_kinds[e.kind] = true
		t.check("edge %d joins distinct sites" % e.id, e.a != e.b)
	t.check("all four edge kinds used", edge_kinds.size() == 4)
	var owners := {}
	for r in g.regions:
		owners[r.owner] = true
	t.check("two nations own regions", owners.has(0) and owners.has(1))
	t.check("nations listed", data["nations"].size() == 2)

	# Edges are local: two sites a road joins are neighbours on the ground, so a
	# hop is a day's march rather than a teleport across the map. The longest
	# authored edge is Millbrook → Fordwatch at 326 units, hence the 340 bound.
	var longest := 0.0
	var longest_name := ""
	for e in g.edges:
		var d: float = g.site(e.a).pos.distance_to(g.site(e.b).pos)
		if d > longest:
			longest = d
			longest_name = "%s → %s" % [g.site(e.a).name, g.site(e.b).name]
	t.check("every edge joins geographic neighbours (< 340 units)", longest < 340.0,
		"%s is %.0f units" % [longest_name, longest])

	# The ford is the one crossing. Everything else about the map's shape can
	# change; this cannot, because the whole logistics prototype is built on
	# there being exactly one chokepoint between the two nations.
	var crossings: PackedStringArray = []
	for e in g.edges:
		var west_a: bool = g.site(e.a).pos.x < 560.0
		var west_b: bool = g.site(e.b).pos.x < 560.0
		if west_a != west_b:
			crossings.append("%s → %s" % [g.site(e.a).name, g.site(e.b).name])
	t.check("exactly one edge crosses x = 560", crossings.size() == 1, " | ".join(crossings))
	t.check("and it is the ford",
		crossings.size() == 1 and crossings[0].contains("The Ford"), " | ".join(crossings))

	# Both battle features are through-sites, not dead ends: an army can be
	# caught on the good ground rather than only choosing to sit on it.
	for feature_name in ["West Hill", "East Hill", "The Ford"]:
		var f := _named(g, feature_name)
		t.check("%s is a through-site" % feature_name,
			f != null and g.neighbors(f.id).size() >= 2,
			"degree %d" % (g.neighbors(f.id).size() if f != null else -1))

## Losing any one site — bar the ford, which is meant to be a chokepoint — must
## leave each nation able to supply itself: a raider taking a village reroutes a
## supply line, it does not end it.
##
## Two claims, and only the second one bites. Market-to-depot passes whatever
## the map looks like, because in both nations those two are joined by a direct
## edge; it is kept as a guard against a future map that separates them.
## **Depot-to-a-farm is the invariant the lateral edges buy** — it failed in
## exactly two ways before the depot laterals landed (losing Capital stranded
## Capital Depot, losing Warcamp Market stranded Warcamp Depot, each depot being
## a leaf), so it is what stops anyone deleting those edges again.
func _test_prototype_map_survives_one_loss() -> void:
	var g := WorldGraph.from_data(PrototypeMap.data())
	var ford := _named(g, "The Ford")
	t.check("the map has a ford", ford != null)
	if ford == null:
		return

	for nation in [0, 1]:
		var market := _nation_site(g, nation, Site.Kind.MARKET)
		var depot := _nation_site(g, nation, Site.Kind.DEPOT)
		t.check("nation %d has a market and a depot" % nation, market != null and depot != null)
		if market == null or depot == null:
			continue
		var broken: PackedStringArray = []
		for s in g.sites:
			if s.id == ford.id or s.id == market.id or s.id == depot.id:
				continue
			if not _reachable(g, market.id, s.id).has(depot.id):
				broken.append(s.name)
		t.check("nation %d keeps market and depot joined after losing any one site" % nation,
			broken.is_empty(), ", ".join(broken))

		# A depot with no route to a farm is a depot that cannot be refilled, so
		# this is the check with teeth. Removing the market is deliberately in
		# scope: that is the loss each depot's second road exists to survive.
		var farms: Array[int] = []
		for s in g.sites:
			if s.kind == Site.Kind.FARM and g.region_of(s.id).owner == nation:
				farms.append(s.id)
		t.check("nation %d owns at least one farm" % nation, not farms.is_empty())
		var starved: PackedStringArray = []
		for s in g.sites:
			if s.id == ford.id or s.id == depot.id:
				continue
			var seen := _reachable(g, depot.id, s.id)
			var fed := false
			for fid in farms:
				if fid != s.id and seen.has(fid):
					fed = true
					break
			if not fed:
				starved.append(s.name)
		t.check("nation %d keeps its depot in reach of one of its own farms after losing any one site" % nation,
			starved.is_empty(), ", ".join(starved))

	# The other half of the same claim: the ford really is the chokepoint.
	var empire := _nation_site(g, 0, Site.Kind.DEPOT)
	var warlord := _nation_site(g, 1, Site.Kind.DEPOT)
	t.check("the two nations are joined at all",
		empire != null and warlord != null and _reachable(g, empire.id, -1).has(warlord.id))
	t.check("losing the ford separates the two nations",
		empire != null and warlord != null
			and not _reachable(g, empire.id, ford.id).has(warlord.id))

func _named(g: WorldGraph, site_name: String) -> Site:
	for s in g.sites:
		if s.name == site_name:
			return s
	return null

func _nation_site(g: WorldGraph, nation: int, kind: int) -> Site:
	for s in g.sites:
		if s.kind == kind and g.region_of(s.id).owner == nation:
			return s
	return null

## Every site reachable from `from_id` with `removed` deleted from the graph.
func _reachable(g: WorldGraph, from_id: int, removed: int) -> Dictionary:
	var seen := {from_id: true}
	var queue: Array[int] = [from_id]
	while not queue.is_empty():
		var at: int = queue.pop_back()
		for n in g.neighbors(at):
			if n == removed or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen

# ------------------------------------------------------------- world and stacks

## `t.bare_world()` rather than `t.world()`: this test places its own stacks and
## would otherwise be counting the map's two field armies as well.
func _test_world_stacks_and_relations() -> void:
	var w := t.bare_world()
	t.check("player nation is 0", w.player().id == 0)
	t.check("nations loaded", w.nations.size() == 2)
	t.check("prototype nations at war", w.hostile(0, 1))
	t.check("war is a named constant", w.relation(0, 1) == World.WAR)
	t.check("a nation is not hostile to itself", not w.hostile(0, 0))
	t.check("an unset pair is at peace", w.relation(0, 0) == World.PEACE)
	w.set_relation(0, 1, World.PEACE)
	t.check("relations are symmetric", w.relation(1, 0) == World.PEACE)
	var s := w.add_stack(0, 1, [GameConfig.Role.INFANTRY, GameConfig.Role.INFANTRY, GameConfig.Role.CAVALRY])
	t.check("stack sized by roster", s.size() == 3)
	t.check("stack has a unique id", w.add_stack(0, 1, [GameConfig.Role.INFANTRY]).id != s.id)
	t.check("stacks_at", w.stacks_at(1).size() == 2)
	t.check("stacks_of", w.stacks_of(0).size() == 2 and w.stacks_of(1).is_empty())
	t.near("strength at full supply", s.strength(), 3.0, 0.001)
	s.supply = 0.0
	t.near("strength at zero supply is half", s.strength(), 1.5, 0.001)
	w.remove_stack(s)
	t.check("remove_stack", w.stacks_at(1).size() == 1)
	t.check("deterministic rng", t.world(7).rng.randi() == t.world(7).rng.randi())
	t.check("pending_battles is declared for WS-C", w.pending_battles.is_empty())
	t.check("provinces is declared for WS-M", w.provinces.is_empty())

## `from_map` is the one way a world is born: map data carries the starting
## armies, and `WorldSetup.hooks()` is where every workstream's run-start setup
## goes. Both are seams other workstreams build on, so both are tested here.
func _test_map_stacks_and_setup_hooks() -> void:
	var w := World.from_map(PrototypeMap.data(), 1)
	t.check("the map's two starting stacks are loaded", w.stacks.size() == 2, str(w.stacks.size()))
	var mine := w.stacks_of(0)
	var theirs := w.stacks_of(1)
	t.check("one stack each", mine.size() == 1 and theirs.size() == 1,
		"%d / %d" % [mine.size(), theirs.size()])
	if mine.size() != 1 or theirs.size() != 1:
		return
	t.check("the player stack is 12 regiments", mine[0].size() == 12, str(mine[0].size()))
	t.check("role names parsed into roles",
		mine[0].regiments.count(GameConfig.Role.INFANTRY) == 8
			and mine[0].regiments.count(GameConfig.Role.CAVALRY) == 2
			and mine[0].regiments.count(GameConfig.Role.ARCHERS) == 2,
		str(mine[0].regiments))
	t.check("the player stack stands on the site the map names",
		w.graph.site(mine[0].site_id).name == "Capital Depot",
		w.graph.site(mine[0].site_id).name)
	t.check("the enemy stack is 6 regiments", theirs[0].size() == 6, str(theirs[0].size()))
	t.check("the enemy stack stands on the site the map names",
		w.graph.site(theirs[0].site_id).name == "Warcamp Depot",
		w.graph.site(theirs[0].site_id).name)
	t.near("supply comes from map data", mine[0].supply, 100.0, 0.001)
	t.check("a map with no stacks array is still legal", t.bare_world().stacks.is_empty())

	# The run-start seam. `hooks()` is process-global mutable state shared by
	# every suite, so first name the leak if some earlier suite left one behind
	# — otherwise this test's counts would be wrong for a reason nothing says.
	t.check("no suite leaked a WorldSetup hook", WorldSetup.hooks().is_empty(),
		"%d hook(s) still registered" % WorldSetup.hooks().size())
	# Then append one, build a world, and erase it again.
	var calls: Array = []
	var hook := func(world: World) -> void:
		calls.append(world)
		world.era_listeners.append(func(_w: World, _era: int) -> void: pass)
	WorldSetup.hooks().append(hook)
	var hooked := World.from_map(PrototypeMap.data(), 1)
	WorldSetup.hooks().erase(hook)
	t.check("from_map calls every WorldSetup hook exactly once", calls.size() == 1, str(calls.size()))
	t.check("the hook is handed the finished world",
		calls.size() == 1 and calls[0] == hooked and hooked.stacks.size() == 2)
	t.check("a hook can register an era listener", hooked.era_listeners.size() == 1,
		str(hooked.era_listeners.size()))
	t.check("the test's hook is gone again", not WorldSetup.hooks().has(hook))
	t.check("and the registry is empty for the next suite", WorldSetup.hooks().is_empty(),
		"%d hook(s) still registered" % WorldSetup.hooks().size())

func _test_presence_severs() -> void:
	var w := t.bare_world()
	var e: Edge = w.graph.edges[0]
	t.check("no presence, not severed", not w.is_severed(e, 0))
	w.add_stack(1, e.a, [GameConfig.Role.CAVALRY])
	t.check("hostile stack on an endpoint severs it for the other nation", w.is_severed(e, 0))
	t.check("but not for its own nation", not w.is_severed(e, 1))
	w.set_relation(0, 1, World.PEACE)
	t.check("at peace, presence does not sever", not w.is_severed(e, 0))

# ------------------------------------------------------------- turns and eras

func _test_turn_pipeline_runs_every_phase() -> void:
	var w := t.world()
	var s := w.add_stack(0, 0, [GameConfig.Role.INFANTRY])
	s.moved_this_turn = true
	TurnResolver.end_turn(w)
	t.check("turn advanced", w.turn == 2)
	t.check("moved flag reset before phases", not s.moved_this_turn)
	t.check("phase list has twelve slots", TurnResolver.phases().size() == 12,
		str(TurnResolver.phases().size()))

	# Every slot is a live callable a fresh world survives. A phase file that was
	# renamed, or that stopped parsing, fails here rather than as a broken End
	# Turn in the shell — and no phase may advance the turn itself, which is
	# `end_turn`'s job alone.
	var fresh := t.world()
	var slots := TurnResolver.phases()
	for i in slots.size():
		var phase: Callable = slots[i]
		t.check("phase slot %d is a live callable" % i, phase.is_valid())
		phase.call(fresh)
	t.check("no phase advances the turn on its own", fresh.turn == 1, str(fresh.turn))

func _test_eras() -> void:
	t.check("turn 1 is era 1", World.era_of(1) == 1, str(World.era_of(1)))
	t.check("turn 24 is still era 1", World.era_of(24) == 1, str(World.era_of(24)))
	t.check("turn 25 opens era 2", World.era_of(25) == 2, str(World.era_of(25)))
	t.check("the last era does not roll over", World.era_of(73) == 3, str(World.era_of(73)))
	t.check("era() reads the world's own turn", t.world().era() == 1)

	# The tuning panel can drag any number to zero while the game is running.
	var per = GameConfig.run["turns_per_era"]
	GameConfig.run["turns_per_era"] = 0
	var safe := World.era_of(10)
	GameConfig.run["turns_per_era"] = per
	t.check("turns_per_era 0 does not divide by zero", safe >= 1, str(safe))
	t.check("turns_per_era restored for the rest of the suite",
		int(GameConfig.run["turns_per_era"]) == int(per), str(GameConfig.run["turns_per_era"]))

func _test_era_edges_fire() -> void:
	var w := t.world()
	var fired: Array = []
	w.era_listeners.append(func(_w: World, era: int): fired.append(era))
	for i in int(GameConfig.run["turns_per_era"]) - 1:
		TurnResolver.end_turn(w)
	t.check("no era edge before the boundary", fired.is_empty())
	TurnResolver.end_turn(w)
	t.check("era 2 announced on the boundary", fired == [2])
	t.check("world reports era 2", w.era() == 2)
