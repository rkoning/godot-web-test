extends RefCounted

## WS-A: supply as a network. Rules first (pure functions, hand-checked
## numbers from Appendix B), then the phases that apply them.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_upkeep_is_superlinear()
	_test_hop_loss_and_delivery()
	_test_level_delta()
	_test_move_points()
	_test_holdings()
	_test_local_feed()
	# Later tasks append their tests here.
	_test_report_worked_example()
	_test_depots_refill_from_farms_in_reach()
	_test_one_farm_starves_four_farms_hold()
	_test_raider_on_the_road_raises_shortfall()
	_test_foraging_pillages()
	_test_desertion()
	_test_occupation()
	_test_orders()

# ------------------------------------------------------------------ fixtures

## A small two-nation map: a road from the home depot east into enemy land,
## a trail loop, one river edge, and four farms so a 12-stack can disperse.
##
##   Depot(0) -- Village(1) -- Crossroads(2) -- EnemyFarm(3) -- FoeVillage(6) -- FoeMarket(7) -- FourthFarm(8)
##                  \ trail      \ trail            \ river
##                  HomeFarm(4) --/                 FarFarm(5)
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
	w.graph.site(0).stock = 0.0        # tests set stock explicitly
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

# --------------------------------------------------------------------- rules

func _test_upkeep_is_superlinear() -> void:
	t.near("4 regiments eat 8", SupplyRules.upkeep(4), 8.0, 0.001)
	t.near("8 regiments eat 16 (the cap is exclusive)", SupplyRules.upkeep(8), 16.0, 0.001)
	t.near("9 regiments eat 27 (×1.5)", SupplyRules.upkeep(9), 27.0, 0.001)
	t.near("12 regiments eat 36", SupplyRules.upkeep(12), 36.0, 0.001)
	t.near("13 regiments eat 52 (×2)", SupplyRules.upkeep(13), 52.0, 0.001)

func _test_hop_loss_and_delivery() -> void:
	var w := _world()
	t.near("road loses 10%", SupplyRules.hop_loss(Edge.Kind.ROAD), 0.10, 0.0001)
	t.near("river loses 5%", SupplyRules.hop_loss(Edge.Kind.RIVER), 0.05, 0.0001)
	t.near("trail loses 20%", SupplyRules.hop_loss(Edge.Kind.TRAIL), 0.20, 0.0001)
	t.near("mountain loses 35%", SupplyRules.hop_loss(Edge.Kind.MOUNTAIN), 0.35, 0.0001)
	var roads: Array = [w.graph.edges[0], w.graph.edges[1], w.graph.edges[2]]
	t.near("three road hops deliver 72.9%", SupplyRules.delivery_factor(roads), 0.729, 0.0001)
	t.near("30 requested over three roads arrives as 21.87", SupplyRules.delivered(30.0, roads), 21.87, 0.001)
	t.near("no hops, no loss", SupplyRules.delivery_factor([]), 1.0, 0.0001)

func _test_level_delta() -> void:
	t.near("fed stacks gain 10", SupplyRules.level_delta(0.0, 12), 10.0, 0.001)
	t.near("a surplus is still +10", SupplyRules.level_delta(-5.0, 12), 10.0, 0.001)
	t.near("shortfall 8 on 12 regiments is −3.33", SupplyRules.level_delta(8.0, 12), -3.3333, 0.001)
	t.near("shortfall 1.6 on 6 regiments is −1.33", SupplyRules.level_delta(1.6, 6), -1.3333, 0.001)

func _test_move_points() -> void:
	var w := _world()
	var small := w.add_stack(0, 0, _inf(4))
	var raider := w.add_stack(0, 0, _inf(3))
	var big := w.add_stack(0, 0, _inf(9))
	var huge := w.add_stack(0, 0, _inf(13))
	t.check("4 regiments move 4", SupplyRules.move_points(small) == 4)
	t.check("3 regiments are a raider and move 5", SupplyRules.is_raider(raider) and SupplyRules.move_points(raider) == 5)
	t.check("9 regiments move 3", SupplyRules.move_points(big) == 3)
	t.check("13 regiments move 2", SupplyRules.move_points(huge) == 2)
	small.supply = 5.0
	t.check("below 10 supply movement halves", SupplyRules.move_points(small) == 2)
	huge.supply = 5.0
	t.check("halving never drops below 1", SupplyRules.move_points(huge) == 1)
	t.check("road costs 1, trail 2, mountain 3, river 1",
		SupplyRules.move_cost(Edge.Kind.ROAD) == 1 and SupplyRules.move_cost(Edge.Kind.TRAIL) == 2
		and SupplyRules.move_cost(Edge.Kind.MOUNTAIN) == 3 and SupplyRules.move_cost(Edge.Kind.RIVER) == 1)

func _test_holdings() -> void:
	var w := _world()
	var farm := w.graph.site(3)
	t.check("an ungarrisoned site belongs to its region's owner", Holdings.site_owner(w, farm) == 1)
	t.check("enemy ground is hostile to us", Holdings.is_hostile_ground(w, farm, 0))
	t.check("and friendly to them", Holdings.is_friendly(w, farm, 1))
	farm.garrison_nation = 0
	t.check("a garrison overrides the region", Holdings.site_owner(w, farm) == 0 and Holdings.is_friendly(w, farm, 0))
	w.set_relation(0, 1, World.PEACE)
	farm.garrison_nation = -1
	t.check("at peace, their ground is not hostile ground", not Holdings.is_hostile_ground(w, farm, 0))
	var depot := w.graph.site(0)
	t.check("a depot with no build pending is ready", Holdings.depot_ready(w, depot))
	depot.depot_ready_turn = w.turn + 2
	t.check("a depot under construction is not", not Holdings.depot_ready(w, depot))
	t.check("a village is never a depot", not Holdings.depot_ready(w, w.graph.site(1)))

func _test_local_feed() -> void:
	var w := _world()
	t.near("a farm feeds three regiments' worth", SupplyRules.local_feed(w, w.graph.site(3), 12), 6.0, 0.001)
	t.near("but only what is standing there", SupplyRules.local_feed(w, w.graph.site(3), 2), 4.0, 0.001)
	t.near("a village feeds one", SupplyRules.local_feed(w, w.graph.site(1), 5), 2.0, 0.001)
	t.near("a feature feeds nobody", SupplyRules.local_feed(w, w.graph.site(2), 5), 0.0, 0.001)
	var depot := w.graph.site(0)
	depot.stock = 7.0
	t.near("a depot feeds from stock, up to the upkeep asked", SupplyRules.local_feed(w, depot, 12), 7.0, 0.001)
	t.near("and no more than the stack eats", SupplyRules.local_feed(w, depot, 2), 4.0, 0.001)
	t.check("depot feed is flagged as coming from stock", SupplyRules.local_from_stock(w, depot))
	t.check("farm feed is not", not SupplyRules.local_from_stock(w, w.graph.site(3)))

# Placeholders filled by Tasks 3–7. Keep them `pass` until then.
func _test_report_worked_example() -> void:
	var w := _world()
	w.graph.site(0).stock = 80.0
	var big := w.add_stack(0, 3, _inf(12))      # 12 regiments on the enemy farm, 3 road hops out
	var r := SupplyRules.report(w, big)
	t.near("upkeep 36", r["upkeep"], 36.0, 0.001)
	t.near("local 6 (the farm feeds three)", r["local"], 6.0, 0.001)
	t.check("it is foraging", r["foraging"])
	t.near("requests 30 from the depot", r["requested"], 30.0, 0.001)
	t.near("depot loses 30", r["depot_draw"], 30.0, 0.001)
	t.near("21.87 arrives", r["delivered"], 21.87, 0.01)
	t.check("three hops from depot 0", r["depot_id"] == 0 and r["hops"] == 3)
	t.near("shortfall 8.13", r["shortfall"], 8.13, 0.01)
	t.near("level falls 3.39", r["delta"], -3.39, 0.01)
	t.check("the report changed nothing", is_equal_approx(w.graph.site(0).stock, 80.0) and is_equal_approx(big.supply, 100.0))

	w.remove_stack(big)
	var a := w.add_stack(0, 3, _inf(6))
	var b := w.add_stack(0, 5, _inf(6))         # the river farm, 4 hops (river then three roads)
	var ra := SupplyRules.report(w, a)
	t.near("a 6-stack eats 12", ra["upkeep"], 12.0, 0.001)
	t.near("draws 6 from the depot", ra["depot_draw"], 6.0, 0.001)
	t.near("and falls only 1.36", ra["delta"], -1.355, 0.01)
	var rb := SupplyRules.report(w, b)
	t.near("the river farm's route loses a little more", rb["delivered"], 6.0 * 0.729 * 0.95, 0.01)

	# Standing on a depot: stock feeds directly, nothing double-counts.
	var home := w.add_stack(0, 0, _inf(4))
	w.graph.site(0).stock = 5.0
	var rh := SupplyRules.report(w, home)
	t.near("5 of the 8 comes from stock underfoot", rh["local"], 5.0, 0.001)
	t.check("flagged as from stock", rh["local_from_stock"])
	t.near("the rest cannot come from the same empty depot", rh["depot_draw"], 0.0, 0.001)
	t.near("shortfall 3", rh["shortfall"], 3.0, 0.001)
func _test_depots_refill_from_farms_in_reach() -> void:
	var w := _world()
	SupplyPhase.refill_depots(w)
	t.near("Home Farm (2 hops) feeds the depot 6", w.graph.site(0).stock, 6.0, 0.001)
	w.graph.site(0).stock = 118.0
	SupplyPhase.refill_depots(w)
	t.near("stock caps at the depot's capacity", w.graph.site(0).stock, 120.0, 0.001)
	w.graph.site(0).stock = 0.0
	w.graph.site(4).pillaged_until = w.turn + 2
	SupplyPhase.refill_depots(w)
	t.near("a pillaged farm yields nothing", w.graph.site(0).stock, 0.0, 0.001)
	# Enemy farms have no depot to send to; four hops is out of reach.
	var far := World.from_map(_map(), 1)
	far.graph.region(1).owner = 0                  # now all farms are ours, but Fourth Farm is 6 hops out
	far.graph.site(0).stock = 0.0
	SupplyPhase.refill_depots(far)
	t.near("only farms within reach count (Home 2, Enemy 3; Far 4 and Fourth 6 do not)", far.graph.site(0).stock, 12.0, 0.001)

func _test_one_farm_starves_four_farms_hold() -> void:
	var w := _world()                              # depot empty: nothing to lean on
	var doom := w.add_stack(0, 3, _inf(12))
	for i in 3:
		SupplyPhase.feed(w, doom)
	t.check("a 12-stack on one farm visibly starves: 100 → %d in three turns" % int(doom.supply), doom.supply < 70.0)
	t.near("its report says shortfall 30", doom.supply_report["shortfall"], 30.0, 0.001)

	var w2 := _world()
	var parts: Array[Stack] = []
	for site_id in [3, 4, 5, 8]:
		parts.append(w2.add_stack(0, site_id, _inf(3), 60.0))
	for i in 3:
		for p in parts:
			SupplyPhase.feed(w2, p)
	var all_up := true
	for p in parts:
		all_up = all_up and p.supply >= 90.0
	t.check("the same twelve split across four farms hold steady and recover", all_up)

func _test_raider_on_the_road_raises_shortfall() -> void:
	var w := _world()
	w.graph.site(0).stock = 80.0
	var army := w.add_stack(0, 2, _inf(6))         # on the crossroads, 2 road hops from the depot
	var before := SupplyRules.report(w, army)
	t.near("fed by the depot: shortfall 2.28", before["shortfall"], 12.0 - 12.0 * 0.81, 0.01)
	var raider := w.add_stack(1, 1, _cav(3))       # on the village between them
	var after := SupplyRules.report(w, army)
	t.near("the same turn the raider sits down the whole upkeep is short", after["shortfall"], 12.0, 0.001)
	t.check("and the edge shows severed", w.is_severed(w.graph.edge_between(1, 2), 0) and w.is_severed(w.graph.edge_between(0, 1), 0))
	w.remove_stack(raider)
	t.near("repair is free the moment it leaves", SupplyRules.report(w, army)["shortfall"], before["shortfall"], 0.001)

func _test_foraging_pillages() -> void:
	var w := _world()
	var coin_before: float = w.nation(0).coin
	var s := w.add_stack(0, 3, _inf(3))            # enemy farm
	SupplyPhase.feed(w, s)
	t.check("pillaging a farm kills two turns of yield", w.graph.site(3).pillaged_until == w.turn + 2)
	SupplyPhase.feed(w, s)
	t.check("and it accumulates", w.graph.site(3).pillaged_until == w.turn + 4)
	t.near("a farm pays no coin", w.nation(0).coin, coin_before, 0.001)
	s.site_id = 6
	SupplyPhase.feed(w, s)
	t.near("a village pays 2 coin once", w.nation(0).coin, coin_before + 2.0, 0.001)
	SupplyPhase.feed(w, s)
	t.near("not twice while it is still pillaged", w.nation(0).coin, coin_before + 2.0, 0.001)
	s.site_id = 7
	SupplyPhase.feed(w, s)
	t.near("a market pays 10", w.nation(0).coin, coin_before + 12.0, 0.001)
	t.check("and stays pillaged 3 turns", w.graph.site(7).pillaged_until == w.turn + 3)
	# Friendly ground is not pillaged.
	var home := w.add_stack(0, 4, _inf(2))
	SupplyPhase.feed(w, home)
	t.check("our own farm is untouched", w.graph.site(4).pillaged_until == 0 and not home.supply_report["foraging"])

func _test_desertion() -> void:
	var w := _world()
	var s := w.add_stack(0, 2, _inf(4), 20.0)      # the crossroads feeds nobody, no depot stock
	SupplyPhase.run(w)
	t.check("one turn under 30 loses nothing yet", s.size() == 4 and s.hunger == 1)
	SupplyPhase.run(w)
	t.check("the second turn costs a regiment", s.size() == 3 and s.hunger == 0)
	s.supply = 100.0
	s.hunger = 1
	w.graph.site(0).stock = 100.0
	s.site_id = 0
	SupplyPhase.run(w)
	t.check("being fed resets the count", s.hunger == 0 and s.size() == 3)
	var last := w.add_stack(0, 2, _inf(1), 0.0)
	for i in 2:
		SupplyPhase.run(w)
	t.check("a stack that loses its last regiment is removed", not w.stacks.has(last))
	# The warning line, once, on the way down.
	var w2 := _world()
	var s2 := w2.add_stack(0, 2, _inf(4), 55.0)
	SupplyPhase.run(w2)
	SupplyPhase.run(w2)
	var warned := 0
	for line in w2.events:
		if line.contains("short on supply"):
			warned += 1
	t.check("crossing 50 is logged once", warned == 1, str(w2.events))
	# Opening stock from the setup hook.
	var fresh := t.world()
	t.near("every depot opens the run with the configured stock", fresh.graph.site(1).stock, 60.0, 0.001)

func _test_occupation() -> void:
	var w := _world()
	var s := w.add_stack(0, 6, _inf(2))            # standing on Foe Village, no hold order
	OccupationPhase.run(w)
	t.check("passing through changes nothing", w.graph.region(1).owner == 1 and w.graph.site(6).garrison_nation == -1)
	s.order = "hold"
	OccupationPhase.run(w)
	t.check("a holding stack garrisons its site", w.graph.site(6).garrison_nation == 0)
	t.check("one of two is not a majority", w.graph.region(1).owner == 1)
	var m := w.add_stack(0, 7, _inf(1))
	m.order = "hold"
	OccupationPhase.run(w)
	t.check("village and market both held flips the region", w.graph.region(1).owner == 0)
	t.check("the flip is logged", w.events[w.events.size() - 1].contains("Foeland is now held by Home"))
	w.remove_stack(m)
	OccupationPhase.run(w)
	t.check("losing the majority does not flip it back on its own", w.graph.region(1).owner == 0)
	t.check("but the empty market is nobody's garrison", w.graph.site(7).garrison_nation == -1)
	s.path = [3] as Array[int]
	OccupationPhase.run(w)
	t.check("a holding stack with a route is marching, not garrisoning", w.graph.site(6).garrison_nation == -1)
func _test_orders() -> void:
	var w := _world()
	var s := w.add_stack(0, 0, _inf(12))
	t.check("move plans the road", Orders.move(w, s, 6) and s.path == ([1, 2, 3, 6] as Array[int]))
	s.order = "hold"
	Orders.move(w, s, 2)
	t.check("a move cancels a hold", s.order == "" and s.path == ([1, 2] as Array[int]))
	Orders.hold(w, s)
	t.check("hold clears the route", s.order == "hold" and s.path.is_empty())
	t.check("an unreachable order is refused", not Orders.move(w, s, 0) and s.order == "hold")
	# `hold` empties the route itself, so clearing after a hold would only ever
	# prove the posture was dropped. Post the posture by hand on a stack that
	# still has a route, so `clear` has both things to take back.
	Orders.move(w, s, 2)
	s.order = "hold"
	t.check("the fixture has a route and a posture for clear to take back",
		not s.path.is_empty() and s.order == "hold", "%s / '%s'" % [str(s.path), s.order])
	Orders.clear(w, s)
	t.check("clear takes back both the route and the posture",
		s.path.is_empty() and s.order == "", "%s / '%s'" % [str(s.path), s.order])

	var d := Orders.detach(w, s, 3, 4, true)
	t.check("detach makes a new stack of the last three", d != null and d.size() == 3 and s.size() == 9)
	t.check("it inherits supply, loses the leader, and walks to its site holding",
		is_equal_approx(d.supply, s.supply) and d.leader_id == -1 and is_equal_approx(d.quality, 0.5)
		and d.order == "hold" and d.path == ([1, 4] as Array[int]))
	t.check("detaching everything is refused", Orders.detach(w, s, 9, 4) == null and s.size() == 9)
	t.check("detaching nothing is refused", Orders.detach(w, s, 0, 4) == null)
	t.check("detachments are labelled", d.label.contains("detachment"))

	var n := w.nation(0)
	var cross := w.graph.site(2)
	t.check("Homeland already has a depot, so a second is refused",
		Orders.can_build_depot(w, n, cross).contains("already") and not Orders.build_depot(w, n, cross))
	t.check("enemy ground is refused", Orders.can_build_depot(w, n, w.graph.site(3)).contains("not yours"))
	# Take Foeland's market and village so it is ours, then build there.
	w.graph.region(1).owner = 0
	var far := w.graph.site(5)
	n.coin = 30.0
	t.check("too poor is refused", Orders.can_build_depot(w, n, far).contains("coin"))
	n.coin = 60.0
	t.check("a friendly farm can be built on", Orders.build_depot(w, n, far))
	t.check("it costs 40 and is a depot under construction", is_equal_approx(n.coin, 20.0)
		and far.kind == Site.Kind.DEPOT and far.depot_ready_turn == w.turn + 2 and not Holdings.depot_ready(w, far))
	t.check("a second in the same region is refused", Orders.can_build_depot(w, n, w.graph.site(8)).contains("already"))
	w.turn += 2
	t.check("two turns later it is ready", Holdings.depot_ready(w, far))
