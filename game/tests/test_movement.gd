extends RefCounted

## WS-A: how armies get from site to site, and the scripted enemies and
## scenarios that exercise it.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_road_beats_trail()
	_test_presence_blocks_the_interior()
	_test_nearest_depot()
	# Later tasks append here.
	_test_walk_and_stop()
	_test_merge()
	_test_marcher()
	_test_raider()
	_test_the_march_dumb_and_smart()
	_test_the_siege_is_winnable_without_a_fight()

## Same fixture as test_supply.gd; kept local so neither suite edits the other.
func _map() -> Dictionary:
	return {
		"nations": [
			{"id": 0, "name": "Home", "player": true, "coin": 60},
			{"id": 1, "name": "Foe", "player": false, "coin": 60},
		],
		"relations": [{"a": 0, "b": 1, "state": "war"}],
		"regions": [{"id": 0, "name": "Homeland", "owner": 0}, {"id": 1, "name": "Foeland", "owner": 1}],
		"sites": [
			{"id": 0, "region": 0, "kind": "depot", "pos": [100, 100], "name": "Depot"},
			{"id": 1, "region": 0, "kind": "village", "pos": [200, 100], "name": "Village"},
			{"id": 2, "region": 0, "kind": "feature", "pos": [300, 100], "name": "Crossroads"},
			{"id": 3, "region": 1, "kind": "farm", "pos": [400, 100], "name": "Enemy Farm"},
			{"id": 4, "region": 0, "kind": "farm", "pos": [200, 200], "name": "Home Farm"},
			{"id": 5, "region": 1, "kind": "farm", "pos": [400, 200], "name": "Far Farm"},
			{"id": 6, "region": 1, "kind": "village", "pos": [500, 100], "name": "Foe Village"},
			{"id": 7, "region": 1, "kind": "market", "pos": [500, 200], "name": "Foe Market"},
			{"id": 8, "region": 1, "kind": "farm", "pos": [600, 200], "name": "Fourth Farm"},
		],
		"edges": [
			{"a": 0, "b": 1}, {"a": 1, "b": 2}, {"a": 2, "b": 3},
			{"a": 1, "b": 4, "kind": "trail"}, {"a": 2, "b": 4, "kind": "trail"},
			{"a": 3, "b": 5, "kind": "river"}, {"a": 3, "b": 6}, {"a": 6, "b": 7}, {"a": 7, "b": 8},
		],
	}

func _world() -> World:
	var w := World.from_map(_map(), 1)
	w.graph.site(0).stock = 0.0
	return w

func _inf(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(GameConfig.Role.INFANTRY)
	return out

func _cav(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(GameConfig.Role.CAVALRY)
	return out

# ------------------------------------------------------------------- pathing

func _test_road_beats_trail() -> void:
	var w := _world()
	t.check("Home Farm to Depot goes by the village road, not the crossroads trail",
		Pathing.shortest(w, 4, 0, 0) == ([1, 0] as Array[int]), str(Pathing.shortest(w, 4, 0, 0)))
	t.check("Depot to Fourth Farm walks the whole road",
		Pathing.shortest(w, 0, 8, 0) == ([1, 2, 3, 6, 7, 8] as Array[int]))
	t.check("a site is no distance from itself", Pathing.shortest(w, 2, 2, 0).is_empty())
	var ex := Pathing.explore(w, 0, 0, Pathing.Cost.MOVEMENT)
	t.near("movement cost to Home Farm is 3 (road + trail)", ex["dist"][4], 3.0, 0.001)
	var hops := Pathing.explore(w, 0, 0, Pathing.Cost.HOPS)
	t.near("hops to Home Farm is 2", hops["dist"][4], 2.0, 0.001)

func _test_presence_blocks_the_interior() -> void:
	var w := _world()
	w.add_stack(1, 1, _cav(3))                # a raider on the Village
	t.check("with a raider on the village the depot is unreachable from the crossroads",
		Pathing.shortest(w, 2, 0, 0).is_empty())
	t.check("but the raider's own site can still be the destination (an attack)",
		Pathing.shortest(w, 2, 1, 0) == ([1] as Array[int]))
	t.check("the raider itself is not blocked by its own presence",
		Pathing.shortest(w, 1, 0, 1) == ([0] as Array[int]))
	w.set_relation(0, 1, World.PEACE)
	t.check("at peace, presence blocks nothing", Pathing.shortest(w, 2, 0, 0) == ([1, 0] as Array[int]))

func _test_nearest_depot() -> void:
	var w := _world()
	t.check("no stock, no depot", Pathing.nearest_depot(w, 3, 0).is_empty())
	t.check("unless stock is not required", Pathing.nearest_depot(w, 3, 0, false)["site_id"] == 0)
	w.graph.site(0).stock = 80.0
	var d := Pathing.nearest_depot(w, 3, 0)
	t.check("Enemy Farm's depot is three road hops away", d["site_id"] == 0 and d["hops"] == 3)
	t.near("and delivers 72.9%", d["factor"], 0.729, 0.0001)
	t.check("the route is listed from the army toward the depot", d["sites"] == ([2, 1, 0] as Array[int]))
	t.check("standing on the depot is zero hops at full delivery",
		Pathing.nearest_depot(w, 0, 0)["hops"] == 0 and is_equal_approx(Pathing.nearest_depot(w, 0, 0)["factor"], 1.0))
	t.check("the enemy has no depot at all", Pathing.nearest_depot(w, 3, 1, false).is_empty())
	w.graph.site(0).depot_ready_turn = w.turn + 1
	t.check("a depot under construction does not count", Pathing.nearest_depot(w, 3, 0).is_empty())

	# Presence severs at the shelves too: a depot with an enemy standing on it
	# ships nothing, however full it is and however clear the road.
	var besieged := _world()
	besieged.graph.site(0).stock = 80.0
	t.check("with the depot clear it feeds the farm", not Pathing.nearest_depot(besieged, 4, 0).is_empty())
	besieged.add_stack(1, 0, _cav(3))
	t.check("a besieged depot ships nothing", Pathing.nearest_depot(besieged, 4, 0).is_empty())
	t.check("and no planner can pretend otherwise",
		Pathing.nearest_depot(besieged, 4, 0, false).is_empty())

# --------------------------------------------------------------- movement

func _test_walk_and_stop() -> void:
	var w := _world()
	var s := w.add_stack(0, 0, _inf(4))
	s.path = [1, 2, 3, 6] as Array[int]
	Movement.walk(w, s)
	t.check("4 points walk 4 road edges", s.site_id == 6 and s.path.is_empty(), "at %d" % s.site_id)
	t.check("it moved this turn", s.moved_this_turn)

	var big := w.add_stack(0, 0, _inf(9))
	big.path = [1, 2, 3, 6] as Array[int]
	Movement.walk(w, big)
	t.check("9 regiments walk 3", big.site_id == 3 and big.path == ([6] as Array[int]))

	var trail := w.add_stack(0, 0, _inf(4))
	trail.path = [1, 4, 2] as Array[int]           # road 1 + trail 2 = 3, the next trail (2) does not fit
	Movement.walk(w, trail)
	t.check("a step it cannot afford waits for next turn", trail.site_id == 4 and trail.path == ([2] as Array[int]))

	var foe := w.add_stack(1, 3, _cav(2))
	var att := w.add_stack(0, 1, _inf(4))
	att.path = [2, 3, 6] as Array[int]
	Movement.walk(w, att)
	t.check("entering a hostile site ends the march there", att.site_id == 3 and att.path.is_empty())
	t.check("both stacks share the site for EngagementPhase", w.stacks_at(3).has(foe) and w.stacks_at(3).has(att))

	var stale := w.add_stack(0, 0, _inf(2))
	stale.path = [7] as Array[int]                  # not adjacent to the depot
	Movement.walk(w, stale)
	t.check("a stale route is dropped, not walked", stale.site_id == 0 and stale.path.is_empty())

	# Waiting only pays when next turn buys more, and it never does: a step past
	# the whole allowance is as dead an order as a route to nowhere.
	var thirteen := w.add_stack(0, 1, _inf(13))     # over huge_stack: 2 points
	thirteen.path = [4] as Array[int]               # the trail to Home Farm costs 2
	Movement.walk(w, thirteen)
	t.check("a thirteen just affords the trail", thirteen.site_id == 4 and thirteen.path.is_empty())

	var starving := w.add_stack(0, 1, _inf(13), 5.0)   # halved again under slow_below: 1 point
	starving.path = [4] as Array[int]
	Movement.walk(w, starving)
	t.check("a starving thirteen cannot, and the route goes rather than the turn",
		starving.site_id == 1 and starving.path.is_empty(), "at %d" % starving.site_id)
	t.check("and the log names the obstacle",
		w.events[w.events.size() - 1].contains("cannot cross the trail"),
		w.events[w.events.size() - 1])

	# What `walk` returns is where the attack came from, and the phase files it.
	var w2 := _world()
	var defender := w2.add_stack(1, 3, _cav(2))
	var march := w2.add_stack(0, 1, _inf(4))
	march.path = [2, 3, 6] as Array[int]
	MovementPhase.run(w2)
	t.check("a march stopped on the enemy leaves one pending battle",
		w2.pending_battles.size() == 1, str(w2.pending_battles.size()))
	if w2.pending_battles.size() == 1:
		var battle: Dictionary = w2.pending_battles[0]
		t.check("it names the attacker, the site and the side it came in from",
			battle["attacker"] == march and int(battle["site_id"]) == 3
				and int(battle["from_site"]) == 2, str(battle))
	t.check("the defender is still standing for WS-C to resolve against",
		w2.stacks.has(defender))

func _test_merge() -> void:
	var w := _world()
	var a := w.add_stack(0, 1, _inf(4), 100.0)
	var b := w.add_stack(0, 1, _cav(2), 40.0)
	var foe := w.add_stack(1, 1, _inf(1), 70.0)
	Movement.merge_all(w)
	t.check("friendly stacks on one site merge into the lower id", w.stacks_at(1).size() == 2 and w.stacks.has(a) and not w.stacks.has(b))
	t.check("regiments are pooled", a.size() == 6 and a.regiments.count(GameConfig.Role.CAVALRY) == 2)
	t.near("supply is the size-weighted mean", a.supply, 80.0, 0.001)
	t.check("the enemy on the same site is untouched", w.stacks.has(foe) and foe.size() == 1)

	var c := w.add_stack(0, 2, _inf(1))
	var d := w.add_stack(0, 2, _inf(1))
	d.hold_separate = true
	Movement.merge_all(w)
	t.check("hold_separate keeps a stack apart", w.stacks.has(c) and w.stacks.has(d))

	# The phase walks then merges, in id order, and only touches moved flags via the resolver.
	var w2 := _world()
	var x := w2.add_stack(0, 0, _inf(3))
	var y := w2.add_stack(0, 2, _inf(3))
	x.path = [1, 2] as Array[int]
	MovementPhase.run(w2)
	t.check("MovementPhase walks and then merges arrivals", w2.stacks.size() == 1 and w2.stacks[0] == x and x.size() == 6 and x.site_id == 2)
	t.check("y was folded into x", not w2.stacks.has(y))

# -------------------------------------------------------- the scripted enemies

func _test_marcher() -> void:
	var w := _world()
	w.nation(1).weights["scripted"] = "marcher"
	w.graph.site(0).stock = 100.0
	var m := w.add_stack(1, 8, _inf(12), 100.0)     # at Fourth Farm, the far end of the road
	ScriptedEnemy.issue_orders(w)
	t.check("the marcher heads for the player's depot", m.path == ([7, 6, 3, 2, 1, 0] as Array[int]))
	m.supply = 35.0
	ScriptedEnemy.issue_orders(w)
	t.check("under 40 it splits in two", m.size() == 6 and w.stacks_of(1).size() == 2)
	var half := w.stacks_of(1)[1]
	t.check("the half heads for a farm", half.size() == 6 and not half.path.is_empty()
		and w.graph.site(half.path[half.path.size() - 1]).kind == Site.Kind.FARM)
	var farm_route: Array[int] = half.path.duplicate()
	ScriptedEnemy.issue_orders(w)
	t.check("a six does not split again", w.stacks_of(1).size() == 2)
	t.check("and the foraging half keeps its farm route rather than being re-aimed",
		half.path == farm_route, str(half.path))
	# Blocked: a player stack on the only road makes it hold where it is.
	var block := w.add_stack(0, 3, _inf(8))
	ScriptedEnemy.issue_orders(w)
	t.check("with the road held it holds instead of walking into a wall", m.order == "hold" and m.path.is_empty())
	t.check("the block is still standing", w.stacks.has(block))

func _test_raider() -> void:
	var w := _world()
	w.nation(1).weights["scripted"] = "raider"
	w.graph.site(0).stock = 80.0
	var army := w.add_stack(0, 4, _inf(8))        # the player's largest, on Home Farm, 2 hops from the depot
	var r := w.add_stack(1, 8, _cav(3))
	ScriptedEnemy.issue_orders(w)
	t.check("the raider goes for the road between depot and army (the village)",
		not r.path.is_empty() and r.path[r.path.size() - 1] == 1, str(r.path))
	r.site_id = 2
	r.path.clear()
	army.site_id = 1                               # the army comes back to the village next door
	ScriptedEnemy.issue_orders(w)
	t.check("a big stack next door makes it flee", not r.path.is_empty() and r.path[0] != 1, str(r.path))
	t.check("raiders never hold", r.order == "")

# ------------------------------------------------------------- the scenarios

func _test_the_march_dumb_and_smart() -> void:
	var names: Array = []
	for s in LogisticsScenarios.all():
		names.append(s["name"])
	t.check("both Appendix B scenarios exist", names == ["The March", "The Siege"])

	# Dumb: cross the ford as one stack, hold both villages with it and a single detachment.
	var w := LogisticsScenarios.world(0)
	var me := w.stacks_of(0)[0]
	var east := _site(w, "Fording East")
	var reed := _site(w, "Reed Landing")
	Orders.move(w, me, east.id)
	TurnResolver.end_turn(w)
	TurnResolver.end_turn(w)
	t.check("two turns to cross with twelve", me.site_id == east.id)
	Orders.detach(w, me, 1, reed.id, true)
	Orders.hold(w, me)
	var lost := false
	var won_dumb := false
	for i in 9:
		TurnResolver.end_turn(w)
		var st := LogisticsScenarios.status(0, w)
		lost = lost or st["lost"]
		won_dumb = won_dumb or st["won"]
	t.check("holding River East as one hungry stack fails (%s)" % LogisticsScenarios.status(0, w)["text"], lost)
	t.check("and the hungry hold never counted as a win", not won_dumb)

	# Smart: one regiment per village, three on the farm, the rest back on a friendly farm.
	var w2 := LogisticsScenarios.world(0)
	var me2 := w2.stacks_of(0)[0]
	Orders.move(w2, me2, _site(w2, "Fording East").id)
	TurnResolver.end_turn(w2)
	TurnResolver.end_turn(w2)
	Orders.detach(w2, me2, 1, _site(w2, "Reed Landing").id, true)
	Orders.detach(w2, me2, 3, _site(w2, "East Bank Farm").id, true)
	Orders.detach(w2, me2, 1, _site(w2, "Fording East").id, true)   # same site: an order to hold here
	Orders.move(w2, me2, _site(w2, "West Bank Farm").id)
	var won := false
	for i in 14:
		TurnResolver.end_turn(w2)
		if me2.path.is_empty() and me2.order != "hold":
			Orders.hold(w2, me2)
		won = won or LogisticsScenarios.status(0, w2)["won"]
	t.check("dispersed to eat and garrisoned, River East is held for ten turns above 50 (%s)"
		% LogisticsScenarios.status(0, w2)["text"], won)

func _test_the_siege_is_winnable_without_a_fight() -> void:
	var w := LogisticsScenarios.world(1)
	var marcher := w.stacks_of(1)[0]
	t.check("the marcher sits on our frontier depot with fourteen", marcher.size() == 14
		and w.graph.site(marcher.site_id).name == "Riverwatch Depot")
	var me := w.stacks_of(0)[0]
	t.check("we have eight", me.size() == 8)
	# Turn 1: the last three of the roster — one infantry and both cavalry, a
	# raider by size — to Fordwatch, the marcher's only road home.
	var raider := Orders.detach(w, me, 3, _site(w, "Fordwatch").id, false)
	t.check("the raider is fast enough to get there this turn", raider != null and SupplyRules.move_points(raider) == 5)
	for i in 8:
		TurnResolver.end_turn(w)
	t.check("cut off, the marcher starves below 40 (%d%%)" % int(marcher.supply), marcher.supply < 40.0)
	t.check("it never got past the raider", w.graph.site(marcher.site_id).name == "Riverwatch Depot")
	t.check("our raider still stands", w.stacks.has(raider) and raider.size() == 3)
	t.check("the scenario reports the strangling as progress", LogisticsScenarios.status(1, w)["text"].contains("starving"))
	t.check("the scenario left the prototype map alone", PrototypeMap.data()["sites"][12]["kind"] == "village")

	# The win branch, which no playthrough above reaches: an empty field only
	# counts when hunger did the emptying, not when the enemy simply went home.
	var w2 := LogisticsScenarios.world(1)
	var gone := w2.stacks_of(1)[0]
	w2.remove_stack(gone)
	t.check("a marcher that walked home is not a victory",
		not LogisticsScenarios.status(1, w2)["won"], LogisticsScenarios.status(1, w2)["text"])
	w2.record("%s %s" % [gone.label, SupplyPhase.DESERTION])
	t.check("an empty field that hunger emptied is",
		LogisticsScenarios.status(1, w2)["won"], LogisticsScenarios.status(1, w2)["text"])

func _site(w: World, name: String) -> Site:
	for s in w.graph.sites:
		if s.name == name:
			return s
	t.check("site '%s' exists" % name, false)
	return w.graph.site(0)
