# Battle Contact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Blocks that meet lock together, the side winning the damage trade pushes the other back, an attack pulls the attacker flush against the face it struck, facing turns at a rate instead of snapping, friendly blocks are solid, and a flanked block ordered to attack its flanker re-faces after a visible, risky reform.

**Architecture:** A new `Contact` record (`game/scripts/sim/contact.gd`) is created by `BattleSim` for every touching enemy pair and updated each step before free movement: seating (turn + slide to the struck face), pressure (smoothed damage per second through the contact), push (loser moves along the contact normal). Turning and the reform live on `Block`; `BattleSim` wires them into `step()`. `BattleView` draws the reform procedurally.

**Tech Stack:** Godot 4.5 GDScript (CI) / 4.7.1 locally, headless test runner `game/tests/run_tests.gd`.

**Spec:** `docs/superpowers/specs/2026-09-23-battle-contact-design.md` (approved).

## Global Constraints

- The sim stays `RefCounted`, rendering-free and deterministic; no randomness is added.
- Every new tunable lives in `GameConfig` and shows in the tuning panels: `GameConfig.combat` gains `seat_speed` 30.0, `push_per_dps` 1.0, `push_max` 6.0, `push_deadband` 0.5, `push_smoothing` 1.0, `pivot_angle` 30.0, `reform_damage` 0.5; each `GameConfig.units[role]` gains `turn_rate` (deg/s: infantry 90, archers 120, cavalry 180) and `reform_time` (s: infantry 2.0, archers 1.5, cavalry 1.5). These are starting values; only these new values may be tuned to keep existing claims.
- Existing combat claims stay pass/fail bars (the combat suite prints 88 = 87 real checks + the runner's "produced checks" line): a flank charge on an engaged block routs it within ~5 s; the same charge into a braced front fails; an uncovered withdrawal under cavalry is a disaster and a covered one survives; the hill and the bridge beat open ground; every battle ends within the clock; the Ford near-miss is still recorded. Measured values (trades, Ford counts) may move and are re-measured in Task 7. **If a claim fails, tune the new values above first; if tuning cannot keep it, stop and report — never weaken a check.** WS-C's East Hill acceptance (`test_battle_bridge.gd`) must still hold.
- Decisions carried from the spec: an engaged block ignores Move unless it is *winning* every lock it is in by more than `push_deadband`; Withdraw / Retreat all / rout / death end locks; front-to-front locks square both blocks; flank and rear locks move only the attacker; friendly blocks are solid (a pair that already overlaps may move apart); **routing blocks run through their own side and turn while moving (no pivot)** — a rout that stopped to pivot in contact would be deleted, which the spec does not intend.
- Test ground (probed): flat open plain around (120, 90) — arena field `Rect2(10, 10, 220, 160)`; a slope falling east along y = 490 (height 48 at x 940, 32 at x 960); river water at x 600–650 on y = 330, plain from x 660 east.
- Tests: `cd game && $G --headless --script tests/run_tests.gd -- contact` (the new suite) or no argument (all). `$G` = `/k/Godot/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe`. New `class_name` scripts need `$G --headless --path game --import` once; stage the `.gd.uid` files. Use no API newer than Godot 4.5 (`rotate_toward` and `angle_difference` are fine).
- Git: never commit or push; stage with `git add`; never stage `game/icon.svg.import`.

---

## File map

| File | Responsibility |
| --- | --- |
| `game/scripts/sim/contact.gd` (new) | `Contact`: one lock between two enemy blocks — which face was struck, damage recorded through it, smoothed pressure, the loser; static geometry helpers (face, normal, half extent). |
| `game/scripts/sim/block.gd` | + `turn_toward`, reform state (`reform_left`, `reform_from`, `reform_target_id`, `reforming()`). |
| `game/scripts/sim/battle_sim.gd` | step order; turning and pivot in `_move`; solid friends; lock lifecycle, seating, push, walk-away; reform start/tick/cancel; damage multiplier; `locks_of`, `push_state`, `reform_facing`. |
| `game/scripts/sim/game_config.gd` | new `combat` keys and per-role `turn_rate`, `reform_time`. |
| `game/scripts/ui/game_root.gd` | the prototype's tuning panel lists the two new per-role keys. |
| `game/scripts/ui/battle_view.gd` | reform drawing, REFORMING tag, tooltip states. |
| `game/tests/test_contact.gd` (new) | one check per rule. |
| `README.md` | "Battle rules" paragraph for contact, re-measured numbers. |

---

### Task 1: Config and turn rates

**Files:**
- Modify: `game/scripts/sim/game_config.gd`, `game/scripts/sim/block.gd`, `game/scripts/sim/battle_sim.gd` (`_move`), `game/scripts/ui/game_root.gd` (tuning list)
- Create: `game/tests/test_contact.gd`

**Interfaces:**
- Produces: `Block.turn_toward(angle: float, dt: float) -> float` (turns `facing` toward `angle` at the role's `turn_rate`, returns the remaining absolute angle in radians). `_move` pivots in place while more than `pivot_angle` off its heading (routing blocks excepted) and no longer snaps facing.

- [ ] **Step 1: Write the failing tests**

Create `game/tests/test_contact.gd`:

```gdscript
extends RefCounted

## Battle contact (spec 2026-09-23-battle-contact-design.md): turn rates,
## solid friends, locks and seating, pressure and push, walking away, the
## reform. Every check runs on probed ground: flat plain around (120, 90), the
## east slope of the big hill on y = 490, the river bank at x = 660 on y = 330.

const INF_ := GameConfig.Role.INFANTRY
const CAV := GameConfig.Role.CAVALRY
const P := GameConfig.Side.PLAYER
const E := GameConfig.Side.ENEMY

var t: TestHarness
var terrain: Terrain

func run(harness: TestHarness) -> void:
	t = harness
	terrain = Terrain.new()
	_test_config()
	_test_turn_rate()

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
	return sim

func _run(sim: BattleSim, seconds: float) -> void:
	t.run_for(sim, seconds)

func _off(a: float, b: float) -> float:
	return absf(angle_difference(a, b))

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
	t.near("infantry turns about 90° in 1 s", _off(0.0, b.facing), PI / 2.0, 0.1)
	_run(sim, 1.3)
	t.check("after ~2 s it faces the way it walks", _off(b.facing, PI) < 0.05, str(b.facing))
	t.check("and has started walking", b.pos.x < 118.0, str(b.pos))
	var cav := sim.add_block(E, CAV, Vector2(120, 140), 0.0)
	sim.order_move(cav, Vector2(40, 140))
	_run(sim, 1.0)
	t.check("cavalry turns 180° in about a second", _off(cav.facing, PI) < 0.1, str(cav.facing))
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- contact`
Expected: FAIL — config keys missing; the turn check fails because facing snaps.

- [ ] **Step 3: Implement**

In `game_config.gd`, add to each role in `units` (after `"can_brace"`):

```gdscript
		"turn_rate": 90.0,     # deg/s (infantry)
		"reform_time": 2.0,    # s to turn to face a flanker
```
with cavalry `"turn_rate": 180.0, "reform_time": 1.5` and archers `"turn_rate": 120.0, "reform_time": 1.5`. Append to `combat` (before `"battle_seconds"`):

```gdscript
	# Contact (spec 2026-09-23): locks, pressure, push, turning, reform.
	"seat_speed": 30.0,        # u/s an attacker slides to sit flush on the face it struck
	"push_per_dps": 1.0,       # push speed per point of damage-per-second advantage
	"push_max": 6.0,           # u/s cap on how fast a loser gives ground
	"push_deadband": 0.5,      # dps advantage below which a fight is even
	"push_smoothing": 1.0,     # s over which pressure is averaged
	"pivot_angle": 30.0,       # deg off heading beyond which a block turns in place
	"reform_damage": 0.5,      # damage dealt while reforming
```

In `block.gd`, below `face_towards`:

```gdscript
## Turn toward `angle` at this role's turn rate. Returns how far off it still
## is, in radians, so the caller can decide whether to walk yet.
func turn_toward(angle: float, dt: float) -> float:
	var rate := deg_to_rad(float(stats()["turn_rate"]))
	facing = rotate_toward(facing, angle, rate * dt)
	return absf(angle_difference(facing, angle))
```

In `battle_sim.gd` `_move`, replace from `var dir := to_dest.normalized()` to the end of the function with:

```gdscript
	var dir := to_dest.normalized()
	# Turn first: a formed block wheels rather than spinning on the spot. A
	# rout runs while it turns — stopping to pivot in contact would be death.
	var off := b.turn_toward(dir.angle(), dt)
	if not b.routing and off > deg_to_rad(GameConfig.combat["pivot_angle"]):
		b.charge_run = 0.0
		return
	var stride: float = speed * dt
	var moved := _try_step(b, dir, stride)

	if moved > 0.0:
		# A charge needs a straight run-up; turning resets it.
		if b.last_move_dir.dot(dir) > 0.9:
			b.charge_run += moved
		else:
			b.charge_run = moved
		b.last_move_dir = dir
	if terrain.biome_at(b.pos) == Terrain.Biome.FOREST:
		b.charge_run = 0.0
```

In `game_root.gd` `_build_tuning_panel`, extend the per-unit key list to `["health", "morale", "speed", "melee_dps", "ranged_dps", "range", "charge_burst", "turn_rate", "reform_time"]`, and the `combat` loop already lists every combat key.

- [ ] **Step 4: Run the suite and every suite**

Run: `$G --headless --path game --import`, then `cd game && $G --headless --script tests/run_tests.gd -- contact` → all `ok`.
Run all suites. If a combat claim now fails (withdrawals pivot before walking; charges need a straight run-up), tune only `turn_rate` / `pivot_angle` and record every change and its effect in the report. If no tuning keeps it, report DONE_WITH_CONCERNS with the failing check's output.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/game_config.gd game/scripts/sim/block.gd game/scripts/sim/battle_sim.gd game/scripts/ui/game_root.gd game/tests/test_contact.gd game/tests/test_contact.gd.uid
```
Suggested message: `Battle: blocks turn at a rate and pivot before walking`

---

### Task 2: Solid friendly blocks

**Files:**
- Modify: `game/scripts/sim/battle_sim.gd` (`step`, `_try_step`, remove `_separate` and `_nudge`, add `_blocked`, `_blocked_by_friend`, `_can_stand`)
- Modify: `game/tests/test_contact.gd`

**Interfaces:**
- Produces: `BattleSim._can_stand(b: Block, next: Vector2, ignore: Array) -> bool` — terrain, field (unless routing), bridge lane, and no *new* deep overlap with any alive block not in `ignore` (routing blocks ignore friends). Tasks 3–4 use it for seating and pushing.

- [ ] **Step 1: Write the failing tests**

Add to `run()` after `_test_turn_rate()`: `_test_friends_are_solid()` and `_test_routers_run_through_friends()`. Append:

```gdscript
func _test_friends_are_solid() -> void:
	print("\nfriends are solid: no shoving, no overlapping")
	var sim := _arena()
	var wall := sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var walker := sim.add_block(P, INF_, Vector2(60, 90), 0.0)
	sim.order_move(walker, Vector2(180, 90))
	var overlapped := false
	for i in int(6.0 / TestHarness.DT):
		sim.step(TestHarness.DT)
		if walker.overlaps_deeply(wall):
			overlapped = true
	t.check("a friend walking into a standing friend never overlaps it", not overlapped)
	t.check("and never shoves it", wall.pos.is_equal_approx(Vector2(120, 90)), str(wall.pos))
	var sim2 := _arena()
	var a := sim2.add_block(P, INF_, Vector2(80, 90), 0.0)
	var b := sim2.add_block(P, INF_, Vector2(160, 90), PI)
	sim2.order_move(a, Vector2(120, 90))
	sim2.order_move(b, Vector2(120, 90))
	_run(sim2, 6.0)
	t.check("two friends converging on one point do not overlap", not a.overlaps_deeply(b))

func _test_routers_run_through_friends() -> void:
	print("\na rout runs through its own side")
	var sim := _arena()
	sim.home_dir[P] = Vector2.RIGHT
	sim.add_block(P, INF_, Vector2(120, 90), 0.0)
	var r := sim.add_block(P, INF_, Vector2(70, 90), 0.0)
	r.routing = true
	r.morale = 0.0
	_run(sim, 4.0)
	t.check("the routing block got past the friend in its way", r.pos.x > 140.0, str(r.pos))
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- contact`
Expected: FAIL — "never shoves it" (today `_separate` pushes the standing block).

- [ ] **Step 3: Implement**

In `battle_sim.gd`:
1. Delete the `_separate()` call in `step()` and delete the `_separate` and `_nudge` functions.
2. In `_try_step`, replace `if _blocked_by_enemy(b, next) or _bridge_lane_taken(b, next):` with `if _blocked(b, next) or _bridge_lane_taken(b, next):`.
3. Add after `_blocked_by_enemy`:

```gdscript
## Friends are solid too — a block waits or slides around a friend rather than
## shoving it — except that a pair already overlapping (a rally, a push) may
## move apart, and a rout runs straight through its own side.
func _blocked(b: Block, next: Vector2) -> bool:
	if _blocked_by_enemy(b, next):
		return true
	return not b.routing and _blocked_by_friend(b, next)

func _blocked_by_friend(b: Block, next: Vector2) -> bool:
	var was := b.pos
	for other in blocks:
		if other == b or not other.alive() or other.side != b.side or other.routing:
			continue
		var before := b.overlaps_deeply(other)
		b.pos = next
		var after := b.overlaps_deeply(other)
		b.pos = was
		if after and not before:
			return true
	return false

## Somewhere `b` may be put by seating or a push: open ground, on the field
## (unless routing), a free bridge lane, and no new overlap with any block
## except those in `ignore` (the ones it is locked with).
func _can_stand(b: Block, next: Vector2, ignore: Array) -> bool:
	if terrain.is_blocked(next, b.role):
		return false
	if not b.routing and not field.has_point(next):
		return false
	if _bridge_lane_taken(b, next):
		return false
	var was := b.pos
	for other in blocks:
		if other == b or not other.alive() or ignore.has(other):
			continue
		if b.routing and other.side == b.side:
			continue
		var before := b.overlaps_deeply(other)
		b.pos = next
		var after := b.overlaps_deeply(other)
		b.pos = was
		if after and not before:
			return false
	return true
```

- [ ] **Step 4: Run the suite and every suite**

`-- contact` → all `ok`; then all suites. Combat checks that relied on friendlies giving way (the Ford plan, covered withdrawal, scenarios running to the clock) may change; tune only the new values, or, if a failure is a jam that tuning cannot fix, report DONE_WITH_CONCERNS with the check, its output and where blocks jammed (print positions).

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/battle_sim.gd game/tests/test_contact.gd
```
Suggested message: `Battle: friendly blocks are solid instead of shoving each other`

---

### Task 3: Locks, seating and pressure

**Files:**
- Create: `game/scripts/sim/contact.gd`
- Modify: `game/scripts/sim/battle_sim.gd`
- Modify: `game/tests/test_contact.gd`

**Interfaces:**
- Produces `Contact` (RefCounted): `var initiator: Block`, `var target: Block`, `var face: String` (`"front" | "left" | "right" | "rear"` of the target), `var pressure := {}` (block id → smoothed dps through this lock); `static func begin(a: Block, b: Block) -> Contact`; `static func face_of(target: Block, from: Vector2) -> String`; `static func normal(target: Block, face: String) -> Vector2` (unit, pointing out of that face); `static func half_extent(target: Block, face: String) -> float`; `func squares() -> bool` (`face == "front"`); `func other(b: Block) -> Block`; `func has(b: Block) -> bool`; `func record(from: Block, amount: float)`; `func settle(dt: float) -> void`; `func gap(b: Block) -> float` (b's pressure minus the other's); `func loser() -> Block` (null when the gap is within `push_deadband`).
- Produces on `BattleSim`: `var locks: Array[Contact]`; `func locks_of(b: Block) -> Array[Contact]`; step order (below).

- [ ] **Step 1: Write the failing tests**

Add to `run()`: `_test_front_contact_squares_up()`, `_test_flank_hit_leaves_victim_facing()`, `_test_locked_move_is_ignored()`, `_test_withdraw_breaks_the_lock()`. Append:

```gdscript
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
```

- [ ] **Step 2: Run to verify it fails**

Expected: parse error / FAIL — `Contact` and `locks_of` do not exist.

- [ ] **Step 3: Implement `contact.gd`**

```gdscript
class_name Contact
extends RefCounted

## One lock between two enemy blocks in contact (spec 2026-09-23). The
## initiator is pulled flush against the face of the target it struck; the
## damage each deals the other through this contact is smoothed into pressure,
## and whoever is ahead by more than `push_deadband` pushes the other back.

var initiator: Block
var target: Block
var face := "front"            # side of the target the initiator struck
var pressure := {}             # block id -> smoothed damage per second through this lock
var _dealt := {}               # block id -> damage dealt through this lock this step

## A new lock. The initiator is the block whose front points more squarely at
## the other (ties: lower id), so a charge that arrives is the one that seats.
static func begin(a: Block, b: Block) -> Contact:
	var c := Contact.new()
	var da := Vector2.RIGHT.rotated(a.facing).dot((b.pos - a.pos).normalized())
	var db := Vector2.RIGHT.rotated(b.facing).dot((a.pos - b.pos).normalized())
	var a_first := da > db or (is_equal_approx(da, db) and a.id < b.id)
	c.initiator = a if a_first else b
	c.target = b if a_first else a
	c.face = face_of(c.target, c.initiator.pos)
	c.pressure = {a.id: 0.0, b.id: 0.0}
	c._dealt = {a.id: 0.0, b.id: 0.0}
	return c

## Which side of `target` a point lies on, by the 45°/135° arc rule; the flank
## is split by which side of the facing line the point falls.
static func face_of(target: Block, from: Vector2) -> String:
	var arc := target.arc_from(from)
	if arc != "flank":
		return arc
	var local := (from - target.pos).rotated(-target.facing)
	return "left" if local.y < 0.0 else "right"

## Unit vector out of that face of `target`.
static func normal(target: Block, p_face: String) -> Vector2:
	var f := Vector2.RIGHT.rotated(target.facing)
	match p_face:
		"rear": return -f
		"left": return f.rotated(-PI / 2.0)
		"right": return f.rotated(PI / 2.0)
	return f

## Distance from the target's centre to that face.
static func half_extent(target: Block, p_face: String) -> float:
	return target.depth() * 0.5 if p_face == "front" or p_face == "rear" else target.frontage() * 0.5

func squares() -> bool:
	return face == "front"

func has(b: Block) -> bool:
	return b == initiator or b == target

func other(b: Block) -> Block:
	return target if b == initiator else initiator

func record(from: Block, amount: float) -> void:
	_dealt[from.id] = float(_dealt.get(from.id, 0.0)) + amount

## Fold this step's damage into the smoothed pressure.
func settle(dt: float) -> void:
	var k := clampf(dt / maxf(float(GameConfig.combat["push_smoothing"]), 0.001), 0.0, 1.0)
	for id in _dealt:
		var rate: float = float(_dealt[id]) / maxf(dt, 0.0001)
		pressure[id] = lerpf(float(pressure.get(id, 0.0)), rate, k)
		_dealt[id] = 0.0

func gap(b: Block) -> float:
	return float(pressure.get(b.id, 0.0)) - float(pressure.get(other(b).id, 0.0))

func loser() -> Block:
	var g := gap(initiator)
	if absf(g) <= float(GameConfig.combat["push_deadband"]):
		return null
	return target if g > 0.0 else initiator
```

- [ ] **Step 4: Wire locks into `battle_sim.gd`**

Add `var locks: Array[Contact] = []` and `var _released := {}` (pair key → true) beside `_prev_contacts`. Replace `step()` with:

```gdscript
func step(dt: float) -> void:
	if finished or not started:
		return
	time += dt

	BattleAI.run(self, dt)

	_damage_taken.clear()
	_update_locks(dt)
	for b in blocks:
		if b.alive():
			_move(b, dt)

	var contacts := _find_contacts()
	_sync_locks(contacts)
	_resolve_charges(contacts)
	_resolve_melee(contacts, dt)
	_resolve_ranged(dt)
	_resolve_morale(contacts, dt)
	_resolve_status(contacts, dt)
	for lock in locks:
		lock.settle(dt)
	_prev_contacts = contacts
	_check_end()
```

Add the lock functions (a new section after `_find_contacts`):

```gdscript
# ---------------------------------------------------------------------- locks

func locks_of(b: Block) -> Array[Contact]:
	var out: Array[Contact] = []
	for lock in locks:
		if lock.has(b):
			out.append(lock)
	return out

func _lock_between(a: Block, b: Block) -> Contact:
	for lock in locks:
		if lock.has(a) and lock.has(b):
			return lock
	return null

func _pair_key(a: Block, b: Block) -> String:
	return _contact_key(a, b)

## A block that can hold a lock: alive, not routing, not pulling back.
func _can_lock(b: Block) -> bool:
	return b.alive() and not b.routing and b.order != Block.OrderType.WITHDRAW

## End locks that broke (no longer touching, a rout, a withdrawal, a death) and
## start one for every touching pair that has none. A pair a winner walked out
## of is left alone until it separates, so the walk-out is not undone.
func _sync_locks(contacts: Dictionary) -> void:
	var kept: Array[Contact] = []
	for lock in locks:
		if _can_lock(lock.initiator) and _can_lock(lock.target) \
				and contacts.get(lock.initiator.id, []).has(lock.target):
			kept.append(lock)
	locks = kept
	var touching := {}
	for a in blocks:
		for b in contacts.get(a.id, []):
			if a.id < b.id:
				touching[_pair_key(a, b)] = true
				if _released.has(_pair_key(a, b)) or _lock_between(a, b) != null:
					continue
				if _can_lock(a) and _can_lock(b):
					locks.append(Contact.begin(a, b))
	for key in _released.keys():
		if not touching.has(key):
			_released.erase(key)

## Pull every initiator flush against the face it struck; a front-to-front
## lock squares both blocks. Runs before free movement each step.
func _update_locks(dt: float) -> void:
	for lock in locks:
		_seat(lock, dt)

func _seat(lock: Contact, dt: float) -> void:
	var i := lock.initiator
	var t := lock.target
	var goal: Vector2
	if lock.squares():
		var axis := t.pos - i.pos
		axis = axis.normalized() if axis.length_squared() > 0.0001 else Vector2.RIGHT.rotated(i.facing)
		i.turn_toward(axis.angle(), dt)
		t.turn_toward((-axis).angle(), dt)
		goal = t.pos - axis * (i.depth() + t.depth()) * 0.5
	else:
		var n := Contact.normal(t, lock.face)
		i.turn_toward((-n).angle(), dt)
		goal = t.pos + n * (Contact.half_extent(t, lock.face) + i.depth() * 0.5)
	_slide(i, goal, float(GameConfig.combat["seat_speed"]) * dt)

## Move `b` toward `goal` by at most `max_step`, if it may stand there.
func _slide(b: Block, goal: Vector2, max_step: float) -> void:
	var to_goal := goal - b.pos
	if to_goal.length() < 0.01:
		return
	var next := b.pos + to_goal.limit_length(max_step)
	var partners: Array = []
	for lock in locks_of(b):
		partners.append(lock.other(b))
	if _can_stand(b, next, partners):
		b.pos = next
```

In `_move`, right after the existing "A block already in contact is locked in melee" early return, add:

```gdscript
	# Locked: a Move or an Attack on someone else does not walk a block out of
	# a fight. Withdraw, a rout, or winning the fight (Task 4) are the ways out.
	if not b.routing and b.order != Block.OrderType.WITHDRAW and not locks_of(b).is_empty() \
			and (b.order == Block.OrderType.MOVE or b.order == Block.OrderType.ATTACK):
		b.charge_run = 0.0
		return
```

Record damage through locks: in `_resolve_melee`, after `_hurt(b, dmg)` add:

```gdscript
			var lock := _lock_between(a, b)
			if lock != null:
				lock.record(a, dmg)
```

and in `_resolve_charges`, after `_hurt(b, burst)` add the same three lines with `burst` in place of `dmg`.

- [ ] **Step 5: Run the suite and every suite**

`$G --headless --path game --import`; `-- contact` → all `ok`; then all suites. Tuning rules as in Task 1 (only `seat_speed` among this task's values). Report every tuning change.

- [ ] **Step 6: Stage**

```bash
git add game/scripts/sim/contact.gd game/scripts/sim/contact.gd.uid game/scripts/sim/battle_sim.gd game/tests/test_contact.gd
```
Suggested message: `Battle: blocks in contact lock together and seat flush on the face they struck`

---

### Task 4: Push, giving ground, and walking away

**Files:**
- Modify: `game/scripts/sim/battle_sim.gd`, `game/tests/test_contact.gd`

**Interfaces:**
- Consumes: `Contact.loser/gap/normal/squares`, `BattleSim._can_stand`, `locks_of`, `_released`.
- Produces: `BattleSim.push_state(b: Block) -> int` (1 = winning every lock it is in, -1 = the loser of at least one lock, 0 = otherwise); a winning block's Move walks it out (its locks end and their pairs are released).

- [ ] **Step 1: Write the failing tests**

Add to `run()`: `_test_even_fight_does_not_drift()`, `_test_uphill_pushes_downhill()`, `_test_river_stops_the_push()`, `_test_winner_walks_away()`. Append:

```gdscript
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

## Uphill deals ×1.25 and takes ×0.75: 10 dps against 6, a 4 dps gap.
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
	_run(sim, 5.0)
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
	var down_at := down.pos
	sim.order_move(down, Vector2(1020, 490))
	_run(sim, 1.0)
	t.check("the loser's Move is ignored", not sim.locks_of(down).is_empty())
	var up_at := up.pos
	sim.order_move(up, Vector2(880, 490))
	_run(sim, 4.0)
	t.check("the winner's Move ends the lock", sim.locks_of(up).is_empty())
	t.check("and it walks off", up.pos.x < up_at.x - 5.0, str(up.pos))
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `push_state` missing; the uphill block does not push.

- [ ] **Step 3: Implement**

In `battle_sim.gd`, replace `_update_locks` with:

```gdscript
func _update_locks(dt: float) -> void:
	for lock in locks:
		_seat(lock, dt)
	_push(dt)
```

In `_seat`, a losing initiator is pushed away from the face rather than pulled back onto it: replace the final line `_slide(i, goal, …)` with

```gdscript
	if lock.loser() != i:
		_slide(i, goal, float(GameConfig.combat["seat_speed"]) * dt)
```

Add after `_slide`:

```gdscript
## Every lock's loser gives ground along the contact line, away from the
## winner, at push_per_dps × the gap (capped); a block losing several locks
## moves by their capped sum. Blocked ground stops it — nobody overlaps. A
## winning initiator follows by re-seating; a winning target steps after a
## pushed initiator as long as that is its only fight.
func _push(dt: float) -> void:
	var shove := {}
	for lock in locks:
		var lose := lock.loser()
		if lose == null:
			continue
		var win := lock.other(lose)
		var speed := minf(absf(lock.gap(win)) * float(GameConfig.combat["push_per_dps"]),
			float(GameConfig.combat["push_max"]))
		var n: Vector2          # from the target toward the initiator
		if lock.squares():
			n = (lock.initiator.pos - lock.target.pos).normalized()
		else:
			n = Contact.normal(lock.target, lock.face)
		var dir := -n if lose == lock.target else n
		shove[lose] = shove.get(lose, Vector2.ZERO) + dir * speed
	for lose in shove:
		var step_v: Vector2 = (shove[lose] as Vector2).limit_length(float(GameConfig.combat["push_max"])) * dt
		var partners: Array = []
		for lock in locks_of(lose):
			partners.append(lock.other(lose))
		if not _can_stand(lose, lose.pos + step_v, partners):
			continue
		lose.pos += step_v
		for lock in locks_of(lose):
			var win := lock.other(lose)
			if lose == lock.initiator and locks_of(win).size() == 1 \
					and _can_stand(win, win.pos + step_v, [lose]):
				win.pos += step_v

## 1: ahead in every lock by more than the dead band. -1: behind in at least
## one. 0: not locked, or even somewhere.
func push_state(b: Block) -> int:
	var mine := locks_of(b)
	if mine.is_empty():
		return 0
	var winning := true
	for lock in mine:
		if lock.loser() == b:
			return -1
		if lock.gap(b) <= float(GameConfig.combat["push_deadband"]):
			winning = false
	return 1 if winning else 0

## A winner walking out: its locks end and the pairs are left alone until they
## separate, so the lock is not re-made the next step.
func _release(b: Block) -> void:
	for lock in locks_of(b):
		_released[_pair_key(lock.initiator, lock.target)] = true
		locks.erase(lock)
```

In `_move`, change the lock check added in Task 3 so a winning block's Move walks out:

```gdscript
	if not b.routing and b.order != Block.OrderType.WITHDRAW and not locks_of(b).is_empty() \
			and (b.order == Block.OrderType.MOVE or b.order == Block.OrderType.ATTACK):
		if b.order == Block.OrderType.MOVE and push_state(b) == 1:
			_release(b)
		else:
			b.charge_run = 0.0
			return
```

Note the existing "already in contact is locked in melee" early return only fires for ATTACK orders, so a released block with a Move order walks on.

- [ ] **Step 4: Run the suite and every suite**

`-- contact` → all `ok`; all suites. Tuning rules as before (this task's values: `push_per_dps`, `push_max`, `push_deadband`, `push_smoothing`).

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/battle_sim.gd game/tests/test_contact.gd
```
Suggested message: `Battle: the winning block pushes the loser back; only a winner can walk away`

---

### Task 5: The reform

**Files:**
- Modify: `game/scripts/sim/block.gd`, `game/scripts/sim/battle_sim.gd`, `game/tests/test_contact.gd`

**Interfaces:**
- Produces on `Block`: `var reform_left := 0.0`, `var reform_from := 0.0`, `var reform_target_id := -1`, `func reforming() -> bool`.
- Produces on `BattleSim`: `func reform_facing(b: Block) -> float` (the facing the reform ends on: toward the reform target, else the block's facing); `func damage_multiplier(b: Block) -> float` (`reform_damage` while reforming, else 1.0). An Attack order on an enemy touching the block outside its front arc starts a reform; re-issuing it does not restart it; Withdraw / Retreat all / a rout cancels it; on completion the block faces the target and every lock where it is the target has its face recomputed.

- [ ] **Step 1: Write the failing tests**

Add to `run()`: `_test_reform_turns_to_the_flanker()`, `_test_reform_is_not_restarted()`, `_test_withdraw_cancels_reform()`, `_test_no_reform_when_free()`, `_test_ai_reforms_once()`. Append:

```gdscript
## Enough health and morale that a block survives a long, badly flanked test:
## held at the front and hit in the flank, morale drains at 20/s and damage at
## 20/s, which would rout or kill it before the reform the test is about ends.
func _sturdy(b: Block) -> void:
	b.max_health = 1000.0
	b.health = 1000.0
	b.max_morale = 1000.0
	b.morale = 1000.0

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
	sim.order_attack(p, flank)
	t.check("it starts reforming", p.reforming())
	t.near("for its role's reform_time", p.reform_left, float(p.stats()["reform_time"]), 0.001)
	t.near("disordered: half damage", sim.damage_multiplier(p), float(GameConfig.combat["reform_damage"]), 0.001)
	_run(sim, 1.0)
	t.check("halfway through it has not turned yet", _off(p.facing, 0.0) < 0.01, str(p.facing))
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
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `reforming()` and `damage_multiplier` missing.

- [ ] **Step 3: Implement**

In `block.gd` beside the bookkeeping fields:

```gdscript
# Reform: turning to face a flanker while engaged (spec 2026-09-23).
var reform_left := 0.0                 # seconds left; > 0 means disordered
var reform_from := 0.0                 # facing when it began, for the view
var reform_target_id := -1

func reforming() -> bool:
	return reform_left > 0.0
```

In `battle_sim.gd`:

1. `order_attack`:

```gdscript
func order_attack(b: Block, target: Block) -> void:
	b.order = Block.OrderType.ATTACK
	b.target_id = target.id
	b.braced = false
	b.hold_time = 0.0
	# Turning on a flanker while engaged is a reform, not a pivot — and asking
	# again (the AI re-issues every 0.4 s) does not start it over.
	if not b.reforming() and contacts_of(b).has(target) and _arc(b, target.pos) != "front":
		b.reform_left = float(b.stats()["reform_time"])
		b.reform_from = b.facing
		b.reform_target_id = target.id
		_log("%s %s reforms to face a flank attack" % [_side_name(b.side), b.stats()["name"].to_lower()])
```

2. `order_withdraw`: add `_cancel_reform(b)` at its end. In `_resolve_status`, in the block that sets `b.routing = true`, add `_cancel_reform(b)`.

3. New functions (after the lock section):

```gdscript
# --------------------------------------------------------------------- reform

func _cancel_reform(b: Block) -> void:
	b.reform_left = 0.0
	b.reform_target_id = -1

func reform_facing(b: Block) -> float:
	var target := block_by_id(b.reform_target_id)
	if target == null or not target.alive():
		return b.facing
	return (target.pos - b.pos).angle()

func damage_multiplier(b: Block) -> float:
	return float(GameConfig.combat["reform_damage"]) if b.reforming() else 1.0

## Count reforms down; the one that finishes turns its block to face the
## target, and every lock it is the target of re-reads which face was struck.
func _tick_reforms(dt: float) -> void:
	for b in blocks:
		if not b.reforming():
			continue
		b.reform_left -= dt
		if b.reform_left > 0.0:
			continue
		b.reform_left = 0.0
		b.facing = reform_facing(b)
		b.reform_target_id = -1
		for lock in locks_of(b):
			if lock.target == b:
				lock.face = Contact.face_of(b, lock.initiator.pos)
```

4. In `step()`, call `_tick_reforms(dt)` right after the `for lock in locks: lock.settle(dt)` loop.

5. In `_move`, as the first line after the stats/speed setup: `if b.reforming(): b.charge_run = 0.0; return` (two statements on separate lines).

6. In `_seat`, a reforming block does not turn: guard each `turn_toward` call with `if not i.reforming():` / `if not t.reforming():`, and a reforming initiator does not slide (`if lock.loser() != i and not i.reforming():`).

7. In `_resolve_melee`, multiply the attacker's dps: `var dps: float = a.stats()["melee_dps"] * GameConfig.supply_multiplier(a.supply) * damage_multiplier(a)`.

- [ ] **Step 4: Run the suite and every suite**

`-- contact` → all `ok`; all suites (the AI now reforms against flank attacks in scenario battles; the clock and withdrawal claims must still hold). Tuning rules as before (this task's values: `reform_time`, `reform_damage`).

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/block.gd game/scripts/sim/battle_sim.gd game/tests/test_contact.gd
```
Suggested message: `Battle: a flanked block reforms to face its attacker after a delay`

---

### Task 6: Drawing the reform, and the tags

**Files:**
- Modify: `game/scripts/ui/battle_view.gd`, `game/tests/test_battle_shell.gd`

**Interfaces:**
- Consumes: `Block.reforming/reform_left/reform_from`, `BattleSim.reform_facing/push_state`.

- [ ] **Step 1: Write the failing test**

In `game/tests/test_battle_shell.gd`, add `_test_reform_shows(tree)` to `run()` after `_test_battle_view(tree)` and append:

```gdscript
func _test_reform_shows(tree: SceneTree) -> void:
	print("\nBattleView names a reform and a push")
	var host := Control.new()
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := BattleSim.new()
	sim.setup(terrain, Rect2(10, 10, 220, 160))
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	var p := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(120, 90), 0.0)
	var flank := sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(120, 50), PI / 2.0)
	sim.order_hold(p)
	sim.order_attack(flank, p)
	t.run_for(sim, 3.0)
	sim.order_attack(p, flank)
	var view := BattleView.new()
	host.add_child(view)
	view.open(terrain, sim, false)
	view.selection = [p] as Array[Block]
	view._process(0.1)
	t.check("the tag reads REFORMING", view._block_tag(p) == "REFORMING", view._block_tag(p))
	t.check("the tooltip says how long is left", view._block_state(p).begins_with("reforming ("),
		view._block_state(p))
	tree.root.remove_child(host)
	host.free()
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_shell`
Expected: FAIL — the tag reads FIGHTING.

- [ ] **Step 3: Implement**

In `battle_view.gd`:

1. `_draw_block`: first lines of the function body:

```gdscript
	if b.reforming():
		_draw_reform(b, z)
		return
```

2. Add after `_draw_block`:

```gdscript
## A reform, drawn: the ranks open into loose marks, the cluster wheels from
## its old facing to the new one (ease in-out), and closes up again; a ring
## counts the time down. The sim's facing only flips at the end.
func _draw_reform(b: Block, z: float) -> void:
	var total := maxf(float(b.stats()["reform_time"]), 0.01)
	var t := clampf(1.0 - b.reform_left / total, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var angle := lerp_angle(b.reform_from, sim.reform_facing(b), eased)
	var loose := sin(t * PI) * 4.0
	var d: float = b.depth()
	var w: float = b.frontage()
	var col := ThemeColors.side(b.side)
	var ranks := 3
	var files := 6
	draw_set_transform(_w2s(b.pos), angle, Vector2(z, z))
	for r in ranks:
		for f in files:
			var base := Vector2((float(r) + 0.5) / float(ranks) * d - d * 0.5,
				(float(f) + 0.5) / float(files) * w - w * 0.5)
			var jitter := Vector2(sin(float(b.id * 13 + r * 7 + f * 3)),
				cos(float(b.id * 5 + r * 11 + f * 17))) * loose
			draw_rect(Rect2(base + jitter - Vector2(1.5, 1.5), Vector2(3, 3)), col.lightened(0.3), true)
	draw_line(Vector2(d * 0.5 + loose, -w * 0.5), Vector2(d * 0.5 + loose, w * 0.5),
		col.lightened(0.6) * Color(1, 1, 1, 0.5), 1.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var at := _w2s(b.pos)
	var radius := (maxf(d, w) * 0.5 + 6.0) * z
	draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * t, 32, ThemeColors.ACCENT, 2.0)
	if selection.has(b):
		draw_arc(at, radius + 4.0, 0.0, TAU, 32, ThemeColors.TEXT, 1.5)
```

3. `_block_tag`: before the `if sim.is_engaged(b):` line add `if b.reforming(): return "REFORMING"` (two lines).

4. `_block_state`: as the second check (after ROUTING) add:

```gdscript
	if b.reforming():
		return "reforming (%.1fs)" % b.reform_left
```

and at the end of the engaged branch, before `return text`, add:

```gdscript
		match sim.push_state(b):
			1: text += " — pushing"
			-1: text += " — giving ground"
```

- [ ] **Step 4: Run tests and a windowed smoke**

`-- battle_shell` → all `ok`; all suites. Then write a scratch scene script (delete it afterwards) that hosts a `BattleView` on the flanked fixture above, orders the reform, and runs windowed for 4 s with `$G --path game --quit-after 240 <scratch scene>`; the output must contain no errors. Report what you saw in the log; the look is play-tested by the user.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/ui/battle_view.gd game/tests/test_battle_shell.gd
```
Suggested message: `Battle view: draw the reform and say who is pushing`

---

### Task 7: Balance check, docs, build

**Files:**
- Modify: `README.md` (the combat prototype section and its trade table), `game/tests/test_combat.gd` only where a *measured* number is printed (never an assertion)

- [ ] **Step 1: Full run and re-measure**

Run all suites. Record the printed measurements (hill/bridge trades, the Ford line counts, East Hill vs Southfield). Every check must pass; if any claim fails here, stop and report with the output.

- [ ] **Step 2: README**

In the "## The combat prototype" section, after the "Three rules were needed…" list, add:

```markdown
**Contact.** Blocks that touch lock together. The attacker is pulled flush
against the face it struck — front to front, both square up; on a flank or the
rear only the attacker turns, so the hit stays a flank hit. The side dealing
more damage through the contact pushes the other back, slowly (up to 6 u/s),
and a loser with a river, a cliff or a friend behind it cannot give ground.
Only a block that is winning can walk out with a Move; anyone else leaves by
Withdraw, by routing, or not at all. Blocks turn at a rate (infantry 90°/s)
and pivot before they walk; friendly blocks are solid. Ordering a flanked block
to attack its flanker starts a **reform**: about two seconds disordered at half
damage, still taking the flank hit, before it faces the new enemy — and
whoever was in front is then on its flank.
```

Update the trade table and the Ford sentence with the re-measured numbers from Step 1.

- [ ] **Step 3: Build**

Run the Windows build (`tools/build-windows.ps1 -Godot <the _console.exe>`) and smoke the exe with `--quit-after 300`; the output must be only the engine banner.

- [ ] **Step 4: Stage**

```bash
git add README.md docs/superpowers/plans/2026-09-23-battle-contact.md docs/superpowers/specs/2026-09-23-battle-contact-design.md
```
Suggested message: `Battle contact: docs and re-measured numbers`

**Implementation notes:** the push-tuning history (why `push_per_dps`,
`push_deadband`, `push_smoothing` and `pivot_angle` ended up where they did,
and how narrow the green region is) lives in `.superpowers/sdd/progress.md`
under "Battle contact ledger", not duplicated here.
