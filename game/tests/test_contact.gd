extends RefCounted

## Battle contact (spec 2026-09-23-battle-contact-design.md): turn rates,
## solid friends, locks and seating, pressure and push, walking away, the
## reform. Every check runs on probed ground: flat plain around (120, 90), the
## east slope of the big hill on y = 490, the river bank at x = 660 on y = 330.

const INF_ := GameConfig.Role.INFANTRY
const CAV := GameConfig.Role.CAVALRY
const P := GameConfig.Side.PLAYER
const E := GameConfig.Side.ENEMY

## Infantry marched at 20 u/s when the timing windows below were written; it
## marches at 14 now. Windows that only wait for a walk to finish are stretched
## by the ratio (scaled for the 2026-09-30 speed change).
const SLOWED := 20.0 / 14.0

var t: TestHarness
var terrain: Terrain

func run(harness: TestHarness) -> void:
	t = harness
	terrain = Terrain.new()
	_test_config()
	_test_shooting_range()
	_test_shoot_order()
	_test_turn_rate()
	_test_friends_are_solid()
	_test_routers_run_through_friends()
	_test_overlapping_friends_only_part()
	_test_front_contact_squares_up()
	_test_flank_hit_leaves_victim_facing()
	_test_locked_move_is_ignored()
	_test_withdraw_breaks_the_lock()
	_test_death_ends_the_lock()
	_test_two_front_locks_turn_once()
	_test_initiator_and_target_turn_once()
	_test_initiator_of_two_locks_slides_once()
	_test_even_fight_does_not_drift()
	_test_uphill_pushes_downhill()
	_test_river_stops_the_push()
	_test_winner_walks_away()
	_test_loser_of_two_locks_moves_once()
	_test_winner_in_two_locks_holds_both()
	_test_loser_not_pushed_into_even_partner()
	_test_reform_turns_to_the_flanker()
	_test_reform_is_not_restarted()
	_test_withdraw_cancels_reform()
	_test_no_reform_when_free()
	_test_ai_reforms_once()
	_test_ai_keeps_its_front_target()
	_test_ai_cavalry_sees_its_flank_charge_through()
	_test_reform_cancels_when_target_leaves()
	_test_rout_cancels_reform()
	_test_reform_halves_damage_dealt()
	_test_reforming_block_does_not_move()
	_test_routing_block_does_not_reform()
	_test_deep_enemies_can_part()
	_test_friends_swap_head_on()
	_test_marching_through_a_friend_is_slowed()
	_test_cavalry_charge_seats_flush()
	_test_reform_cancels_when_target_dies()
	_test_reform_cancels_when_target_routs()
	_test_losing_block_can_withdraw()
	_test_reforming_block_takes_flank_damage()
	_test_lock_is_not_duplicated()
	_test_march_does_not_stack_onto_a_fight()
	_test_march_passes_a_friend_near_an_enemy()
	_test_two_marchers_queued_behind_a_fight()

# ------------------------------------------------------------------ helpers

## A started battle on `field` with both sides player-controlled.
func _arena(field := Rect2(10, 10, 220, 160)) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(terrain, field)
	for side in [P, E]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[P] = Vector2.LEFT
	sim.home_dir[E] = Vector2.RIGHT
	sim.started = true
	# Idle sentinels in far corners so both sides have fielded a block from the
	# start: _check_end must never see an empty side as "collapsed" while a
	# test is still building up its own arena.
	sim.add_block(P, INF_, field.position + Vector2(8, 8), 0.0)
	sim.add_block(E, INF_, field.end - Vector2(8, 8), 0.0)
	return sim

func _run(sim: BattleSim, seconds: float) -> void:
	t.run_for(sim, seconds)

func _off(a: float, b: float) -> float:
	return absf(angle_difference(a, b))

## Make `b` hard to kill or break, so a test about geometry is not cut short
## by a rout or a death.
func _sturdy(b: Block) -> void:
	b.max_health = 1000.0
	b.health = 1000.0
	b.max_morale = 1000.0
	b.morale = 1000.0

# -------------------------------------------------------------------- tests

func _test_config() -> void:
	print("\ncontact config")
	for key in ["seat_speed", "push_per_dps", "push_max", "push_deadband", "push_smoothing",
			"pivot_angle", "reform_damage"]:
		t.check("combat.%s is configured" % key, GameConfig.combat.has(key))
	for role in GameConfig.units:
		t.check("%s has a turn_rate and reform_time" % GameConfig.units[role]["name"],
			GameConfig.units[role].has("turn_rate") and GameConfig.units[role].has("reform_time"))

func _test_turn_rate() -> void:
	print("\nturning: facing turns at a rate and a block pivots before it walks")
	var sim := _arena()
	var b := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	sim.order_move(b, Vector2(40, 90))                   # straight behind it
	_run(sim, 1.0)
	t.check("after 1 s it is still pivoting in place", b.pos.distance_to(Vector2(120, 90)) < 0.5,
		str(b.pos))
	t.near("infantry turns about 90Â° in 1 s", _off(0.0, b.facing), PI / 2.0, 0.1)
	_run(sim, 1.3)
	t.check("after ~2 s it faces the way it walks", _off(b.facing, PI) < 0.05, str(b.facing))
	t.check("and has started walking", b.pos.x < 118.0, str(b.pos))
	var cav := sim.add_block(E, CAV, Vector2(120, 140), 0.0)
	sim.order_move(cav, Vector2(40, 140))
	_run(sim, 1.0)
	t.check("cavalry turns 180Â° in about a second", _off(cav.facing, PI) < 0.1, str(cav.facing))

## Soft marching (user decision 2026-09-24): a block on a Move or a route walks
## through friends. Every other block is solid to them, so these walkers attack
## an enemy beyond instead of marching.
func _test_friends_are_solid() -> void:
	print("\nfriends are solid to a block that is not marching: no shoving, no overlapping")
	var sim := _arena()
	var wall := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var walker := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
	var beyond := sim.add_block(E, INF_, Vector2(200, 90), PI)
	sim.order_hold(beyond)
	sim.order_attack(walker, beyond)
	var overlapped := false
	for i in int(6.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		if walker.overlaps_deeply(wall):
			overlapped = true
	t.check("an attacker walking into a standing friend never overlaps it", not overlapped)
	t.check("and never shoves it", wall.pos.is_equal_approx(Vector2(120, 90)), str(wall.pos))
	# Two attackers making for the same face of one enemy really meet there.
	var sim2 := _arena()
	var a := sim2.add_block(P, INF_, Vector2(60, 72), 0.0)
	var b := sim2.add_block(P, INF_, Vector2(60, 108), 0.0)
	var foe := sim2.add_block(E, INF_, Vector2(170, 90), PI)
	_sturdy(foe)
	sim2.order_hold(foe)
	sim2.order_attack(a, foe)
	sim2.order_attack(b, foe)
	var met := false
	var closest := INF
	for i in int(8.0 / TestHarness.DT):
		sim2.step(TestHarness.DT)
		closest = minf(closest, a.pos.distance_to(b.pos))
		if a.overlaps_deeply(b):
			met = true
	t.check("fixture: the two attackers came within a frontage of each other", closest < a.frontage(),
		"%.1f" % closest)
	t.check("two attackers converging on one face never overlap", not met, "%s %s" % [a.pos, b.pos])

func _test_routers_run_through_friends() -> void:
	print("\na rout runs through its own side")
	var sim := _arena()
	sim.home_dir[P] = Vector2.RIGHT
	sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var r := sim.add_block(P, INF_, Vector2(70, 90), 0.0)
	r.routing = true
	r.morale = 0.0
	_run(sim, 4.0 * SLOWED)                     # scaled for the 2026-09-30 speed change
	t.check("the routing block got past the friend in its way", r.pos.x > 140.0, str(r.pos))

func _test_overlapping_friends_only_part() -> void:
	print("\nfriends already overlapping may part, never pass through")
	var sim := _arena()
	var a := sim.add_block(P, INF_, Vector2(110, 90), PI)    # faces away from b
	var b := sim.add_block(P, INF_, Vector2(116, 90), 0.0)
	t.check("they start overlapping", a.overlaps_deeply(b))
	sim.order_move(a, Vector2(40, 90))
	_run(sim, 3.0)
	t.check("the pair separated", not a.overlaps_deeply(b), str(a.pos))
	var sim2 := _arena()
	var c := sim2.add_block(P, INF_, Vector2(110, 90), 0.0)  # faces into d
	var d := sim2.add_block(P, INF_, Vector2(116, 90), 0.0)
	var beyond := sim2.add_block(E, INF_, Vector2(210, 90), PI)
	sim2.order_hold(beyond)
	var start := c.pos.distance_to(d.pos)
	sim2.order_attack(c, beyond)             # not marching, so d is solid to it
	var closest := start
	var passed := false
	for i in int(4.0 / TestHarness.DT):
		sim2.step(TestHarness.DT)
		closest = minf(closest, c.pos.distance_to(d.pos))
		if c.pos.x >= d.pos.x:
			passed = true
	t.check("a block never walks deeper into a friend it overlaps", closest >= start - 0.001,
		"%f < %f" % [closest, start])
	t.check("nor through it", not passed, str(c.pos))

## An infantry duel on flat ground: P attacks from the west, slightly off-line,
## E stands facing it. Returns [sim, attacker, target].
func _front_duel() -> Array:
	var sim := _arena()
	var target := sim.add_block(E, INF_, Vector2(140, 90), PI)
	var attacker := sim.add_block(P, INF_, Vector2(95, 80), 0.2)
	sim.order_attack(attacker, target)
	return [sim, attacker, target]

func _test_front_contact_squares_up() -> void:
	print("\nlock: a front-to-front contact squares both blocks up")
	var d := _front_duel()
	var sim: BattleSim = d[0]
	var a: Block = d[1]
	var e: Block = d[2]
	_run(sim, 4.0)
	t.check("they are locked", sim.locks_of(a).size() == 1 and sim.locks_of(e).size() == 1)
	if sim.locks_of(a).is_empty():
		return
	var lock: Contact = sim.locks_of(a)[0]
	t.check("the lock is front-to-front", lock.squares(), lock.face)
	t.check("they face each other exactly", _off(a.facing, e.facing + PI) < deg_to_rad(3.0),
		"%f vs %f" % [a.facing, e.facing])
	var axis := (e.pos - a.pos).normalized()
	t.check("along the line between them", _off(axis.angle(), a.facing) < deg_to_rad(3.0))
	t.near("flush: centres a depth apart", a.pos.distance_to(e.pos),
		(a.depth() + e.depth()) * 0.5, 1.5)
	t.check("pressure is recorded both ways",
		float(lock.pressure.get(a.id, 0.0)) > 1.0 and float(lock.pressure.get(e.id, 0.0)) > 1.0,
		str(lock.pressure))

func _test_flank_hit_leaves_victim_facing() -> void:
	print("\nlock: a flank hit moves only the attacker")
	var sim := _arena()
	var victim := sim.add_block(E, INF_, Vector2(140, 90), PI / 2.0)   # facing south
	var attacker := sim.add_block(P, INF_, Vector2(95, 95), 0.0)       # comes from the west
	sim.order_attack(attacker, victim)
	_run(sim, 4.0)
	t.check("locked", sim.locks_of(attacker).size() == 1)
	if sim.locks_of(attacker).is_empty():
		return
	var lock: Contact = sim.locks_of(attacker)[0]
	t.check("on a flank", lock.face == "left" or lock.face == "right", lock.face)
	t.check("the victim did not turn", is_equal_approx(victim.facing, PI / 2.0), str(victim.facing))
	var n := Contact.normal(victim, lock.face)
	t.check("the attacker faces into the struck face", _off(attacker.facing, (-n).angle()) < deg_to_rad(3.0))
	t.near("flush against it", (attacker.pos - victim.pos).dot(n),
		Contact.half_extent(victim, lock.face) + attacker.depth() * 0.5, 1.5)

func _test_locked_move_is_ignored() -> void:
	print("\nlock: an evenly matched block cannot just walk away")
	var d := _front_duel()
	var sim: BattleSim = d[0]
	var a: Block = d[1]
	_run(sim, 4.0)
	var at := a.pos
	sim.order_move(a, Vector2(30, 90))
	_run(sim, 1.5)
	t.check("still locked", not sim.locks_of(a).is_empty())
	t.check("and has not walked off", a.pos.distance_to(at) < 3.0, str(a.pos - at))

func _test_withdraw_breaks_the_lock() -> void:
	print("\nlock: Withdraw is the way out")
	var d := _front_duel()
	var sim: BattleSim = d[0]
	var a: Block = d[1]
	_run(sim, 4.0)
	var at := a.pos
	sim.order_withdraw(a)
	_run(sim, 5.0)
	t.check("the lock is gone", sim.locks_of(a).is_empty())
	t.check("and it pulled back", a.pos.x < at.x - 10.0, str(a.pos))

func _test_death_ends_the_lock() -> void:
	print("\nlock: a destroyed partner ends the lock")
	var d := _front_duel()
	var sim: BattleSim = d[0]
	var a: Block = d[1]
	var e: Block = d[2]
	_run(sim, 4.0)
	t.check("locked before", not sim.locks_of(a).is_empty())
	e.health = 0.0
	e.status = Block.Status.DESTROYED
	t.check("locks_of never returns a lock with a dead partner", sim.locks_of(a).is_empty())
	sim.step(TestHarness.DT)
	t.check("the lock is gone after a step", sim.locks_of(a).is_empty() and sim.locks.is_empty(),
		str(sim.locks.size()))

## Step `sim` for `seconds`; return the largest per-step turn of `b`.
func _worst_turn(sim: BattleSim, b: Block, seconds: float) -> float:
	var worst := 0.0
	for i in int(seconds / TestHarness.DT):
		var before := b.facing
		sim.step(TestHarness.DT)
		worst = maxf(worst, _off(before, b.facing))
	return worst

## One block struck frontally by two enemies arriving from the north-east and
## the south-east: it turns at its own rate, and its facing follows only its
## first front engagement rather than stalling between the two.
func _test_two_front_locks_turn_once() -> void:
	print("\nlock: a block in two front locks turns once per step")
	var sim := _arena()
	var lone := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var foes: Array[Block] = []
	for bearing in [-0.75, 0.75]:
		var at: Vector2 = Vector2(120, 90) + Vector2.RIGHT.rotated(bearing) * 40.0
		var foe := sim.add_block(E, INF_, at, bearing + PI)
		sim.order_attack(foe, lone)
		foes.append(foe)
	var limit := deg_to_rad(float(lone.stats()["turn_rate"])) * TestHarness.DT + 1e-4
	var worst := 0.0
	var both := false
	for i in int(4.0 / TestHarness.DT):
		var before := lone.facing
		sim.step(TestHarness.DT)
		worst = maxf(worst, _off(before, lone.facing))
		if sim.locks_of(lone).size() == 2 and sim.locks_of(lone).all(
				func(l: Contact) -> bool: return l.target == lone and l.squares()):
			both = true
	t.check("it was the target of two front locks at once", both)
	t.check("its facing never turned faster than its turn rate", worst <= limit,
		"%f > %f" % [worst, limit])
	var first: Block = sim.locks_of(lone)[0].other(lone) if not sim.locks_of(lone).is_empty() else foes[0]
	t.check("it ends up facing its first front engagement",
		_off(lone.facing, (first.pos - lone.pos).angle()) < deg_to_rad(3.0),
		"%f vs %f" % [lone.facing, (first.pos - lone.pos).angle()])

## A block that initiated one lock (on an enemy's rear) and is the target of a
## front lock, with the two headings on the same side of its facing: one turn
## per step, not one per lock.
func _test_initiator_and_target_turn_once() -> void:
	print("\nlock: a block that is initiator and target turns once per step")
	var sim := _arena()
	var lone := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var rear := sim.add_block(E, INF_, Vector2(131.5, 83), 0.15)     # its back to lone
	var front_at: Vector2 = Vector2(120, 90) + Vector2.RIGHT.rotated(0.7) * 14.0
	var striker := sim.add_block(E, INF_, front_at, 0.7 + PI)       # faces lone squarely
	sim.step(TestHarness.DT)
	var mine := _lock_with(sim, lone, rear)
	var theirs := _lock_with(sim, lone, striker)
	t.check("lone initiated a lock on the rear block", mine != null and mine.initiator == lone,
		"" if mine == null else mine.face)
	t.check("and is the target of a front lock", theirs != null and theirs.target == lone \
		and theirs.squares(), "" if theirs == null else theirs.face)
	var limit := deg_to_rad(float(lone.stats()["turn_rate"])) * TestHarness.DT + 1e-4
	var worst := _worst_turn(sim, lone, 1.0)
	t.check("its facing never turned faster than its turn rate", worst <= limit,
		"%f > %f" % [worst, limit])

## One block standing against two enemies side by side: it initiates both
## locks, and is still seated at no more than seat_speed.
func _test_initiator_of_two_locks_slides_once() -> void:
	print("\nlock: an initiator of two locks slides once per step")
	var sim := _arena()
	var a := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	sim.add_block(E, INF_, Vector2(132, 77), 0.0)
	sim.add_block(E, INF_, Vector2(132, 103), 0.0)
	var limit := float(GameConfig.combat["seat_speed"]) * TestHarness.DT + 1e-4
	var worst := 0.0
	var initiated := 0
	for i in int(1.0 / TestHarness.DT):
		var before := a.pos
		sim.step(TestHarness.DT)
		worst = maxf(worst, before.distance_to(a.pos))
		var n := 0
		for lock in sim.locks_of(a):
			if lock.initiator == a:
				n += 1
		initiated = maxi(initiated, n)
	t.check("it initiated two locks at once", initiated == 2, str(initiated))
	t.check("it never slid faster than seat_speed", worst <= limit, "%f > %f" % [worst, limit])

func _lock_with(sim: BattleSim, a: Block, b: Block) -> Contact:
	for lock in sim.locks_of(a):
		if lock.has(b):
			return lock
	return null

func _test_even_fight_does_not_drift() -> void:
	print("\npush: a mirror fight on flat ground stays put")
	var sim := _arena()
	var a := sim.add_block(P, INF_, Vector2(114, 90), 0.0)
	var b := sim.add_block(E, INF_, Vector2(126, 90), PI)
	sim.order_attack(a, b)
	sim.order_attack(b, a)
	_run(sim, 8.0)
	t.near("the fight's centre has not moved", (a.pos.x + b.pos.x) * 0.5, 120.0, 2.0)
	t.check("neither is pushing", sim.push_state(a) == 0 and sim.push_state(b) == 0)

## Uphill deals Ã1.25 and takes Ã0.75: 10 dps against 6, a 4 dps gap.
func _uphill_fight() -> Array:
	var sim := _arena(Rect2(860, 400, 180, 180))
	var up := sim.add_block(P, INF_, Vector2(944, 490), 0.0)      # higher, facing downhill
	var down := sim.add_block(E, INF_, Vector2(956, 490), PI)
	sim.order_attack(up, down)
	sim.order_attack(down, up)
	return [sim, up, down]

func _test_uphill_pushes_downhill() -> void:
	print("\npush: the block winning the trade pushes the other back")
	var f := _uphill_fight()
	var sim: BattleSim = f[0]
	var up: Block = f[1]
	var down: Block = f[2]
	_run(sim, 6.0)
	t.check("the downhill block gave ground", down.pos.x > 959.0, str(down.pos))
	t.check("the winner followed", up.pos.x > 946.0, str(up.pos))
	t.check("still locked", not sim.locks_of(up).is_empty())
	t.check("push_state reads it", sim.push_state(up) == 1 and sim.push_state(down) == -1)

func _test_river_stops_the_push() -> void:
	print("\npush: a loser with the river at its back cannot give ground")
	var sim := _arena(Rect2(560, 250, 200, 160))
	sim.supply[E] = 0.1
	var loser := sim.add_block(E, INF_, Vector2(667, 330), 0.0)   # back to the water at x 650
	var winner := sim.add_block(P, INF_, Vector2(679, 330), PI)
	sim.order_attack(winner, loser)
	sim.order_attack(loser, winner)
	_run(sim, 8.0)                   # a slow push (push_per_dps 0.45) reaches the bank well inside 8 s
	t.check("it is being pushed", sim.push_state(loser) == -1)
	t.check("and it gave ground toward the bank", loser.pos.x < 667.0 - 1.0, str(loser.pos))
	var at := loser.pos
	_run(sim, 1.0)
	t.check("it is not in the water", not terrain.is_blocked(loser.pos, INF_))
	t.check("and the push has stopped", loser.pos.distance_to(at) < 0.5, str(loser.pos - at))
	t.check("the fight goes on", not sim.locks_of(loser).is_empty())

func _test_winner_walks_away() -> void:
	print("\nwalking away: the winner may, the loser may not")
	var f := _uphill_fight()
	var sim: BattleSim = f[0]
	var up: Block = f[1]
	var down: Block = f[2]
	_run(sim, 3.0)
	sim.order_move(down, Vector2(1020, 490))
	_run(sim, 1.0)
	t.check("the loser's Move is ignored", not sim.locks_of(down).is_empty())
	var up_at := up.pos
	sim.order_move(up, Vector2(880, 490))
	_run(sim, 4.0)
	t.check("the winner's Move ends the lock", sim.locks_of(up).is_empty())
	t.check("and it walks off", up.pos.x < up_at.x - 5.0, str(up.pos))

## A block struck in the rear by two enemies side by side loses both locks:
## the two shoves (both southward) are summed, capped, and applied once per
## step, so it never gives ground faster than push_max, and each attacker, in
## only that one fight, follows it. (As a target it is never seated, so every
## step of ground it gives is the push.)
func _test_loser_of_two_locks_moves_once() -> void:
	print("\npush: a block losing two locks gives ground once per step")
	var sim := _arena()
	var lone := sim.add_block(E, INF_, Vector2(120, 90), PI / 2.0)   # facing south
	for dx in [-10.0, 10.0]:                                          # both on its back
		var foe := sim.add_block(P, INF_, Vector2(120 + dx, 78.5), PI / 2.0)
		sim.order_attack(foe, lone)
	var limit := float(GameConfig.combat["push_max"]) * TestHarness.DT + 1e-4
	var worst := 0.0
	var both := false
	var given := 0.0
	for i in int(4.0 / TestHarness.DT):
		var before := lone.pos
		sim.step(TestHarness.DT)
		var losing := 0
		for lock in sim.locks_of(lone):
			if lock.loser() == lone and lock.target == lone:
				losing += 1
		if losing == 2:
			both = true
			worst = maxf(worst, before.distance_to(lone.pos))
			given += lone.pos.y - before.y
	t.check("it was the losing target of two locks at once", both)
	t.check("it never gave ground faster than push_max", worst <= limit,
		"%f > %f" % [worst, limit])
	t.check("and it gave ground while losing both", given > 1.0, str(given))

## One block winning against two attackers on its front cannot follow both of
## them: it is in two locks. So neither loser gives ground (the fight grinds in
## place) and both locks hold, rather than the attackers drifting apart and the
## locks dropping and re-forming at zero pressure.
func _test_winner_in_two_locks_holds_both() -> void:
	print("\npush: a winner in two locks holds both; the losers grind in place")
	var sim := _arena()
	sim.supply[E] = 0.1
	var lone := sim.add_block(P, INF_, Vector2(120, 90), PI / 2.0)   # facing south
	_sturdy(lone)                    # outnumbered 2:1 it would rout on morale in ~4 s
	for x in [110.0, 130.0]:                                          # both on its front
		var foe := sim.add_block(E, INF_, Vector2(x, 101.5), -PI / 2.0)
		sim.order_attack(foe, lone)
	var waited := 0.0
	while waited < 6.0 and not (sim.locks_of(lone).size() == 2 and sim.push_state(lone) == 1):
		sim.step(TestHarness.DT)
		waited += TestHarness.DT
	t.check("it is winning two locks", sim.locks_of(lone).size() == 2 and sim.push_state(lone) == 1,
		"after %.2fs" % waited)
	var dropped := 0
	var not_winning := 0
	for i in int(3.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		if sim.locks_of(lone).size() != 2:
			dropped += 1
		if sim.push_state(lone) != 1:
			not_winning += 1
	t.check("both locks held on every step for 3 s", dropped == 0, "%d steps short" % dropped)
	t.check("and push_state stayed 1 throughout", not_winning == 0, "%d steps off" % not_winning)

## A loser with the winner on one side and an enemy it fights evenly on the
## other gives ground only if it will not walk into that enemy: the even
## partner is solid, only the winners (who follow) are ignored. The loser
## initiated both locks, so it is not re-seated and the even partner, a
## target, is not seated either. Pressures are forced each step.
func _test_loser_not_pushed_into_even_partner() -> void:
	print("\npush: a loser is not pushed into an enemy it fights evenly")
	var sim := _arena()
	var lose := sim.add_block(E, INF_, Vector2(120, 90), PI)          # facing west
	var win := sim.add_block(P, INF_, Vector2(102.5, 90), -PI / 2.0)  # west of it, facing north
	var even := sim.add_block(P, INF_, Vector2(131.8, 90), 0.0)       # east of it, facing away
	for b in [lose, win, even]:
		_sturdy(b)
	sim.step(TestHarness.DT)
	var lw := _lock_with(sim, lose, win)
	var le := _lock_with(sim, lose, even)
	t.check("the loser initiated both locks",
		lw != null and le != null and lw.initiator == lose and le.initiator == lose)
	if lw == null or le == null:
		return
	var deep := false
	for i in int(3.0 / TestHarness.DT):
		lw.pressure = {lose.id: 0.0, win.id: 20.0}
		le.pressure = {lose.id: 5.0, even.id: 5.0}
		sim.step(TestHarness.DT)
		if lose.overlaps_deeply(even):
			deep = true
	t.check("it never ends up deep in the even partner", not deep,
		"%s vs %s" % [lose.pos, even.pos])

## P holds facing east against E1 in front; E2 hits its north flank.
func _flanked() -> Array:
	var sim := _arena()
	var p := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	_sturdy(p)
	var front := sim.add_block(E, INF_, Vector2(145, 90), PI)
	var flank := sim.add_block(E, INF_, Vector2(120, 50), PI / 2.0)
	sim.order_hold(p)
	sim.order_attack(front, p)
	sim.order_attack(flank, p)
	_run(sim, 3.0)
	return [sim, p, front, flank]

func _test_reform_turns_to_the_flanker() -> void:
	print("\nreform: ordered to attack its flanker, a block turns after a delay")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	var front: Block = f[2]
	var flank: Block = f[3]
	t.check("fixture: the flanker is on a flank", sim.arc_of(p, flank.pos) == "flank")
	# Squared up to its front foe, P's facing is already a little off 0.
	var before := p.facing
	sim.order_attack(p, flank)
	t.check("it starts reforming", p.reforming())
	t.near("for its role's reform_time", p.reform_left, float(p.stats()["reform_time"]), 0.001)
	t.near("disordered: half damage", sim.damage_multiplier(p), float(GameConfig.combat["reform_damage"]), 0.001)
	_run(sim, 1.0)
	t.check("halfway through it has not turned yet", _off(p.facing, before) < 0.01, str(p.facing))
	t.check("and is still reforming", p.reforming())
	_run(sim, float(p.stats()["reform_time"]))
	t.check("the reform is over", not p.reforming())
	t.check("it faces the flanker", _off(p.facing, (flank.pos - p.pos).angle()) < deg_to_rad(5.0), str(p.facing))
	var lock := sim._lock_between(p, flank)
	t.check("that fight is now front to front", lock != null and lock.squares())
	t.check("and the old front foe is now on its flank", sim.arc_of(p, front.pos) != "front")
	t.near("full damage again", sim.damage_multiplier(p), 1.0, 0.001)

func _test_reform_is_not_restarted() -> void:
	print("\nreform: re-issuing the same Attack does not restart it")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	var flank: Block = f[3]
	sim.order_attack(p, flank)
	_run(sim, 0.8)
	var left := p.reform_left
	sim.order_attack(p, flank)
	t.check("the clock keeps running", is_equal_approx(p.reform_left, left))

func _test_withdraw_cancels_reform() -> void:
	print("\nreform: Withdraw cancels it")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	sim.order_attack(p, f[3])
	sim.order_withdraw(p)
	t.check("no longer reforming", not p.reforming())

func _test_no_reform_when_free() -> void:
	print("\nreform: a block that is not engaged just turns")
	var sim := _arena()
	var p := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var foe := sim.add_block(E, INF_, Vector2(40, 90), 0.0)
	sim.order_attack(p, foe)
	t.check("no reform", not p.reforming())

func _test_ai_reforms_once() -> void:
	print("\nreform: the battle AI re-issuing its order every 0.4 s does not restart it")
	var sim := _arena()
	var p := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	_sturdy(p)
	var flank := sim.add_block(E, INF_, Vector2(120, 50), PI / 2.0)
	sim.order_hold(p)
	sim.order_attack(flank, p)
	_run(sim, 3.0)
	# Hand P to the AI only once the flanker is in contact, so its first order
	# is the reform and every re-issue lands during it.
	sim.behavior[P] = "attacker"
	_run(sim, float(p.stats()["reform_time"]) + 0.6)
	t.check("it has turned to face its only enemy", _off(p.facing, (flank.pos - p.pos).angle()) < deg_to_rad(5.0),
		str(p.facing))
	t.check("and is fighting it, not still reforming", not p.reforming())

func _test_ai_keeps_its_front_target() -> void:
	print("\nreform: the battle AI reforms once, then keeps the foe in front of it")
	var sim := _arena()
	var p := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	_sturdy(p)
	var north := sim.add_block(E, INF_, Vector2(120, 50), PI / 2.0)
	var south := sim.add_block(E, INF_, Vector2(120, 130), -PI / 2.0)
	_sturdy(north)
	_sturdy(south)
	sim.order_hold(p)
	sim.order_attack(north, p)
	sim.order_attack(south, p)
	_run(sim, 3.0)
	t.check("fixture: both flankers touch it", sim.contacts_of(p).has(north) and sim.contacts_of(p).has(south))
	sim.behavior[P] = "attacker"
	var starts := 0
	var prev := p.reform_left
	for i in int(10.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		if p.reform_left > prev + 0.001:
			starts += 1
		prev = p.reform_left
	t.check("at most one reform starts in 10 s", starts <= 1, str(starts))
	var faces_one := _off(p.facing, (north.pos - p.pos).angle()) < deg_to_rad(10.0) \
		or _off(p.facing, (south.pos - p.pos).angle()) < deg_to_rad(10.0)
	t.check("and it ends facing one of them", faces_one, str(p.facing))

## Regression (2026-09-30 speed change): AI cavalry that has started a flank
## charge must see it through. The charge carries it away from the flank point,
## and re-testing that distance every rethink flipped it back to "go to the
## flank" — at 30 u/s it then pivoted between the two headings for the rest of
## the battle, never landing a charge, while archers shot it to pieces.
func _test_ai_cavalry_sees_its_flank_charge_through() -> void:
	print("\nbattle AI: cavalry that has begun a flank charge sees it through")
	var sim := _arena()
	var foot := sim.add_block(P, INF_, Vector2(120, 110), 0.0)
	_sturdy(foot)
	sim.order_hold(foot)
	# 18 u from the flank point (120, 50), so the first rethink orders the
	# charge, but facing away (as it arrives from the flank march): it has to
	# pivot before it runs, and one rethink of running leaves that 30 u radius.
	var cav := sim.add_block(E, CAV, Vector2(127, 67), -2.6)
	_sturdy(cav)
	t.check("fixture: it starts in the foot's flank arc", foot.arc_from(cav.pos) == "flank")
	sim.behavior[E] = "attacker"
	var waited := 0.0
	while waited < 3.0 and not sim.contacts_of(cav).has(foot):
		sim.step(TestHarness.DT)
		waited += TestHarness.DT
	t.check("it reaches the foot within 3 s", sim.contacts_of(cav).has(foot), "%s after %.2fs" % [cav.pos, waited])
	t.check("and hits it in the flank", foot.arc_from(cav.pos) != "front", str(cav.pos))

func _test_reform_cancels_when_target_leaves() -> void:
	print("\nreform: it is called off when its target pulls back")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	var flank: Block = f[3]
	sim.order_attack(p, flank)
	sim.step(TestHarness.DT)
	t.check("fixture: reforming", p.reforming())
	var before := p.facing
	sim.order_withdraw(flank)
	sim.step(TestHarness.DT)
	sim.step(TestHarness.DT)
	t.check("no longer reforming", not p.reforming())
	t.check("and it did not turn to where the target was", _off(p.facing, before) < deg_to_rad(3.0), str(p.facing))

func _test_rout_cancels_reform() -> void:
	print("\nreform: a rout cancels it")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	sim.order_attack(p, f[3])
	t.check("fixture: reforming", p.reforming())
	p.morale = 0.0
	sim.step(TestHarness.DT)
	t.check("it routs", p.routing)
	t.check("and is no longer reforming", not p.reforming())

## Damage the flanker takes over 1 s, with P reforming onto it or just holding.
func _flank_damage_taken(reform: bool) -> float:
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	var flank: Block = f[3]
	_sturdy(flank)
	if reform:
		sim.order_attack(p, flank)
	var start := flank.health
	_run(sim, 1.0)
	return start - flank.health

func _test_reform_halves_damage_dealt() -> void:
	print("\nreform: a reforming block deals reform_damage of its melee damage")
	var normal := _flank_damage_taken(false)
	var disordered := _flank_damage_taken(true)
	t.check("fixture: it hurts the flanker when not reforming", normal > 1.0, str(normal))
	t.near("reforming, it deals reform_damage as much", disordered / maxf(normal, 0.001),
		float(GameConfig.combat["reform_damage"]), 0.02)

func _test_reforming_block_does_not_move() -> void:
	print("\nreform: a reforming block does not walk away on a Move")
	var sim := _arena()
	var p := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	_sturdy(p)
	# A weak, underfed horse on its flank: P out-fights it even while disordered,
	# so it is not being pushed and the lock rule alone would let it walk out.
	var cav := sim.add_block(E, CAV, Vector2(120, 62), PI / 2.0)
	_sturdy(cav)
	cav.supply = 0.0
	sim.order_hold(p)
	sim.order_attack(cav, p)
	_run(sim, 4.0)
	t.check("fixture: the horse is in contact on its flank",
		sim.contacts_of(p).has(cav) and sim.arc_of(p, cav.pos) == "flank")
	sim.order_attack(p, cav)
	t.check("fixture: reforming", p.reforming())
	var at := p.pos
	var facing := p.facing
	sim.order_move(p, Vector2(40, 90))                   # due west, behind it
	_run(sim, 1.0)
	t.check("fixture: it is winning", sim.push_state(p) == 1, str(sim.push_state(p)))
	# As the winner it may be carried along after the horse it pushes (north);
	# the Move itself must do nothing: no pivot toward the point, no step west.
	t.check("it did not turn toward the Move point", _off(p.facing, facing) < 0.01, str(p.facing))
	t.check("nor walk toward it", p.pos.x >= at.x - 0.1, str(p.pos))

func _test_routing_block_does_not_reform() -> void:
	print("\nreform: a routing block ordered onto its flanker does not reform")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	var at := p.pos
	p.routing = true
	sim.order_attack(p, f[3])
	t.check("it does not start a reform", not p.reforming(), str(p.reform_left))
	_run(sim, 1.0)
	t.check("and keeps running", p.pos.x < at.x - 3.0, str(p.pos - at))

func _test_deep_enemies_can_part() -> void:
	print("\nsolid enemies: a pair already deep in each other may move apart")
	var sim := _arena()
	var a := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var e := sim.add_block(E, INF_, Vector2(126, 90), PI)
	_sturdy(a)
	_sturdy(e)
	t.check("fixture: they start deeply overlapping", a.overlaps_deeply(e))
	sim.order_withdraw(a)
	_run(sim, 3.0)
	t.check("the withdrawing block got out within 3 s", not a.overlaps_deeply(e),
		"%s vs %s" % [a.pos, e.pos])

func _test_friends_swap_head_on() -> void:
	print("\nfriends: two friends swapping places head-on get past each other")
	var sim := _arena()
	var a := sim.add_block(P, INF_, Vector2(90, 90), 0.0)
	var b := sim.add_block(P, INF_, Vector2(150, 90), PI)
	sim.order_move(a, Vector2(150, 90))
	sim.order_move(b, Vector2(90, 90))
	_run(sim, 15.0)
	t.check("both arrive within 15 s",
		a.pos.distance_to(Vector2(150, 90)) < 1.5 and b.pos.distance_to(Vector2(90, 90)) < 1.5,
		"%s %s" % [a.pos, b.pos])
	# Marching friends pass through each other (user decision 2026-09-24).
	t.check("and stand apart once there", not a.overlaps_deeply(b))
	# Blocks that are not marching stay solid: two attackers whose targets lie
	# beyond each other meet head-on, sidestep and pass.
	var sim2 := _arena()
	var c := sim2.add_block(P, INF_, Vector2(90, 90), 0.0)
	var d := sim2.add_block(P, INF_, Vector2(150, 90), PI)
	var east := sim2.add_block(E, INF_, Vector2(215, 90), PI)
	var west := sim2.add_block(E, INF_, Vector2(25, 90), 0.0)
	for foe in [east, west]:
		_sturdy(foe)
		sim2.order_hold(foe)
	sim2.order_attack(c, east)
	sim2.order_attack(d, west)
	var overlapped := false
	var passed := -1.0
	for i in int(10.0 / TestHarness.DT):
		sim2.step(TestHarness.DT)
		if c.overlaps_deeply(d):
			overlapped = true
		if passed < 0.0 and c.pos.x > d.pos.x + c.depth():
			passed = float(i) * TestHarness.DT
	t.check("two attackers swapping head-on get past each other within 10 s", passed >= 0.0,
		"%s %s" % [c.pos, d.pos])
	t.check("without ever overlapping", not overlapped)

func _test_marching_through_a_friend_is_slowed() -> void:
	print("\nsoft marching: a block passing through a friend is slowed, the friend unmoved")
	var sim := _arena()
	var stand := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	sim.order_hold(stand)
	var walker := sim.add_block(P, INF_, Vector2(50, 90), 0.0)
	sim.order_move(walker, Vector2(200, 90))
	var inside := []
	var outside := []
	for i in int(8.0 * SLOWED / TestHarness.DT):   # scaled for the 2026-09-30 speed change
		var was := walker.pos
		var deep := walker.overlaps_deeply(stand)
		sim.step(TestHarness.DT)
		var step := walker.pos.distance_to(was)
		if i * TestHarness.DT < 1.0 or step == 0.0:
			continue                                 # starting off, or arrived
		(inside if deep else outside).append(step)
	var mean := func(xs: Array) -> float:
		var s := 0.0
		for x in xs:
			s += x
		return s / maxf(1.0, float(xs.size()))
	var ratio: float = mean.call(inside) / maxf(0.0001, mean.call(outside))
	t.check("fixture: it spent time both inside and outside the friend", inside.size() > 10 and outside.size() > 10,
		"%d / %d steps" % [inside.size(), outside.size()])
	t.near("inside it moves at march_overlap_speed Ã its speed", ratio,
		float(GameConfig.combat["march_overlap_speed"]), 0.02)
	t.check("the walker got through", walker.pos.x > 180.0, str(walker.pos))
	t.check("the standing friend never moved", stand.pos == Vector2(120, 90), str(stand.pos))

func _test_cavalry_charge_seats_flush() -> void:
	print("\nlock: a cavalry charge into a front seats flush")
	var sim := _arena()
	var foot := sim.add_block(E, INF_, Vector2(150, 90), PI)
	_sturdy(foot)
	var cav := sim.add_block(P, CAV, Vector2(50, 84), 0.1)
	_sturdy(cav)
	sim.order_attack(cav, foot)
	var waited := 0.0
	while waited < 6.0 and not sim.contacts_of(cav).has(foot):
		sim.step(TestHarness.DT)
		waited += TestHarness.DT
	t.check("fixture: the charge made contact", sim.contacts_of(cav).has(foot), "after %.2fs" % waited)
	_run(sim, 2.0)
	t.check("they are locked", sim._lock_between(cav, foot) != null)
	t.near("seated flush 2 s after contact: centres a depth apart", cav.pos.distance_to(foot.pos),
		(cav.depth() + foot.depth()) * 0.5, 1.0)

func _test_reform_cancels_when_target_dies() -> void:
	print("\nreform: it is called off when its target dies")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	var flank: Block = f[3]
	sim.order_attack(p, flank)
	sim.step(TestHarness.DT)
	t.check("fixture: reforming", p.reforming())
	var before := p.facing
	flank.health = 0.0
	sim.step(TestHarness.DT)
	t.check("no longer reforming", not p.reforming())
	t.check("and it did not turn", _off(p.facing, before) < deg_to_rad(3.0), str(p.facing))

func _test_reform_cancels_when_target_routs() -> void:
	print("\nreform: it is called off when its target routs")
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	var flank: Block = f[3]
	sim.order_attack(p, flank)
	sim.step(TestHarness.DT)
	t.check("fixture: reforming", p.reforming())
	flank.morale = 0.0
	sim.step(TestHarness.DT)
	t.check("fixture: the flanker routs", flank.routing)
	sim.step(TestHarness.DT)
	t.check("no longer reforming", not p.reforming())

func _test_losing_block_can_withdraw() -> void:
	print("\nwalking away: a losing block's Withdraw gets it out")
	var f := _uphill_fight()
	var sim: BattleSim = f[0]
	var up: Block = f[1]
	var down: Block = f[2]
	_sturdy(up)
	_sturdy(down)
	_run(sim, 3.0)
	t.check("fixture: the downhill block is losing", sim.push_state(down) == -1)
	var at := down.pos
	sim.order_withdraw(down)
	_run(sim, 4.0)
	t.check("its lock is gone", sim.locks_of(down).is_empty())
	t.check("and it pulled back", down.pos.x > at.x + 10.0, str(down.pos - at))

## Health `p` loses over 1 s of the flanked fixture, reforming onto the
## flanker or just holding.
func _damage_to_flanked(reform: bool) -> float:
	var f := _flanked()
	var sim: BattleSim = f[0]
	var p: Block = f[1]
	if reform:
		sim.order_attack(p, f[3])
	var start := p.health
	_run(sim, 1.0)
	if reform:
		t.check("fixture: still reforming after 1 s", p.reforming())
	return start - p.health

func _test_reforming_block_takes_flank_damage() -> void:
	print("\nreform: a reforming block keeps taking the flank hit")
	var holding := _damage_to_flanked(false)
	var reforming := _damage_to_flanked(true)
	t.check("fixture: it takes damage while holding", holding > 1.0, str(holding))
	t.near("reforming, it takes as much as holding (flank rate, not front)",
		reforming / maxf(holding, 0.001), 1.0, 0.02)

func _test_lock_is_not_duplicated() -> void:
	print("\nlock: a duel holds exactly one lock")
	var d := _front_duel()
	var sim: BattleSim = d[0]
	var a: Block = d[1]
	var e: Block = d[2]
	_run(sim, 3.0)
	var n := 0
	for lock in sim.locks:
		if lock.has(a) or lock.has(e):
			n += 1
	t.check("one lock between the duel's blocks", n == 1, str(n))

## Final review of drawn orders: a block marched onto an enemy that a friend is
## already fighting frontally used to walk through the friend, reach the enemy
## from inside it and fight stacked (two blocks through one frontage, the
## enemy's losses doubled). It now waits behind its friend.
func _test_march_does_not_stack_onto_a_fight() -> void:
	print("\nsoft marching: no stacking onto a friend's fight")
	for variant in ["route onto the enemy", "move onto the enemy"]:
		var sim := _arena()
		var e := sim.add_block(E, INF_, Vector2(150, 90), PI)
		var f := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
		_sturdy(e)
		_sturdy(f)
		sim.order_hold(e)
		sim.order_attack(f, e)
		_run(sim, 4.0)
		t.check("%s: fixture: the friend is locked with the enemy" % variant, sim.locks_of(f).size() == 1)
		var before := e.health
		_run(sim, 2.0)
		var one_rate := (before - e.health) / 2.0
		var m := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
		_sturdy(m)
		if variant == "route onto the enemy":
			sim.order_route(m, PackedVector2Array([e.pos]), NAN, e)
		else:
			sim.order_move(m, e.pos)
		var ever_deep := false
		for i in int(8.0 / TestHarness.DT):
			sim.step(TestHarness.DT)
			ever_deep = ever_deep or m.overlaps_deeply(f)
		before = e.health
		_run(sim, 2.0)
		var rate := (before - e.health) / 2.0
		t.check("%s: the marcher never ends up deep in its friend" % variant, not ever_deep and not m.overlaps_deeply(f),
			"m %s f %s" % [m.pos, f.pos])
		t.check("%s: and does not fight through it" % variant, sim.locks_of(m).is_empty(), str(sim.locks_of(m).size()))
		t.near("%s: the enemy takes one block's frontage of damage" % variant, rate / maxf(0.0001, one_rate), 1.0, 0.25)

## Marching still passes through a standing friend when no enemy is at hand,
## even with one in sight a little way off.
func _test_march_passes_a_friend_near_an_enemy() -> void:
	print("\nsoft marching: still passes a standing friend away from the enemy")
	var sim := _arena()
	var stand := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	sim.order_hold(stand)
	var foe := sim.add_block(E, INF_, Vector2(120, 140), PI)
	sim.order_hold(foe)
	var walker := sim.add_block(P, INF_, Vector2(50, 90), 0.0)
	sim.order_move(walker, Vector2(200, 90))
	var was_deep := false
	for i in int(10.0 * SLOWED / TestHarness.DT):  # scaled for the 2026-09-30 speed change
		sim.step(TestHarness.DT)
		was_deep = was_deep or walker.overlaps_deeply(stand)
	t.check("it went through the friend", was_deep)
	t.check("and out the far side", walker.pos.x > 190.0, str(walker.pos))

## Last gate: two marchers sent at an enemy a friend is fighting queue behind
## it, stacked in each other. When the friend falls they must not deadlock at
## the enemy (each refused because the step leaves it deep in the other while
## touching it): one takes the fight, the other backs out of it.
func _test_two_marchers_queued_behind_a_fight() -> void:
	print("\nsoft marching: two marchers queued behind a fight do not deadlock")
	for variant in ["move", "route", "move side by side", "move stacked"]:
		var sim := _arena()
		var e := sim.add_block(E, INF_, Vector2(150, 90), PI)
		var f := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
		_sturdy(e)
		sim.order_hold(e)
		sim.order_attack(f, e)
		_run(sim, 3.0)
		f.health = 12.0                        # it falls a few seconds after the queue forms
		var starts := [Vector2(60, 90), Vector2(80, 90)]
		if variant == "move side by side":
			starts = [Vector2(60, 84), Vector2(60, 96)]
		elif variant == "move stacked":
			starts = [Vector2(60, 90), Vector2(60, 90)]
		var ms: Array[Block] = [sim.add_block(P, INF_, starts[0], 0.0), sim.add_block(P, INF_, starts[1], 0.0)]
		for m in ms:
			_sturdy(m)
			if variant != "route":
				sim.order_move(m, e.pos)
			else:
				sim.order_route(m, PackedVector2Array([e.pos]), NAN, e)
		var fell := -1.0
		for i in int(30.0 / TestHarness.DT):
			sim.step(TestHarness.DT)
			if fell < 0.0 and not f.alive():
				fell = sim.time
			if fell >= 0.0 and sim.time - fell >= 3.0 * SLOWED:   # scaled for the 2026-09-30 speed change
				break
		t.check("%s: fixture: the friend fell" % variant, fell >= 0.0)
		var before := e.health
		_run(sim, 5.0 * SLOWED)                 # scaled for the 2026-09-30 speed change
		var locked := not sim.locks_of(ms[0]).is_empty() or not sim.locks_of(ms[1]).is_empty()
		t.check("%s: one of them takes the fight" % variant, locked,
			"%s %s e %s" % [ms[0].pos, ms[1].pos, e.pos])
		t.check("%s: and the enemy takes damage" % variant, e.health < before - 1.0, "%.1f lost" % (before - e.health))
		t.check("%s: they do not end stacked" % variant, not ms[0].overlaps_deeply(ms[1]),
			"%s %s locks %d/%d orders %d/%d" % [ms[0].pos, ms[1].pos, sim.locks_of(ms[0]).size(), sim.locks_of(ms[1]).size(), ms[0].order, ms[1].order])

## The reach the battle view rings around an archer block is the reach its
## targeting uses: the role's range on open ground, cut in a forest.
func _test_shooting_range() -> void:
	print("\nshooting range: the ring the view draws")
	var sim := _arena(Rect2(0, 0, 1200, 800))
	var arc := sim.add_block(P, GameConfig.Role.ARCHERS, Vector2(120, 90), 0.0)
	var reach: float = GameConfig.units[GameConfig.Role.ARCHERS]["range"]
	t.near("on open ground it is the role's range", sim.shooting_range(arc), reach, 0.001)
	arc.pos = Vector2(200, 600)                             # Woodhaven, in the forest
	t.check("fixture: that spot is forest", terrain.biome_at(arc.pos) == Terrain.Biome.FOREST)
	t.near("in a forest it is cut", sim.shooting_range(arc),
		reach * float(GameConfig.terrain_mods["forest_archer_range"]), 0.001)
	var foot := sim.add_block(P, INF_, Vector2(300, 90), 0.0)
	t.near("a block with no bow has no reach", sim.shooting_range(foot),
		float(GameConfig.units[INF_]["range"]), 0.001)

## The Shoot order: archers stand and shoot a chosen enemy in reach, walk into
## reach of one that isn't, prefer it over anything nearer, fall back to the
## nearest when it is gone, and shoot what a route drawn onto an enemy ends on.
## A block with no bow given a Shoot order attacks instead.
func _test_shoot_order() -> void:
	print("\nshoot order: archers shoot the enemy you pick")
	var ARC := GameConfig.Role.ARCHERS
	var reach: float = GameConfig.units[ARC]["range"]

	var sim := _arena()
	var arc := sim.add_block(P, ARC, Vector2(60, 90), 0.0)
	var near := sim.add_block(E, INF_, Vector2(110, 60), PI)
	var far := sim.add_block(E, INF_, Vector2(160, 110), PI)
	for b in [near, far]:
		sim.order_hold(b)
	sim.order_shoot(arc, far)
	t.check("an archer given Shoot has the Shoot order", arc.order == Block.OrderType.SHOOT)
	var hp := far.health
	var near_hp := near.health
	_run(sim, 2.0)
	t.check("in reach it does not move", arc.pos.distance_to(Vector2(60, 90)) < 0.5, str(arc.pos))
	t.check("it shoots the chosen enemy", far.health < hp and arc.shooting_id == far.id)
	t.check("not the nearer one", is_equal_approx(near.health, near_hp), "%f" % near.health)

	var sim2 := _arena()
	var walker := sim2.add_block(P, ARC, Vector2(20, 90), 0.0)
	var mark := sim2.add_block(E, INF_, Vector2(200, 90), PI)
	sim2.order_hold(mark)
	sim2.order_shoot(walker, mark)
	_run(sim2, 20.0)
	var gap := walker.pos.distance_to(mark.pos)
	t.check("out of reach it walks until the target is in reach", gap <= reach + 0.5, "gap %f" % gap)
	t.check("and stops there rather than closing in", gap > reach - 15.0, "gap %f" % gap)
	var at := walker.pos
	_run(sim2, 1.0)
	t.check("then stands and shoots", walker.pos.distance_to(at) < 0.1 and walker.shooting_id == mark.id)

	var sim3 := _arena()
	var arc3 := sim3.add_block(P, ARC, Vector2(60, 90), 0.0)
	var gone := sim3.add_block(E, INF_, Vector2(160, 90), PI)
	var other := sim3.add_block(E, INF_, Vector2(140, 130), PI)
	sim3.order_hold(other)
	sim3.order_shoot(arc3, gone)
	gone.health = 0.0
	gone.status = Block.Status.DESTROYED
	_run(sim3, 1.0)
	t.check("when its target is gone the order lapses", arc3.order == Block.OrderType.NONE, str(arc3.order))
	t.check("and it shoots the nearest enemy again", arc3.shooting_id == other.id)

	var sim4 := _arena()
	var foot := sim4.add_block(P, INF_, Vector2(60, 90), 0.0)
	var foe4 := sim4.add_block(E, INF_, Vector2(160, 90), PI)
	sim4.order_shoot(foot, foe4)
	t.check("a block with no bow given Shoot attacks instead",
		foot.order == Block.OrderType.ATTACK and foot.target_id == foe4.id)

	var sim5 := _arena()
	var arc5 := sim5.add_block(P, ARC, Vector2(40, 90), 0.0)
	var foe5 := sim5.add_block(E, INF_, Vector2(200, 90), PI)
	sim5.order_hold(foe5)
	sim5.order_route(arc5, PackedVector2Array([Vector2(70, 60)]), NAN, foe5)
	_run(sim5, 6.0)
	t.check("an archer's route drawn onto an enemy ends in a Shoot, not a charge",
		arc5.order == Block.OrderType.SHOOT and arc5.target_id == foe5.id, str(arc5.order))
