extends RefCounted

## WS-C: stacks that meet on the campaign graph fight. Battle collection, the
## Stack <-> Army bridge, results and retreat, threshold auto-resolve and the
## AI battle stub, and the acceptance fight on East Hill.

const INF_ := GameConfig.Role.INFANTRY
const CAV := GameConfig.Role.CAVALRY
const ARC := GameConfig.Role.ARCHERS

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	_test_config()
	_test_collect_arrival()
	_test_collect_follows_a_merge()
	_test_collect_standoff()
	_test_sides()
	_test_fielded()
	_test_to_armies()
	_test_start()
	_test_hill_beats_plain()
	_test_losses_by_role()
	_test_loser_retreats_toward_depot()
	_test_retreat_to_resets_next_turn()
	_test_repulsed_attacker_goes_back()
	_test_surrounded_loser_is_lost()
	_test_wiped_out_stack_is_removed()
	_test_ratio_and_threshold()
	_test_hidden_failure_rate()
	_test_ai_battles_resolve_on_end_turn()
	_test_player_trivial_auto_resolves()
	_test_player_real_fight_waits()
	_test_valid()

# ------------------------------------------------------------------ helpers

func _site(w: World, site_name: String) -> int:
	for s in w.graph.sites:
		if s.name == site_name:
			return s.id
	t.check("fixture site '%s' exists" % site_name, false)
	return -1

func _roster(inf: int, cav: int, arc: int) -> Array:
	var r: Array = []
	for i in inf:
		r.append(INF_)
	for i in cav:
		r.append(CAV)
	for i in arc:
		r.append(ARC)
	return r

## Empire (0, the player) marches `att` onto Warlord's (1) `def` standing on
## `at`, from `from`, exactly as MovementPhase leaves it.
func _arrival(w: World, at: int, from: int, att: Array, def: Array) -> Dictionary:
	var d := w.add_stack(1, at, def)
	var a := w.add_stack(0, at, att)
	a.moved_this_turn = true
	w.pending_battles = [{"attacker": a, "site_id": at, "from_site": from}]
	return {"attacker": a, "defender": d}

# -------------------------------------------------------------------- tests

func _test_config() -> void:
	print("\nbattle bridge config")
	for key in ["max_blocks", "approach_distance", "auto_resolve_ratio", "hidden_failure_chance",
			"auto_attrition", "auto_loser_losses", "auto_supply_cost", "retreat_supply_cost"]:
		t.check("battle_bridge.%s is configured" % key, GameConfig.battle_bridge.has(key))
	t.check("a stack starts with no retreat", Stack.new().retreat_to == -1)

func _test_collect_arrival() -> void:
	print("\nengagement: an arrival is a battle")
	var w := t.bare_world()
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var s := _arrival(w, hill, watch, _roster(4, 0, 0), _roster(3, 0, 0))
	var battles := EngagementPhase.collect(w)
	t.check("one battle", battles.size() == 1, str(battles.size()))
	if battles.size() != 1:
		return
	var b: Dictionary = battles[0]
	t.check("the marcher attacks", b["attacker"] == s["attacker"])
	t.check("the stack standing there defends", b["defender"] == s["defender"])
	t.check("at the site", b["site_id"] == hill)
	t.check("coming from where it stepped in", b["from_site"] == watch)

func _test_collect_follows_a_merge() -> void:
	print("\nengagement: an attacker that merged is found by site and nation")
	var w := t.bare_world()
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	# A friend already on the site has the lowest id, so merge_all folds the
	# marcher into it and the pending entry points at a stack that is gone.
	var first := w.add_stack(0, hill, _roster(1, 0, 0))
	var s := _arrival(w, hill, watch, _roster(2, 0, 0), _roster(3, 0, 0))
	Movement.merge_all(w)
	t.check("fixture: the marcher was absorbed", not w.stacks.has(s["attacker"]))
	var battles := EngagementPhase.collect(w)
	t.check("still one battle", battles.size() == 1, str(battles.size()))
	if battles.size() != 1:
		return
	var att: Stack = battles[0]["attacker"]
	t.check("the attacker is the survivor", att == first)
	t.check("holding every attacking regiment", att.size() == 3, str(att.size()))

func _test_collect_standoff() -> void:
	print("\nengagement: a standoff left from an earlier turn is found again")
	var w := t.bare_world()
	var market := _site(w, "Warcamp Market")        # Warlord ground
	var d := w.add_stack(1, market, _roster(3, 0, 0))
	var a := w.add_stack(0, market, _roster(3, 0, 0))
	w.pending_battles = []
	var battles := EngagementPhase.collect(w)
	t.check("one battle with no arrival recorded", battles.size() == 1, str(battles.size()))
	if battles.size() != 1:
		return
	t.check("the owner of the ground defends", battles[0]["defender"] == d)
	t.check("the other side attacks", battles[0]["attacker"] == a)
	t.check("from a real neighbour", w.graph.edge_between(market, battles[0]["from_site"]) != null)
	var peace := t.bare_world()
	peace.set_relation(0, 1, World.PEACE)
	peace.add_stack(1, market, _roster(3, 0, 0))
	peace.add_stack(0, market, _roster(3, 0, 0))
	t.check("nations at peace share a site without a fight", EngagementPhase.collect(peace).is_empty())

func _test_sides() -> void:
	print("\nengagement: who is on the player's side of the field")
	var w := t.bare_world()
	var hill := _site(w, "East Hill")
	var s := _arrival(w, hill, _site(w, "Hilltop Watch"), _roster(4, 0, 0), _roster(3, 0, 0))
	var b: Dictionary = EngagementPhase.collect(w)[0]
	t.check("the player's stack is found", BattleBridge.player_stack(w, b) == s["attacker"])
	t.check("other() is the opponent", BattleBridge.other(b, s["attacker"]) == s["defender"])
	var sides := BattleBridge.sides(w, b)
	t.check("the player's stack takes Side.PLAYER", sides[GameConfig.Side.PLAYER] == s["attacker"])
	t.check("sides are remembered on the battle", b.get("sides") == sides)
	# AI vs AI: no player stack, the attacker takes Side.PLAYER.
	w.nation(0).is_player = false
	t.check("no player stack when the player is not in it", BattleBridge.player_stack(w, b) == null)
	t.check("the attacker takes Side.PLAYER in an AI fight",
		BattleBridge.sides(w, b)[GameConfig.Side.PLAYER] == s["attacker"])

func _test_fielded() -> void:
	print("\nbridge: at most max_blocks regiments take the field, mix kept")
	var w := t.bare_world()
	var s := w.add_stack(0, 0, _roster(8, 2, 2))
	var roles := BattleBridge.fielded(s)
	t.check("a 12-stack fields 8", roles.size() == 8, str(roles.size()))
	t.check("4 infantry", roles.count(INF_) == 4, str(roles))
	t.check("2 cavalry", roles.count(CAV) == 2, str(roles))
	t.check("2 archers", roles.count(ARC) == 2, str(roles))
	var small := w.add_stack(0, 0, _roster(2, 1, 0))
	t.check("a small stack fields everything", BattleBridge.fielded(small).size() == 3)

func _test_to_armies() -> void:
	print("\nbridge: stacks become armies on the site")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var s := _arrival(w, hill, watch, _roster(4, 0, 0), _roster(3, 0, 0))
	s["attacker"].supply = 60.0
	var b: Dictionary = EngagementPhase.collect(w)[0]
	var armies := BattleBridge.to_armies(w, terrain, b)
	var mine: Army = armies[GameConfig.Side.PLAYER]
	var theirs: Army = armies[GameConfig.Side.ENEMY]
	var site_pos: Vector2 = w.graph.sites[hill].pos
	var from_pos: Vector2 = w.graph.sites[watch].pos
	t.check("the defender stands on the site", theirs.pos.is_equal_approx(site_pos))
	t.near("the attacker is approach_distance away", mine.pos.distance_to(site_pos),
		float(GameConfig.battle_bridge["approach_distance"]), 0.5)
	t.check("on the side it came from",
		(mine.pos - site_pos).dot(from_pos - site_pos) > 0.0)
	t.near("campaign supply 60 is battle supply 0.6", mine.supply, 0.6, 0.001)
	t.check("the attacker moved this turn", mine.moved_this_turn)
	t.check("the defender did not", not theirs.moved_this_turn)
	t.check("rosters are the fielded roles", mine.roster.size() == 4 and theirs.roster.size() == 3)

func _test_start() -> void:
	print("\nbridge: starting the battle")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	_arrival(w, hill, _site(w, "Hilltop Watch"), _roster(8, 2, 2), _roster(3, 0, 0))
	var b: Dictionary = EngagementPhase.collect(w)[0]
	var sim := BattleBridge.start(w, terrain, b)
	t.check("8 player blocks", sim.side_blocks(GameConfig.Side.PLAYER).size() == 8)
	t.check("3 enemy blocks", sim.side_blocks(GameConfig.Side.ENEMY).size() == 3)
	t.check("the human side has no AI", sim.behavior[GameConfig.Side.PLAYER] == "")
	t.check("the enemy defends", sim.behavior[GameConfig.Side.ENEMY] == "defender")
	t.check("the attacking player does not pre-arrange", sim.started and not sim.player_is_defender)
	var auto := BattleBridge.start(w, terrain, b, Vector2.ZERO, true)
	t.check("ai_plays_player gives the player's side the attacker AI",
		auto.behavior[GameConfig.Side.PLAYER] == "attacker")
	t.check("an AI-played battle starts at once", auto.started)
	# The player defending gets to arrange first, as in the prototype.
	var w2 := t.bare_world()
	var d := w2.add_stack(0, hill, _roster(3, 0, 0))
	var a := w2.add_stack(1, hill, _roster(3, 0, 0))
	a.moved_this_turn = true
	w2.pending_battles = [{"attacker": a, "site_id": hill, "from_site": _site(w2, "Hilltop Watch")}]
	var b2: Dictionary = EngagementPhase.collect(w2)[0]
	var sim2 := BattleBridge.start(w2, terrain, b2)
	t.check("a defending player arranges before the clock", sim2.player_is_defender and not sim2.started)
	t.check("the defending player is still Side.PLAYER", b2["sides"][GameConfig.Side.PLAYER] == d)

## Acceptance (Design §4 via WS-C): parking on the hill before a battle visibly
## changes the outcome, fought from the campaign graph. Same rosters, both
## sides played by the battle AI; the defender's trade (enemy health destroyed
## minus its own lost) on East Hill must beat the same fight on flat Southfield.
func _test_hill_beats_plain() -> void:
	print("\nacceptance: the hill changes the battle, from the campaign graph")
	var terrain := Terrain.new()
	var on_hill := _defender_trade(terrain, "East Hill", "Hilltop Watch")
	var on_flat := _defender_trade(terrain, "Southfield", "Warcamp Market")
	print("    East Hill: trade %+.0f   Southfield: trade %+.0f" % [on_hill, on_flat])
	t.check("holding East Hill beats holding flat ground against the same attack",
		on_hill > on_flat, "%.0f vs %.0f" % [on_hill, on_flat])

func _defender_trade(terrain: Terrain, at_name: String, from_name: String) -> float:
	var w := t.bare_world()
	var at := _site(w, at_name)
	var from := _site(w, from_name)
	_arrival(w, at, from, [INF_, INF_, ARC, CAV], [INF_, INF_, ARC, CAV])
	var b: Dictionary = EngagementPhase.collect(w)[0]
	var sim := BattleBridge.start(w, terrain, b, Vector2.ZERO, true)
	var guard := 0
	while not sim.finished and guard < 60 * 120:
		sim.step(TestHarness.DT)
		guard += 1
	var att_side := GameConfig.Side.PLAYER    # the Empire attacker holds Side.PLAYER
	var def_lost := 0.0
	var att_lost := 0.0
	for blk in sim.blocks:
		var lost: float = blk.max_health - maxf(0.0, blk.health)
		if blk.side == att_side:
			att_lost += lost
		else:
			def_lost += lost
	return att_lost - def_lost


## A started battle whose ending the test writes by hand: each block's fate is
## set, then the sim's own _finish() builds the result the view would show.
func _finished(w: World, terrain: Terrain, b: Dictionary, fates: Dictionary, holder_side: int) -> BattleSim:
	var sim := BattleBridge.start(w, terrain, b, Vector2.ZERO, true)
	for blk in sim.blocks:
		var key := "%d:%d" % [blk.side, blk.role]
		var list: Array = fates.get(key, [])
		if list.is_empty():
			continue
		match str(list.pop_front()):
			"destroyed":
				blk.health = 0.0
				blk.status = Block.Status.DESTROYED
			"fled":
				blk.status = Block.Status.FLED
			"routing":
				blk.routing = true
	# Everyone else steps back from the centre so the holder is the side the test names.
	for blk in sim.blocks:
		if blk.alive() and not blk.routing and blk.side != holder_side:
			blk.routing = true
	sim._finish("test")
	return sim

func _test_losses_by_role() -> void:
	print("\nresult: destroyed blocks cost regiments, everything else survives")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	var s := _arrival(w, hill, _site(w, "Hilltop Watch"), _roster(8, 2, 2), _roster(3, 1, 0))
	var b: Dictionary = EngagementPhase.collect(w)[0]
	w.pending_battles = [b]
	var P := GameConfig.Side.PLAYER
	var E := GameConfig.Side.ENEMY
	var sim := _finished(w, terrain, b, {
		"%d:%d" % [P, INF_]: ["destroyed", "fled"],
		"%d:%d" % [E, INF_]: ["destroyed", "destroyed"],
		"%d:%d" % [E, CAV]: ["routing"],
	}, P)
	var r := BattleBridge.apply_result(w, sim, b)
	var att: Stack = s["attacker"]
	var def: Stack = s["defender"]
	t.check("the player (holder) wins", r["winner"] == att)
	t.check("12 − 1 destroyed infantry = 11", att.size() == 11, str(att.size()))
	t.check("the fled infantry block survived", att.regiments.count(INF_) == 7, str(att.regiments))
	t.check("reserves untouched: cavalry and archers intact",
		att.regiments.count(CAV) == 2 and att.regiments.count(ARC) == 2)
	t.check("the enemy lost two infantry, kept its routed cavalry",
		def.regiments.count(INF_) == 1 and def.regiments.count(CAV) == 1, str(def.regiments))
	t.check("losses reported per nation", r["lost"].get(0, 0) == 1 and r["lost"].get(1, 0) == 2, str(r["lost"]))
	t.check("the battle is no longer pending", not w.pending_battles.has(b))
	t.check("it is in the log", w.events.size() > 0 and "East Hill" in w.events[w.events.size() - 1])

func _test_loser_retreats_toward_depot() -> void:
	print("\nresult: a beaten defender falls back one hop toward its depot")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	var s := _arrival(w, hill, _site(w, "Hilltop Watch"), _roster(4, 0, 0), _roster(3, 0, 0))
	var def: Stack = s["defender"]
	var before := def.supply
	var b: Dictionary = EngagementPhase.collect(w)[0]
	var r := BattleBridge.apply_result(w, _finished(w, terrain, b, {}, GameConfig.Side.PLAYER), b)
	var nd := Pathing.nearest_depot(w, hill, 1, false)
	t.check("the defender lost", r["loser"] == def)
	t.check("it left the site", def.site_id != hill)
	t.check("one hop, to a neighbour", w.graph.edge_between(hill, def.site_id) != null)
	t.check("not onto the enemy it fled", not w.hostile_presence(def.site_id, 1))
	t.check("retreat_to records it", def.retreat_to == def.site_id and r["retreat_to"] == def.site_id)
	t.near("retreat costs supply", def.supply, before - float(GameConfig.battle_bridge["retreat_supply_cost"]), 0.001)
	t.check("orders cleared", def.path.is_empty() and def.order == "")

func _test_retreat_to_resets_next_turn() -> void:
	print("\nresult: retreat_to is cleared again after the next End Turn")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	var s := _arrival(w, hill, _site(w, "Hilltop Watch"), _roster(4, 0, 0), _roster(3, 0, 0))
	var def: Stack = s["defender"]
	var b: Dictionary = EngagementPhase.collect(w)[0]
	BattleBridge.apply_result(w, _finished(w, terrain, b, {}, GameConfig.Side.PLAYER), b)
	t.check("fixture: it retreated this turn", def.retreat_to >= 0)
	TurnResolver.end_turn(w)
	t.check("retreat_to is -1 again after the next End Turn", def.retreat_to == -1)

func _test_repulsed_attacker_goes_back() -> void:
	print("\nresult: a repulsed attacker goes back the way it came")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var s := _arrival(w, hill, watch, _roster(3, 0, 0), _roster(4, 0, 0))
	var b: Dictionary = EngagementPhase.collect(w)[0]
	var r := BattleBridge.apply_result(w, _finished(w, terrain, b, {}, GameConfig.Side.ENEMY), b)
	t.check("the defender held", r["winner"] == s["defender"])
	t.check("the attacker is back where it stepped in from", s["attacker"].site_id == watch)

func _test_surrounded_loser_is_lost() -> void:
	print("\nresult: a loser with nowhere to go is lost")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	var s := _arrival(w, hill, _site(w, "Hilltop Watch"), _roster(4, 0, 0), _roster(3, 0, 0))
	# Empire stacks on both of East Hill's neighbours: Warlord cannot get out.
	for n in ["Hilltop Watch", "Warcamp Market"]:
		w.add_stack(0, _site(w, n), _roster(1, 0, 0))
	var b: Dictionary = EngagementPhase.collect(w)[0]
	var r := BattleBridge.apply_result(w, _finished(w, terrain, b, {}, GameConfig.Side.PLAYER), b)
	t.check("the surrounded stack is gone", not w.stacks.has(s["defender"]))
	t.check("retreat_to is -1", r["retreat_to"] == -1)

func _test_wiped_out_stack_is_removed() -> void:
	print("\nresult: a stack with no regiments left is removed")
	var w := t.bare_world()
	var terrain := Terrain.new()
	var hill := _site(w, "East Hill")
	var s := _arrival(w, hill, _site(w, "Hilltop Watch"), _roster(3, 0, 0), _roster(2, 0, 0))
	var b: Dictionary = EngagementPhase.collect(w)[0]
	var E := GameConfig.Side.ENEMY
	BattleBridge.apply_result(w, _finished(w, terrain, b,
		{"%d:%d" % [E, INF_]: ["destroyed", "destroyed"]}, GameConfig.Side.PLAYER), b)
	t.check("the wiped-out defender is removed", not w.stacks.has(s["defender"]))
	t.check("the winner stays on the site", s["attacker"].site_id == hill)

func _test_ratio_and_threshold() -> void:
	print("\nauto-resolve: the ratio and the threshold")
	var w := t.bare_world()
	var big := w.add_stack(0, 0, _roster(9, 0, 0))
	var small := w.add_stack(1, 0, _roster(3, 0, 0))
	t.near("9 vs 3 at full supply is 3.0", AutoResolve.ratio(big, small), 3.0, 0.001)
	t.check("3.0 is trivial", AutoResolve.trivial(w, big, small))
	big.supply = 50.0                                    # multiplier 0.75
	t.near("hunger shows in the ratio", AutoResolve.ratio(big, small), 2.25, 0.001)
	t.check("2.25 is a battle", not AutoResolve.trivial(w, big, small))

func _test_hidden_failure_rate() -> void:
	print("\nauto-resolve: a trivial fight rarely goes wrong, and replays identically")
	var w := t.bare_world(7)
	var big := w.add_stack(0, 0, _roster(12, 0, 0))
	var small := w.add_stack(1, 0, _roster(2, 0, 0))
	var n := 4000
	var upsets := 0
	for i in n:
		if AutoResolve.winner(w, big, small) == small:
			upsets += 1
	var rate := float(upsets) / float(n)
	t.near("upsets happen at hidden_failure_chance", rate,
		float(GameConfig.battle_bridge["hidden_failure_chance"]), 0.015)
	var a := t.bare_world(11)
	var b := t.bare_world(11)
	var sa := [a.add_stack(0, 0, _roster(4, 0, 0)), a.add_stack(1, 0, _roster(3, 0, 0))]
	var sb := [b.add_stack(0, 0, _roster(4, 0, 0)), b.add_stack(1, 0, _roster(3, 0, 0))]
	var same := true
	for i in 50:
		if (AutoResolve.winner(a, sa[0], sa[1]) == sa[0]) != (AutoResolve.winner(b, sb[0], sb[1]) == sb[0]):
			same = false
	t.check("same seed, same winners", same)

func _test_ai_battles_resolve_on_end_turn() -> void:
	print("\nengagement: two AI nations fight it out through the stub")
	var w := t.bare_world()
	w.nation(0).is_player = false
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var a := w.add_stack(0, watch, _roster(6, 0, 0))
	var d := w.add_stack(1, hill, _roster(2, 0, 0))
	Orders.move(w, a, hill)
	TurnResolver.end_turn(w)
	t.check("nothing is left pending", w.pending_battles.is_empty())
	t.check("nobody shares East Hill any more",
		not (w.stacks.has(a) and w.stacks.has(d) and a.site_id == d.site_id))
	var logged := false
	for e in w.events:
		if "Battle at East Hill" in e:
			logged = true
	t.check("the battle is in the log", logged)

func _test_player_trivial_auto_resolves() -> void:
	print("\nengagement: a trivial player fight resolves itself, ratio shown")
	var w := t.bare_world(3)
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var a := w.add_stack(0, watch, _roster(9, 0, 0))
	w.add_stack(1, hill, _roster(1, 0, 0))
	Orders.move(w, a, hill)
	TurnResolver.end_turn(w)
	t.check("no battle waits for the player", w.pending_battles.is_empty())
	var line := ""
	for e in w.events:
		if "auto-resolved at ratio" in e:
			line = e
	t.check("the log shows the ratio", line != "", str(w.events))

func _test_valid() -> void:
	print("\nbridge: valid() catches a battle SupplyPhase has pulled a stack out from under")
	var w := t.bare_world()
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var s := _arrival(w, hill, watch, _roster(4, 0, 0), _roster(3, 0, 0))
	var b: Dictionary = EngagementPhase.collect(w)[0]
	t.check("a fresh waiting battle is valid", BattleBridge.valid(w, b))
	var w2 := t.bare_world()
	var hill2 := _site(w2, "East Hill")
	var watch2 := _site(w2, "Hilltop Watch")
	var s2 := _arrival(w2, hill2, watch2, _roster(4, 0, 0), _roster(3, 0, 0))
	var b2: Dictionary = EngagementPhase.collect(w2)[0]
	w2.remove_stack(s2["defender"])
	t.check("invalid once the defender is removed", not BattleBridge.valid(w2, b2))
	var w3 := t.bare_world()
	var hill3 := _site(w3, "East Hill")
	var watch3 := _site(w3, "Hilltop Watch")
	var s3 := _arrival(w3, hill3, watch3, _roster(4, 0, 0), _roster(3, 0, 0))
	var b3: Dictionary = EngagementPhase.collect(w3)[0]
	s3["attacker"].site_id = watch3
	t.check("invalid once the attacker has moved off the site", not BattleBridge.valid(w3, b3))

func _test_player_real_fight_waits() -> void:
	print("\nengagement: a real fight waits for the player, and is offered again")
	var w := t.bare_world()
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var a := w.add_stack(0, watch, _roster(4, 0, 0))
	var d := w.add_stack(1, hill, _roster(3, 0, 0))
	Orders.move(w, a, hill)
	# EngagementPhase records the ratio before SupplyPhase (later in the same
	# End Turn) drains the two stacks unevenly, so the expectation is taken here.
	var expected_ratio := AutoResolve.ratio(a, d)
	TurnResolver.end_turn(w)
	t.check("one battle waits", w.pending_battles.size() == 1, str(w.pending_battles.size()))
	if w.pending_battles.size() != 1:
		return
	var b: Dictionary = w.pending_battles[0]
	t.near("its ratio is the player's over the enemy's", float(b["ratio"]),
		expected_ratio, 0.001)
	TurnResolver.end_turn(w)
	t.check("not fought: offered again next turn", w.pending_battles.size() == 1)
	Orders.move(w, a, watch)
	TurnResolver.end_turn(w)
	t.check("walking away ends it", w.pending_battles.is_empty())
