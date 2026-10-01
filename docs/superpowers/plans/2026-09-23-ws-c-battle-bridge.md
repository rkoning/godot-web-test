# WS-C Battle Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hostile stacks that meet on the campaign graph fight: the combat prototype's real-time battle for fights the player is in, a visible-ratio threshold auto-resolve for trivial ones, and a seeded battle stub for AI-vs-AI — with results written back to the stacks as lost regiments and a one-hop retreat.

**Architecture:** Pure sim code in `game/scripts/sim/battle/` (`BattleBridge` turns a campaign battle into a `BattleSim` and its result back into stack changes; `AutoResolve` is the ratio and the stub) driven by `EngagementPhase`, which WS-C owns. The battle screen is extracted from `game_root.gd` into a reusable `BattleView` control; the combat prototype hosts it as a child, and the campaign hosts it through `CampaignRoot.set_overlay` from a new WS-C map layer, `BattleLayer`.

**Tech Stack:** Godot 4.5 GDScript (CI), headless test runner (`tests/run_tests.gd`, one suite per file), on top of Phase 0 + WS-A (branch `ws-a-logistics`).

## Global Constraints

- Every simulation class is `RefCounted`, rendering-free, deterministic; the only RNG is `World.rng`. `AutoResolve.winner` consumes exactly one `world.rng.randf()` per call, always, so a run replays identically.
- Every tunable number lives in `game/scripts/sim/game_config.gd` as a `static var` dictionary (`GameConfig.battle_bridge`, added in Task 1); logic never hardcodes a number.
- Supply scale: campaign `Stack.supply` is 0..100, battle `Army.supply` is 0..1. The bridge divides by 100 in exactly one place (`BattleBridge.to_armies`). Never mix them.
- Battles stay 60–90 s, **4–8 blocks a side**, four orders. A stack fields at most `battle_bridge.max_blocks` (8) regiments; the rest are reserve and are never lost in a played battle.
- Design §4: no auto-resolve on a non-trivial fight the player is in. Threshold auto-resolve only, only in the player's favour, the ratio shown, and it can rarely fail.
- Frozen classes may only gain the one field this plan lists: `Stack.retreat_to: int`. `World.pending_battles` already exists; WS-C writes its entries (Task 1 documents the shape).
- WS-C owns: `game/scripts/sim/battle/`, `phases/engagement_phase.gd`, `ui/battle_view.gd`, `ui/layers/battle_layer.gd`, `tests/test_battle_bridge.gd`, `tests/test_battle_shell.gd`. Shared files it touches, each with the exact edit given here: `game_config.gd` (append one dict), `stack.gd` (one field), `campaign_root.gd` (one `LAYERS` line and one `_tables()` line — the only campaign_root edits), `game_root.gd` (Task 5: delegates its battle screen to `BattleView`), `README.md`, the workstreams plan.
- WS-A's files are not edited. `MovementPhase` already clears `world.pending_battles` and appends `{attacker, site_id, from_site}` for each march that stopped on an enemy; `EngagementPhase` runs right after it in the same End Turn.
- Tests: `cd game && godot --headless --script tests/run_tests.gd -- battle_bridge` (one suite) or no argument (all). CI runs Godot 4.5-stable; use no API newer than 4.5. Locally the binary is `K:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` (call it `$G` below). New `class_name` scripts need one `$G --headless --path game --import` before the runner sees them; stage the generated `.gd.uid` files.
- Git: never commit or push; stage with `git add` and leave a suggested message; never stage `game/icon.svg.import`. The combat suite must stay at 87 checks and every other suite must stay green.

---

## File map

| File | Responsibility |
| --- | --- |
| `game/scripts/sim/battle/battle_bridge.gd` | Find the player's side, pick fielded regiments, Stack → Army, start a `BattleSim`, write a result back (losses, retreat, removal). |
| `game/scripts/sim/battle/auto_resolve.gd` | Strength ratio, the trivial threshold, the seeded winner roll, and `resolve` (the battle stub). |
| `game/scripts/sim/phases/engagement_phase.gd` | Collect this turn's battles (arrivals and standoffs), resolve AI and trivial ones, leave the player's real fights waiting. |
| `game/scripts/ui/battle_view.gd` | The battle screen as a reusable Control: draw, input, orders HUD, clock, result panel with host-supplied actions. |
| `game/scripts/ui/game_root.gd` | Combat prototype: strategic zoom only; hosts a `BattleView` for the battle. |
| `game/scripts/ui/layers/battle_layer.gd` | Campaign: marks waiting battles, "Fight battle" button, opens/closes `BattleView` via `set_overlay`, applies the result. |
| `game/tests/test_battle_bridge.gd` | Engagement, bridge, result, auto-resolve, the hill acceptance fight. |
| `game/tests/test_battle_shell.gd` | `BattleView` headless, the combat scene still builds, the campaign battle flow end to end. |

`World.pending_battles` entry after `EngagementPhase` (the one shape every file uses):

```gdscript
{
	"attacker": Stack,      # the stack that marched in (or the non-holder in a standoff)
	"defender": Stack,      # the stack it found there
	"site_id": int,
	"from_site": int,       # where the attacker came from; a neighbour site if unknown
	"ratio": float,         # AutoResolve.ratio(player's stack, the other) — attacker/defender when no player
	"sides": Array,         # [Stack on Side.PLAYER, Stack on Side.ENEMY], set by BattleBridge.sides()
}
```

---

### Task 1: Config, the stack field, and battle collection

**Files:**
- Modify: `game/scripts/sim/game_config.gd` (append after `logistics`)
- Modify: `game/scripts/sim/world/stack.gd` (one field)
- Modify: `game/scripts/ui/campaign_root.gd` (`_tables()`, one line)
- Modify: `game/scripts/sim/phases/engagement_phase.gd`
- Create: `game/scripts/sim/battle/battle_bridge.gd` (the side helpers only)
- Create: `game/tests/test_battle_bridge.gd`

**Interfaces:**
- Consumes: `World.stacks_at`, `World.hostile`, `World.hostile_presence`, `WorldGraph.edges`, `Holdings.site_owner`.
- Produces:
  - `GameConfig.battle_bridge: Dictionary`
  - `Stack.retreat_to: int` (-1 = did not retreat)
  - `EngagementPhase.collect(world: World) -> Array` — battle dicts in the shape above, minus `ratio` (added Task 4) and `sides`.
  - `EngagementPhase.run(world: World) -> void` — for now: `world.pending_battles = collect(world)`.
  - `BattleBridge.player_stack(world: World, battle: Dictionary) -> Stack` — the player's stack in the battle, or null.
  - `BattleBridge.other(battle: Dictionary, s: Stack) -> Stack` — the opponent of `s`.
  - `BattleBridge.sides(world: World, battle: Dictionary) -> Array` — `[player-side Stack, enemy-side Stack]`: the player's stack is Side.PLAYER; with no player in it, the attacker is. Also stores the array in `battle["sides"]`.

- [ ] **Step 1: Write the failing tests**

Create `game/tests/test_battle_bridge.gd`:

```gdscript
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: parse errors / FAIL — `GameConfig.battle_bridge`, `EngagementPhase.collect` and `BattleBridge` do not exist.

- [ ] **Step 3: Implement**

Append to `game/scripts/sim/game_config.gd` after the `logistics` dictionary:

```gdscript

## Battle bridge (Design §4, WS-C): campaign stacks in the real-time battle,
## threshold auto-resolve, and the AI battle stub. Design §10 leaves the ratio
## and the hidden-failure rate open; these are the starting values.
static var battle_bridge := {
	"max_blocks": 8,                   # a stack fields at most this many regiments; the rest are reserve
	"approach_distance": 60.0,         # the attacker deploys this far from the site, toward where it came from
	"auto_resolve_ratio": 3.0,         # player strength / enemy strength at or above this: no battle
	"hidden_failure_chance": 0.05,     # a trivial fight still goes wrong this often
	"auto_attrition": 0.10,            # share of its regiments the winner of an auto-resolve loses
	"auto_loser_losses": 0.5,          # share the loser of an auto-resolve loses (at least one)
	"auto_supply_cost": 5.0,           # supply the winner of an auto-resolve spends
	"retreat_supply_cost": 10.0,       # supply a retreating loser spends
}
```

In `game/scripts/sim/world/stack.gd`, after `var hunger := 0 ...`, add:

```gdscript
var retreat_to := -1              # site a lost battle sent this stack back to, -1 = none (WS-C)
```

In `game/scripts/ui/campaign_root.gd` `_tables()`, after `"logistics": GameConfig.logistics,` add:

```gdscript
		"battle_bridge": GameConfig.battle_bridge,
```

Create `game/scripts/sim/battle/battle_bridge.gd`:

```gdscript
class_name BattleBridge
extends RefCounted

## WS-C: a campaign battle (an entry of `World.pending_battles`) becomes the
## combat prototype's `BattleSim`, and the sim's result becomes lost regiments
## and a retreat. No rules of the fight live here — only the translation.

## The player's stack in this battle, or null when the player is not in it.
static func player_stack(world: World, battle: Dictionary) -> Stack:
	for key in ["attacker", "defender"]:
		var s: Stack = battle[key]
		if world.nation(s.nation_id).is_player:
			return s
	return null

## The opponent of `s` in this battle.
static func other(battle: Dictionary, s: Stack) -> Stack:
	return battle["defender"] if s == battle["attacker"] else battle["attacker"]

## [Stack on Side.PLAYER, Stack on Side.ENEMY]. The player's stack is always
## Side.PLAYER so the view's colours and controls are the player's; with no
## player in the fight, the attacker is. Remembered on the battle so the result
## maps back onto the same stacks the sim was built from.
static func sides(world: World, battle: Dictionary) -> Array:
	var mine := player_stack(world, battle)
	var first: Stack = mine if mine != null else battle["attacker"]
	var out: Array = []
	out.resize(2)
	out[GameConfig.Side.PLAYER] = first
	out[GameConfig.Side.ENEMY] = other(battle, first)
	battle["sides"] = out
	return out
```

Replace `game/scripts/sim/phases/engagement_phase.gd`:

```gdscript
class_name EngagementPhase
extends RefCounted

## WS-C. Hostile stacks on one site fight. MovementPhase has already recorded
## every march that stopped on an enemy; this turns those, and any standoff
## left from an earlier turn, into battles — at most one per site per turn.

static func run(world: World) -> void:
	world.pending_battles = collect(world)

## This turn's battles, arrivals first in the order they happened, then
## standoffs (hostile stacks still sharing a site because the player did not
## fight last turn). A standoff is found again every turn until somebody leaves
## or somebody wins, so ending a turn never silently cancels a battle.
static func collect(world: World) -> Array:
	var out: Array = []
	var seen := {}
	for p in world.pending_battles:
		var site_id := int(p["site_id"])
		if seen.has(site_id):
			continue
		var b := _battle_at(world, site_id, p.get("attacker"), int(p.get("from_site", -1)))
		if not b.is_empty():
			out.append(b)
			seen[site_id] = true
	for s in _by_id(world.stacks):
		if seen.has(s.site_id) or not world.hostile_presence(s.site_id, s.nation_id):
			continue
		var b := _battle_at(world, s.site_id, null, -1)
		if not b.is_empty():
			out.append(b)
			seen[s.site_id] = true
	return out

static func _battle_at(world: World, site_id: int, arrived: Stack, from_site: int) -> Dictionary:
	var here := _by_id(world.stacks_at(site_id))
	var attacker: Stack = null
	var defender: Stack = null
	if arrived != null:
		# The marcher may have been folded into a friend by Movement.merge_all;
		# the survivor of that nation on this site carries its regiments.
		attacker = arrived if (world.stacks.has(arrived) and arrived.site_id == site_id) \
			else _first_of(here, arrived.nation_id)
		if attacker != null:
			defender = _first_hostile(world, here, attacker.nation_id)
	else:
		var owner := Holdings.site_owner(world, world.graph.sites[site_id])
		defender = _first_of(here, owner)
		if defender == null or _first_hostile(world, here, defender.nation_id) == null:
			defender = here[0] if here.size() > 0 else null
		if defender != null:
			attacker = _first_hostile(world, here, defender.nation_id)
	if attacker == null or defender == null:
		return {}
	if from_site < 0 or world.graph.edge_between(site_id, from_site) == null:
		from_site = _approach(world, site_id, attacker.nation_id)
	return {
		"attacker": attacker,
		"defender": defender,
		"site_id": site_id,
		"from_site": from_site,
	}

## A neighbour to come from when nobody recorded one: the first by id with no
## enemy of the attacker on it, else simply the first.
static func _approach(world: World, site_id: int, nation_id: int) -> int:
	var best := -1
	var fallback := -1
	for e in world.graph.edges:
		if e.a != site_id and e.b != site_id:
			continue
		var n := e.other(site_id)
		if fallback < 0 or n < fallback:
			fallback = n
		if not world.hostile_presence(n, nation_id) and (best < 0 or n < best):
			best = n
	return best if best >= 0 else fallback

static func _first_of(stacks: Array, nation_id: int) -> Stack:
	for s in stacks:
		if s.nation_id == nation_id:
			return s
	return null

static func _first_hostile(world: World, stacks: Array, nation_id: int) -> Stack:
	for s in stacks:
		if world.hostile(s.nation_id, nation_id):
			return s
	return null

static func _by_id(stacks: Array) -> Array:
	var out: Array = stacks.duplicate()
	out.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	return out
```

- [ ] **Step 4: Import, then run the suite and everything**

Run: `$G --headless --path game --import` then `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: every check `ok`.
Run: `cd game && $G --headless --script tests/run_tests.gd`
Expected: `... 0 failed`. Nothing resolves a battle yet, so no WS-A behaviour changes.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/game_config.gd game/scripts/sim/world/stack.gd game/scripts/ui/campaign_root.gd game/scripts/sim/phases/engagement_phase.gd game/scripts/sim/battle/ game/tests/test_battle_bridge.gd game/tests/test_battle_bridge.gd.uid
```
Suggested message: `WS-C: collect campaign battles from arrivals and standoffs`

---

### Task 2: Stack → Army, and starting the battle

**Files:**
- Modify: `game/scripts/sim/battle/battle_bridge.gd`
- Modify: `game/tests/test_battle_bridge.gd`

**Interfaces:**
- Consumes: Task 1's `sides`, `Scenarios.start_battle(terrain, player: Army, enemy: Army, crop) -> BattleSim`, `Army.new(side, pos, roster: Array[int], supply: float)`.
- Produces:
  - `BattleBridge.fielded(s: Stack) -> Array[int]` — the roles that take the field, at most `max_blocks`, taken round-robin INFANTRY, CAVALRY, ARCHERS so the mix survives the cap.
  - `BattleBridge.to_armies(world: World, terrain: Terrain, battle: Dictionary) -> Array[Army]` — `[Side.PLAYER army, Side.ENEMY army]`; defender at the site, attacker `approach_distance` back toward `from_site` (rotated off impassable ground), supply ÷ 100.
  - `BattleBridge.start(world: World, terrain: Terrain, battle: Dictionary, crop := Vector2.ZERO, ai_plays_player := false) -> BattleSim` — behaviours: attacker side `"attacker"`, defender side `"defender"`, except the player's side is `""` (human) unless `ai_plays_player`. Started immediately when no human is playing; otherwise a human defender gets the pre-arrange phase as in the prototype.

- [ ] **Step 1: Write the failing tests**

Add to `run()` in `test_battle_bridge.gd`, after `_test_sides()`:

```gdscript
	_test_fielded()
	_test_to_armies()
	_test_start()
	_test_hill_beats_plain()
```

Append:

```gdscript
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: FAIL — `BattleBridge.fielded` / `to_armies` / `start` not found.

- [ ] **Step 3: Implement**

Append to `battle_bridge.gd`:

```gdscript
const ROLE_ORDER := [GameConfig.Role.INFANTRY, GameConfig.Role.CAVALRY, GameConfig.Role.ARCHERS]

## The regiments that take the field: all of them up to `max_blocks`, and past
## that one of each role in turn, so a big stack's reserve does not strip it of
## its only cavalry. The rest stay in reserve and are never lost in the battle.
static func fielded(s: Stack) -> Array[int]:
	var cap := int(GameConfig.battle_bridge["max_blocks"])
	var pools := {}
	for role in ROLE_ORDER:
		pools[role] = s.regiments.count(role)
	var out: Array[int] = []
	while out.size() < cap:
		var took := false
		for role in ROLE_ORDER:
			if out.size() >= cap:
				break
			if pools[role] > 0:
				pools[role] -= 1
				out.append(role)
				took = true
		if not took:
			break
	return out

## [Side.PLAYER army, Side.ENEMY army]. The defender stands on the site; the
## attacker arrives `approach_distance` back along the edge it marched in on,
## turned off water or cliffs if the straight line lands there. Supply crosses
## scales here and nowhere else: campaign 0..100, battle 0..1.
static func to_armies(world: World, terrain: Terrain, battle: Dictionary) -> Array[Army]:
	var side_stacks := sides(world, battle)
	var site: Site = world.graph.sites[battle["site_id"]]
	var dir := Vector2.RIGHT
	var from_id := int(battle["from_site"])
	if from_id >= 0:
		var d: Vector2 = world.graph.sites[from_id].pos - site.pos
		if d.length_squared() > 0.01:
			dir = d.normalized()
	var reach := float(GameConfig.battle_bridge["approach_distance"])
	var attack_pos := site.pos + dir * reach
	for turn in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]:
		if not terrain.is_blocked(attack_pos, GameConfig.Role.INFANTRY):
			break
		attack_pos = site.pos + dir.rotated(deg_to_rad(turn)) * reach

	var out: Array[Army] = []
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		var s: Stack = side_stacks[side]
		var attacking: bool = s == battle["attacker"]
		var army := Army.new(side, attack_pos if attacking else site.pos, fielded(s), s.supply / 100.0)
		army.label = s.label
		army.moved_this_turn = attacking
		out.append(army)
	return out

## Build the battle. The attacker's side runs the attacker AI and the
## defender's the defender AI, except a side the human plays; `ai_plays_player`
## hands that side to the AI too (headless tests, and a future "let the general
## fight it"). A human defender gets the prototype's pre-arrange phase.
static func start(world: World, terrain: Terrain, battle: Dictionary,
		crop := Vector2.ZERO, ai_plays_player := false) -> BattleSim:
	var armies := to_armies(world, terrain, battle)
	var sim := Scenarios.start_battle(terrain, armies[GameConfig.Side.PLAYER],
		armies[GameConfig.Side.ENEMY], crop)
	var side_stacks: Array = battle["sides"]
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.behavior[side] = "attacker" if side_stacks[side] == battle["attacker"] else "defender"
	var human := player_stack(world, battle) != null and not ai_plays_player
	if human:
		sim.behavior[GameConfig.Side.PLAYER] = ""
	else:
		sim.started = true
	return sim
```

- [ ] **Step 4: Run tests**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: all `ok`, and the printed line `East Hill: trade … Southfield: trade …` shows the hill ahead. If the hill check fails, do not loosen it: print both sims' `result` and block positions, and check the attacker placement (`approach_distance`, the rotation fallback) and that the defender deployed on the hill feature (`terrain.feature_at(site.pos)`), before touching anything else.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/battle/battle_bridge.gd game/tests/test_battle_bridge.gd
```
Suggested message: `WS-C: turn campaign stacks into a battle, capped at eight blocks a side`

---

### Task 3: Writing the result back, and retreat

**Files:**
- Modify: `game/scripts/sim/battle/battle_bridge.gd`
- Modify: `game/tests/test_battle_bridge.gd`

**Interfaces:**
- Consumes: `BattleSim.result` (`{reason, seconds, holder: side|-1, feature, rows: [{side, role, fate, ...}], losses}`), `Pathing.nearest_depot(world, from, nation_id, with_stock := true) -> {site_id, hops, sites: Array[int], edges, factor}` or `{}`, `Orders.clear(world, s)`, `Holdings.is_friendly`.
- Produces:
  - `BattleBridge.apply_result(world: World, sim: BattleSim, battle: Dictionary) -> Dictionary` — `{winner: Stack|null, loser: Stack|null, lost: {nation_id: int}, retreat_to: int, text: String}`. Destroyed blocks remove regiments of their role; fled, routing, withdrew and held blocks survive; reserves are untouched. The field's holder wins (nobody → the defender). The loser retreats; a stack with no regiments is removed. Erases `battle` from `world.pending_battles`.
  - `BattleBridge.conclude(world: World, battle: Dictionary, winner: Stack, lost: Dictionary, how: String) -> Dictionary` — the shared tail (remove losses by count, drop empty stacks, retreat the loser, log, erase) that Task 4's auto-resolve reuses. `lost` is `{Stack: Array[int] roles}`.
  - `BattleBridge.retreat(world: World, s: Stack, battle: Dictionary) -> int` — moves `s` one hop and returns the site, or removes it ("surrounded") and returns -1. Attacker: back to `from_site` if no enemy is there. Otherwise the first hop toward its nearest depot (`Pathing.nearest_depot(..., false)`), else the lowest-id neighbour with no enemy on it, friendly ground first. Costs `retreat_supply_cost` supply, clears orders, sets `Stack.retreat_to`.

- [ ] **Step 1: Write the failing tests**

Add to `run()` after `_test_hill_beats_plain()`:

```gdscript
	_test_losses_by_role()
	_test_loser_retreats_toward_depot()
	_test_repulsed_attacker_goes_back()
	_test_surrounded_loser_is_lost()
	_test_wiped_out_stack_is_removed()
```

Append:

```gdscript
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: FAIL — `apply_result` not found.

- [ ] **Step 3: Implement**

Append to `battle_bridge.gd`:

```gdscript
## Write a finished battle back to the campaign. Destroyed blocks cost a
## regiment of their role; a block that fled, routed, withdrew or held lives
## (Design §4: retreat costs position and supply, not regiments). Whoever
## holds the field wins; if nobody does, the defender kept its ground.
static func apply_result(world: World, sim: BattleSim, battle: Dictionary) -> Dictionary:
	# Not battle.get("sides", sides(...)): the default would be evaluated (and
	# stored) even when the battle already remembers its sides.
	var side_stacks: Array = battle["sides"] if battle.has("sides") else sides(world, battle)
	var lost := {}
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		var roles: Array[int] = []
		for row in sim.result.get("rows", []):
			if int(row["side"]) == side and str(row["fate"]) == "destroyed":
				roles.append(int(row["role"]))
		lost[side_stacks[side]] = roles
	var holder := int(sim.result.get("holder", -1))
	var winner: Stack = side_stacks[holder] if holder >= 0 else battle["defender"]
	return conclude(world, battle, winner, lost,
		"after %0.0fs (%s)" % [float(sim.result.get("seconds", 0.0)), str(sim.result.get("reason", ""))])

## The shared end of every battle, played or auto-resolved: regiments come off
## by role, empty stacks go, the loser falls back, one log line, and the
## battle leaves `pending_battles`.
static func conclude(world: World, battle: Dictionary, winner: Stack, lost: Dictionary, how: String) -> Dictionary:
	var loser := other(battle, winner)
	var by_nation := {}
	for s in lost:
		var n := 0
		for role in lost[s]:
			var i: int = s.regiments.rfind(role)
			if i >= 0:
				s.regiments.remove_at(i)
				n += 1
		by_nation[s.nation_id] = int(by_nation.get(s.nation_id, 0)) + n
	var site_name: String = world.graph.sites[battle["site_id"]].name
	var text := "Battle at %s %s: %s holds, %s falls back (losses %d / %d)" % [
		site_name, how, winner.label, loser.label,
		int(by_nation.get(winner.nation_id, 0)), int(by_nation.get(loser.nation_id, 0)),
	]
	var retreat_site := -1
	for s in [winner, loser]:
		if s.size() == 0 and world.stacks.has(s):
			world.remove_stack(s)
			text += "; %s is destroyed" % s.label
	if world.stacks.has(loser):
		retreat_site = retreat(world, loser, battle)
		if retreat_site < 0:
			text += "; %s had nowhere to go and is lost" % loser.label
	world.record(text)
	world.pending_battles.erase(battle)
	return {
		"winner": winner if world.stacks.has(winner) else null,
		"loser": loser,
		"lost": by_nation,
		"retreat_to": retreat_site,
		"text": text,
	}

## One hop out of the fight, or -1 (and the stack removed) when every way out
## is held by the enemy. See the Interfaces block for the order of preference.
static func retreat(world: World, s: Stack, battle: Dictionary) -> int:
	var site_id := int(battle["site_id"])
	var to := -1
	var back := int(battle.get("from_site", -1))
	if s == battle["attacker"] and back >= 0 and not world.hostile_presence(back, s.nation_id):
		to = back
	if to < 0:
		var nd := Pathing.nearest_depot(world, site_id, s.nation_id, false)
		if not nd.is_empty() and nd["sites"].size() > 0:
			var hop: int = nd["sites"][0]
			if not world.hostile_presence(hop, s.nation_id):
				to = hop
	if to < 0:
		var friendly := -1
		var any := -1
		for e in world.graph.edges:
			if e.a != site_id and e.b != site_id:
				continue
			var n := e.other(site_id)
			if world.hostile_presence(n, s.nation_id):
				continue
			if Holdings.is_friendly(world, world.graph.sites[n], s.nation_id) and (friendly < 0 or n < friendly):
				friendly = n
			if any < 0 or n < any:
				any = n
		to = friendly if friendly >= 0 else any
	if to < 0:
		world.remove_stack(s)
		return -1
	s.site_id = to
	s.retreat_to = to
	s.supply = maxf(0.0, s.supply - float(GameConfig.battle_bridge["retreat_supply_cost"]))
	Orders.clear(world, s)
	return to
```

- [ ] **Step 4: Run tests**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: all `ok`.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/battle/battle_bridge.gd game/tests/test_battle_bridge.gd
```
Suggested message: `WS-C: battle results cost regiments by role and send the loser back a hop`

---

### Task 4: Auto-resolve, and EngagementPhase deciding what is played

**Files:**
- Create: `game/scripts/sim/battle/auto_resolve.gd`
- Modify: `game/scripts/sim/phases/engagement_phase.gd`
- Modify: `game/tests/test_battle_bridge.gd`

**Interfaces:**
- Consumes: `Stack.strength()` (size × quality × supply multiplier), `BattleBridge.player_stack/other/conclude`.
- Produces:
  - `AutoResolve.ratio(a: Stack, b: Stack) -> float` — `a.strength() / max(b.strength(), 0.001)`.
  - `AutoResolve.trivial(world: World, a: Stack, b: Stack) -> bool` — `ratio(a, b) >= auto_resolve_ratio`. Pure; the hidden failure is in the roll.
  - `AutoResolve.winner(world: World, a: Stack, b: Stack) -> Stack` — one `world.rng.randf()` per call. Trivial for either side: the stronger wins unless the roll is under `hidden_failure_chance`. Otherwise `a` wins with probability `strength(a) / (strength(a) + strength(b))`.
  - `AutoResolve.resolve(world: World, battle: Dictionary) -> Dictionary` — the battle stub: winner rolled from attacker vs defender, winner loses `round(size × auto_attrition)`, loser `max(1, round(size × auto_loser_losses))`, winner spends `auto_supply_cost` supply and its route; then `BattleBridge.conclude` with how = `"auto-resolved at ratio R"`. Returns `conclude`'s dictionary.
  - `EngagementPhase.run` final: AI-vs-AI → `resolve`; the player's side trivially stronger → `resolve`; otherwise the battle waits in `world.pending_battles` with `ratio` set (the player's stack over the other).

- [ ] **Step 1: Write the failing tests**

Add to `run()`:

```gdscript
	_test_ratio_and_threshold()
	_test_hidden_failure_rate()
	_test_ai_battles_resolve_on_end_turn()
	_test_player_trivial_auto_resolves()
	_test_player_real_fight_waits()
```

Append:

```gdscript
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

func _test_player_real_fight_waits() -> void:
	print("\nengagement: a real fight waits for the player, and is offered again")
	var w := t.bare_world()
	var hill := _site(w, "East Hill")
	var watch := _site(w, "Hilltop Watch")
	var a := w.add_stack(0, watch, _roster(4, 0, 0))
	var d := w.add_stack(1, hill, _roster(3, 0, 0))
	Orders.move(w, a, hill)
	TurnResolver.end_turn(w)
	t.check("one battle waits", w.pending_battles.size() == 1, str(w.pending_battles.size()))
	if w.pending_battles.size() != 1:
		return
	var b: Dictionary = w.pending_battles[0]
	t.near("its ratio is the player's over the enemy's", float(b["ratio"]),
		AutoResolve.ratio(a, d), 0.001)
	TurnResolver.end_turn(w)
	t.check("not fought: offered again next turn", w.pending_battles.size() == 1)
	Orders.move(w, a, watch)
	TurnResolver.end_turn(w)
	t.check("walking away ends it", w.pending_battles.is_empty())
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: FAIL — `AutoResolve` not found.

- [ ] **Step 3: Implement**

Create `game/scripts/sim/battle/auto_resolve.gd`:

```gdscript
class_name AutoResolve
extends RefCounted

## Design §4's threshold auto-resolve, and Appendix B's battle stub for fights
## no human plays. Everything random goes through `world.rng`, one roll per
## `winner` call, so a seeded run replays identically.

static func ratio(a: Stack, b: Stack) -> float:
	return a.strength() / maxf(b.strength(), 0.001)

## At or above the configured ratio the fight is not worth playing. Pure: the
## rare "should have been free" loss is rolled in `winner`, not here, so the UI
## can show this answer without spending randomness.
static func trivial(_world: World, a: Stack, b: Stack) -> bool:
	return ratio(a, b) >= float(GameConfig.battle_bridge["auto_resolve_ratio"])

static func winner(world: World, a: Stack, b: Stack) -> Stack:
	var roll := world.rng.randf()
	if trivial(world, a, b):
		return b if roll < float(GameConfig.battle_bridge["hidden_failure_chance"]) else a
	if trivial(world, b, a):
		return a if roll < float(GameConfig.battle_bridge["hidden_failure_chance"]) else b
	var sa := a.strength()
	var sb := b.strength()
	return a if roll < sa / maxf(sa + sb, 0.001) else b

## Resolve a battle without playing it. The winner pays attrition, supply and
## the rest of its move; the loser pays regiments and falls back.
static func resolve(world: World, battle: Dictionary) -> Dictionary:
	var att: Stack = battle["attacker"]
	var def: Stack = battle["defender"]
	var r := ratio(att, def)
	var mine := BattleBridge.player_stack(world, battle)
	if mine != null:
		r = ratio(mine, BattleBridge.other(battle, mine))
	var won := winner(world, att, def)
	var lost_side := BattleBridge.other(battle, won)
	var cfg := GameConfig.battle_bridge
	var lost := {
		won: _take(won, roundi(float(won.size()) * float(cfg["auto_attrition"]))),
		lost_side: _take(lost_side, maxi(1, roundi(float(lost_side.size()) * float(cfg["auto_loser_losses"])))),
	}
	won.supply = maxf(0.0, won.supply - float(cfg["auto_supply_cost"]))
	Orders.clear(world, won)
	return BattleBridge.conclude(world, battle, won, lost, "auto-resolved at ratio %.1f" % r)

## The last `n` regiments' roles — the ones `conclude` will take off.
static func _take(s: Stack, n: int) -> Array[int]:
	var out: Array[int] = []
	for i in mini(n, s.size()):
		out.append(s.regiments[s.size() - 1 - i])
	return out
```

Replace `run` in `engagement_phase.gd`:

```gdscript
## AI against AI is the battle stub; the player's side trivially stronger is
## auto-resolved in the open; every other fight the player is in waits in
## `pending_battles` for BattleLayer to put on screen.
static func run(world: World) -> void:
	var waiting: Array = []
	for battle in collect(world):
		var att: Stack = battle["attacker"]
		var def: Stack = battle["defender"]
		# An earlier resolution this turn may have moved or removed one of them.
		if not (world.stacks.has(att) and world.stacks.has(def)) or att.site_id != def.site_id:
			continue
		var mine := BattleBridge.player_stack(world, battle)
		if mine == null:
			AutoResolve.resolve(world, battle)
			continue
		var theirs := BattleBridge.other(battle, mine)
		battle["ratio"] = AutoResolve.ratio(mine, theirs)
		if AutoResolve.trivial(world, mine, theirs):
			AutoResolve.resolve(world, battle)
		else:
			waiting.append(battle)
	world.pending_battles = waiting
```

- [ ] **Step 4: Run tests, then every suite**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_bridge`
Expected: all `ok`.
Run: `cd game && $G --headless --script tests/run_tests.gd`
Expected: `0 failed`. Battles now really resolve, so a WS-A test that parks hostile stacks together (the scripted raider, The Siege, The March) may change. If one fails, read what it asserts: if it asserted "stacks sit together and nothing happens", that premise is gone; fix the fixture (put the nations at peace, or keep the stacks apart) rather than the rule, and say so in the report. Do not touch `auto_resolve_ratio` to make a WS-A test pass.

- [ ] **Step 5: Stage**

```bash
git add game/scripts/sim/battle/auto_resolve.gd game/scripts/sim/battle/auto_resolve.gd.uid game/scripts/sim/phases/engagement_phase.gd game/tests/test_battle_bridge.gd
```
Suggested message: `WS-C: threshold auto-resolve and the AI battle stub on End Turn`

---

### Task 5: Extract `BattleView` from the combat prototype

**Files:**
- Create: `game/scripts/ui/battle_view.gd`
- Modify: `game/scripts/ui/game_root.gd`
- Create: `game/tests/test_battle_shell.gd`

**Interfaces:**
- Consumes: `BattleSim`, `MapCamera` (`screen`, `zoom`, `fit`, `rescreen`, `zoom_at`, `pan`, `w2s`, `s2w`), `ThemeColors`, `NetConfig._query_param`.
- Produces `BattleView extends Control`:
  - `var sim: BattleSim`, `var terrain: Terrain`, `var touch: bool`
  - `var insets: Callable` — `() -> Vector2(top_px, bottom_px)` the host's own HUD covers; empty = none.
  - `var result_actions: Array[Dictionary]` — `[{label: String, action: Callable}]`, the result panel's buttons.
  - `func open(p_terrain: Terrain, p_sim: BattleSim, p_touch: bool) -> void`
  - `func fit() -> void`
  - `func result_shown() -> bool`
  - `static func terrain_texture(t: Terrain) -> ImageTexture` (cached per Terrain; `game_root` uses it too)
  - `static func detect_touch() -> bool` (`?input=touch|mouse` on the web, else the display server)
  - Steps the sim only while `is_visible_in_tree()`, so a hidden view is a paused battle.

This is a move, not a rewrite: the drawing, hit-testing and order code keeps its bodies. What changes is who owns the state.

- [ ] **Step 1: Write the failing test**

Create `game/tests/test_battle_shell.gd`:

```gdscript
extends RefCounted

## WS-C: the battle screen as a component. BattleView runs a sim and shows a
## result with the host's buttons; the combat prototype still builds on it; the
## campaign opens it over the map for a waiting battle and writes the result
## back (Task 6 adds that half).

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		t.check("a SceneTree root is available to host the scene", false)
		return
	_test_battle_view(tree)
	_test_combat_scene_builds(tree)

func _test_battle_view(tree: SceneTree) -> void:
	print("\nBattleView runs a battle and ends on the host's buttons")
	var host := Control.new()
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := t.arena(terrain)
	sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(620, 400), 0.0)
	sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(680, 400), PI)
	var view := BattleView.new()
	var pressed := [0]
	view.result_actions = [{"label": "Continue", "action": func(): pressed[0] += 1}]
	host.add_child(view)
	view.open(terrain, sim, false)
	view._process(0.5)
	t.check("the view advances its sim while visible", sim.time > 0.0, str(sim.time))
	var before := sim.time
	view.visible = false
	view._process(0.5)
	t.check("a hidden view is a paused battle", is_equal_approx(sim.time, before))
	view.visible = true
	sim._finish("test")
	view._process(0.0)
	t.check("a finished sim shows the result panel", view.result_shown())
	var buttons := view.find_children("*", "Button", true, false)
	var cont: Button = null
	for b in buttons:
		if b.text == "Continue" and b.is_visible_in_tree():
			cont = b
	t.check("the host's action is on the result panel", cont != null)
	if cont != null:
		cont.pressed.emit()
	t.check("pressing it calls the host", pressed[0] == 1)
	t.check("terrain_texture is cached per terrain",
		BattleView.terrain_texture(terrain) == BattleView.terrain_texture(terrain))
	tree.root.remove_child(host)
	host.free()

func _test_combat_scene_builds(tree: SceneTree) -> void:
	print("\nthe combat prototype still builds on BattleView")
	var packed := load("res://scenes/game.tscn") as PackedScene
	t.check("game.tscn loads", packed != null)
	if packed == null:
		return
	var root := packed.instantiate() as Control
	tree.root.add_child(root)
	var campaign: Campaign = root.campaign
	t.check("it opens on the strategic map", campaign != null and root.battle_view == null)
	root._begin_battle(campaign.armies[0], campaign.armies[1])
	t.check("a battle opens a BattleView", root.battle_view != null and root.battle_view.sim != null)
	t.check("with Replay and Back to map on its result panel",
		root.battle_view.result_actions.size() == 2)
	root._end_battle()
	t.check("Back to map closes it", root.battle_view == null and root.sim == null)
	tree.root.remove_child(root)
	root.free()
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_shell`
Expected: FAIL — `BattleView` not found.

- [ ] **Step 3: Create `battle_view.gd`**

Create `game/scripts/ui/battle_view.gd` with this frame, then paste the moved functions listed after it **verbatim** from the current `game_root.gd` (they compile unchanged because the names they use — `sim`, `camera`, `_font`, `_ack`, `_now`, `selection`, `hover_block`, `pending_order`, `touch`, `terrain`, `_w2s`, `_s2w`, `_hud`, `_press_screen`, `_box_to`, `_refresh_hud` — are all defined here):

```gdscript
class_name BattleView
extends Control

## The real-time battle screen, as a component: it owns a `BattleSim`, steps
## it, draws it, takes orders by mouse or finger, and ends on a result panel
## whose buttons belong to the host. The combat prototype hosts one as a
## child; the campaign hosts one through `CampaignRoot.set_overlay`.
##
## Hidden is paused: the sim only steps while the view is visible in the tree,
## so a host that peeks at its map just hides this.

const DT := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 8
const DRAG_THRESHOLD_PX := 10.0
const HUD_MARGIN := 8.0
const WIDE_SCREEN := 760.0

var terrain: Terrain
var sim: BattleSim
var touch := false
var insets := Callable()
var result_actions: Array[Dictionary] = []

var paused := false
var speed := 1.0
var _accum := 0.0
var camera := MapCamera.new()

var selection: Array[Block] = []
var hover_block: Block = null
var pending_order := ""
var _ack := {}
var hover_world := Vector2.ZERO

var _press_screen := Vector2.INF
var _press_moved := false
var _press_block: Block = null
var _box_to := Vector2.INF
var dragging_block: Block = null

var _touches := {}
var _gesture := false
var _gesture_dist := 0.0
var _gesture_mid := Vector2.ZERO
var _pan_button := -1
var _pan_moved := false

var _font: Font
var _hud := {}

static var _textures := {}           # Terrain -> ImageTexture

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_hud()

func open(p_terrain: Terrain, p_sim: BattleSim, p_touch: bool) -> void:
	terrain = p_terrain
	sim = p_sim
	touch = p_touch
	paused = false
	_accum = 0.0
	selection.clear()
	hover_block = null
	pending_order = ""
	_cancel_pointer()
	_hud["result"].visible = false
	_refresh_hud()
	fit()

func result_shown() -> bool:
	return _hud["result"].visible

## The rasterised terrain, shared by every view of the same Terrain.
static func terrain_texture(t: Terrain) -> ImageTexture:
	if not _textures.has(t):
		_textures[t] = _rasterise(t)
	return _textures[t]

static func detect_touch() -> bool:
	if OS.has_feature("web"):
		var forced := NetConfig._query_param("input")
		if forced == "touch":
			return true
		if forced == "mouse":
			return false
	return DisplayServer.is_touchscreen_available()

func _insets() -> Vector2:
	return insets.call() if insets.is_valid() else Vector2.ZERO

func _map_area() -> Rect2:
	var cover := _insets()
	var top: float = cover.x + _hud["top"].size.y + HUD_MARGIN * 2.0
	var bottom: float = size.y - cover.y - _hud["bottom"].size.y - HUD_MARGIN * 2.0
	return Rect2(0.0, top, size.x, maxf(bottom - top, 1.0))

func fit() -> void:
	camera.screen = _map_area()
	if sim != null:
		camera.fit(sim.field.grow(16.0))

func _w2s(p: Vector2) -> Vector2:
	return camera.w2s(p)

func _s2w(p: Vector2) -> Vector2:
	return camera.s2w(p)

func _process(delta: float) -> void:
	if sim == null:
		return
	if is_visible_in_tree() and sim.started and not sim.finished and not paused:
		_accum += delta * speed
		var steps := 0
		while _accum >= DT and steps < MAX_STEPS_PER_FRAME:
			sim.step(DT)
			_accum -= DT
			steps += 1
	if sim.finished and not _hud["result"].visible:
		_show_result()
	_layout()
	camera.rescreen(_map_area())
	_refresh_status()
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		paused = not paused
		_refresh_hud()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.BACKGROUND, true)
	if sim == null:
		return
	draw_texture_rect(terrain_texture(terrain), Rect2(_w2s(Vector2.ZERO), Terrain.SIZE * camera.zoom), false)
	for road in Terrain.ROADS:
		var pts := PackedVector2Array()
		for p in road:
			pts.append(_w2s(p))
		draw_polyline(pts, ThemeColors.ROAD, maxf(1.5, 4.0 * camera.zoom))
	_draw_field_edge()
	_draw_battle()
```

Then the moved code. From the current `game_root.gd`, copy these functions into `battle_view.gd` unchanged except where noted:

| Function (current `game_root.gd`) | Change |
| --- | --- |
| `_build_terrain_texture` (≈189–206) | rename to `static func _rasterise(terrain: Terrain) -> ImageTexture` (the body already uses a `terrain` name; make it the parameter) |
| `_draw_field_edge`, `_draw_battle`, `_draw_block`, `_draw_orders`, `_draw_combat`, `_draw_clash`, `_draw_tags`, `_block_tag`, `_draw_ack`, `_now`, `_screen_bounds`, `_draw_dashes`, `_draw_arrow`, `_draw_brackets`, `_draw_role_mark` (≈230–237, 285–535) | none |
| `_gui_input`, `_screen_touch`, `_screen_drag`, `_pan_button_event` (≈539–620) | in `_pan_button_event`, `if was_click and _in_battle_control():` becomes `if was_click and sim != null:` |
| `_pointer_down`, `_pointer_move`, `_pointer_up`, `_cancel_pointer` (≈627–742) | keep only the battle branches: delete every `if not _in_battle_control(): …` strategic block, the `_press_army`, `_stroking`, `_stroke_tail`, `preview_path` and `campaign` lines, and the `mode == Mode.STRATEGIC` line in `_cancel_pointer`; `_in_battle_control()` checks become `sim != null` |
| `_update_hover`, `_battle_tap`, `_issue_at`, `_apply_pending`, `_acknowledge`, `_box_select`, `_hit_pad`, `_block_at`, `_clamp_to_field` (≈687–836) | none |
| `_panel`, `_button`, `_label`, `_flow` (≈865–897) | none |
| `_order_button`, `_for_selection`, `_select_all` (≈1001–1018) | none |
| `_selection_tooltip`, `_block_state` (≈1183–1243) | none |

Then write the battle-only HUD and its updates (new, replacing the prototype's mixed versions):

```gdscript
func _build_hud() -> void:
	var top := _panel()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	_hud["top"] = top
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 8)
	top.add_child(top_box)
	_hud["status"] = _label()
	_hud["status"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(_hud["status"])
	var controls := _flow()
	top_box.add_child(controls)
	_hud["begin"] = _button("Begin battle", _on_begin)
	controls.add_child(_hud["begin"])
	_hud["pause"] = _button("Pause", _on_pause)
	controls.add_child(_hud["pause"])
	_hud["speed"] = _button("1×", _on_speed)
	controls.add_child(_hud["speed"])
	controls.add_child(_button("Fit", fit))

	var bottom := _panel()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom)
	_hud["bottom"] = bottom
	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 8)
	bottom.add_child(bottom_box)
	_hud["info"] = _label()
	_hud["info"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud["info"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud["info"].custom_minimum_size.y = 40.0
	_hud["info"].max_lines_visible = 2
	bottom_box.add_child(_hud["info"])
	var orders := _flow()
	bottom_box.add_child(orders)
	_hud["move_btn"] = _order_button("Move", "move")
	orders.add_child(_hud["move_btn"])
	_hud["attack_btn"] = _order_button("Attack", "attack")
	orders.add_child(_hud["attack_btn"])
	orders.add_child(_button("Hold", func(): _for_selection(sim.order_hold)))
	orders.add_child(_button("Withdraw", func(): _for_selection(sim.order_withdraw)))
	orders.add_child(_button("Select all", _select_all))
	orders.add_child(_button("Retreat all", func(): sim.retreat_all(GameConfig.Side.PLAYER)))
	_hud["orders"] = orders

	var log_panel := _panel()
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.custom_minimum_size = Vector2(280, 0)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_panel)
	_hud["log"] = _label("", true)
	_hud["log"].add_theme_font_size_override("font_size", 12)
	_hud["log"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(_hud["log"])
	_hud["log_panel"] = log_panel

	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	var panel := _panel()
	wrap.add_child(panel)
	_hud["result_panel"] = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := _label("Battle over")
	title.add_theme_font_size_override("font_size", 19)
	box.add_child(title)
	_hud["result_title"] = title
	var body := _label("", true)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	_hud["result_body"] = body
	var buttons := _flow()
	box.add_child(buttons)
	_hud["result_buttons"] = buttons
	wrap.visible = false
	_hud["result"] = wrap

## Panels sit inside whatever the host's own HUD covers.
func _layout() -> void:
	var cover := _insets()
	var top: PanelContainer = _hud["top"]
	top.offset_left = HUD_MARGIN
	top.offset_right = -HUD_MARGIN
	top.offset_top = cover.x + HUD_MARGIN
	var bottom: PanelContainer = _hud["bottom"]
	bottom.offset_left = HUD_MARGIN
	bottom.offset_right = -HUD_MARGIN
	bottom.offset_top = -(cover.y + HUD_MARGIN)
	bottom.offset_bottom = -(cover.y + HUD_MARGIN)
	var log_panel: PanelContainer = _hud["log_panel"]
	log_panel.offset_right = -HUD_MARGIN
	log_panel.offset_top = cover.x + top.size.y + HUD_MARGIN * 2.0
	_hud["result_panel"].custom_minimum_size.x = minf(460.0, size.x - 24.0)

func _refresh_hud() -> void:
	var live := sim != null
	_hud["begin"].visible = live and not sim.started
	_hud["pause"].visible = live and sim.started and not sim.finished
	_hud["speed"].visible = live and sim.started and not sim.finished
	_hud["orders"].visible = live and sim.started and not sim.finished
	_hud["log_panel"].visible = live and size.x >= WIDE_SCREEN
	_hud["pause"].text = "Resume" if paused else "Pause"
	_hud["speed"].text = "%d×" % int(speed)
	_hud["move_btn"].set_pressed_no_signal(pending_order == "move")
	_hud["attack_btn"].set_pressed_no_signal(pending_order == "attack")
	if selection.is_empty():
		pending_order = ""
		_hud["move_btn"].set_pressed_no_signal(false)
		_hud["attack_btn"].set_pressed_no_signal(false)

func _refresh_status() -> void:
	var status: Label = _hud["status"]
	var left: float = maxf(0.0, GameConfig.combat["battle_seconds"] - sim.time)
	if sim.finished:
		status.text = "Battle over after %0.0fs — %s" % [sim.time, sim.result["reason"]]
	elif not sim.started:
		status.text = "You are the defender — drag blocks to arrange, then Begin."
	else:
		status.text = "%0.1fs left · %d blocks vs %d" % [
			left,
			sim.side_blocks(GameConfig.Side.PLAYER, true).size(),
			sim.side_blocks(GameConfig.Side.ENEMY, true).size(),
		]
	var d := terrain.describe(hover_world)
	_hud["info"].text = _selection_tooltip() if not selection.is_empty() \
		else "%s — %s" % [d["name"], d["effect"]]
	_hud["log"].text = "\n".join(Array(sim.events).slice(maxi(0, sim.events.size() - 8)))

func _on_begin() -> void:
	sim.started = true
	_refresh_hud()

func _on_pause() -> void:
	paused = not paused
	_refresh_hud()

func _on_speed() -> void:
	speed = 1.0 if speed >= 2.0 else 2.0
	_refresh_hud()

func _show_result() -> void:
	var r := sim.result
	var holder := "nobody"
	if r["holder"] == GameConfig.Side.PLAYER:
		holder = "you"
	elif r["holder"] == GameConfig.Side.ENEMY:
		holder = "the enemy"
	_hud["result_title"].text = "Battle over — %s" % r["reason"]
	var lines: PackedStringArray = [
		"%s holds the field (%s) after %0.0fs." % [holder, r["feature"], r["seconds"]],
		"Losses — you %d, enemy %d.\n" % [
			r["losses"][GameConfig.Side.PLAYER], r["losses"][GameConfig.Side.ENEMY],
		],
	]
	for row in r["rows"]:
		lines.append("%s %-9s %3d/%3d hp   %s" % [
			"you " if row["side"] == GameConfig.Side.PLAYER else "foe ",
			row["name"], int(row["health"]), int(row["max_health"]), row["fate"],
		])
	_hud["result_body"].text = "\n".join(lines)
	var buttons: HFlowContainer = _hud["result_buttons"]
	for c in buttons.get_children():
		buttons.remove_child(c)
		c.queue_free()
	for a in result_actions:
		buttons.add_child(_button(str(a["label"]), a["action"]))
	_hud["result"].visible = true
	_refresh_hud()
```

- [ ] **Step 4: Make `game_root.gd` host it**

In `game/scripts/ui/game_root.gd`:

1. `enum Mode { STRATEGIC, BATTLE }` (RESULT is the view's business now). Add `var battle_view: BattleView = null`.
2. Delete the vars `DT`, `MAX_STEPS_PER_FRAME`, `paused`, `speed`, `_accum`, `selection`, `hover_block`, `pending_order`, `_ack`, `_press_block`, `_box_to`, `dragging_block`.
3. Delete every function moved in Step 3 except `_panel`, `_button`, `_label`, `_flow` and `_screen_touch`/`_screen_drag`/`_gui_input`/`_pan_button_event` (the strategic map still pans and pinches). Also delete `_unhandled_key_input`, `_build_result_panel`, `_on_begin`, `_on_pause`, `_on_speed`, `_show_result`, `_in_battle_control`, `_build_terrain_texture`.
4. `_ready`: `touch = BattleView.detect_touch()` and `_terrain_texture = BattleView.terrain_texture(terrain)`; delete `_detect_touch`.
5. Replace `_begin_battle` and add `_end_battle`:

```gdscript
func _begin_battle(player: Army, enemy: Army) -> void:
	# On a portrait screen a landscape crop is a strip across the middle, so
	# turn the field to match: same area, blocks twice the size.
	var crop: Vector2 = GameConfig.strategic["battle_crop"]
	var area := _map_area()
	if area.size.y > area.size.x:
		crop = Vector2(crop.y, crop.x)
	sim = Scenarios.start_battle(terrain, player, enemy, crop)
	mode = Mode.BATTLE
	peek_map = false
	_cancel_pointer()
	battle_view = BattleView.new()
	battle_view.insets = func() -> Vector2:
		return Vector2(_hud["top"].size.y + HUD_MARGIN, 0.0)
	battle_view.result_actions = [
		{"label": "Replay scenario", "action": func(): _load_scenario(scenario_index)},
		{"label": "Back to map", "action": _end_battle},
	]
	add_child(battle_view)
	# Under the top HUD, which keeps the scenario picker, Map and Tuning.
	move_child(battle_view, 0)
	battle_view.open(terrain, sim, touch)
	_refresh_hud()

func _end_battle() -> void:
	if battle_view != null:
		remove_child(battle_view)
		battle_view.queue_free()
		battle_view = null
	sim = null
	mode = Mode.STRATEGIC
	peek_map = false
	_refresh_hud()
	_fit_camera()
```

6. `_load_scenario`: replace `sim = null`, the `selection`/`hover_block` lines and `_hud["result"].visible = false` with a call to `_end_battle()` at the top (it leaves `mode` strategic), keep the rest.
7. `_process`: remove the stepping block; keep `camera.rescreen(_map_area())`, `_refresh_status()`, `queue_redraw()`.
8. `_draw`: after the background, `if mode == Mode.BATTLE and not peek_map: return` (the view draws the battle); then the terrain, roads and `_draw_strategic()` as today.
9. `_fit_camera`: always `camera.fit(Rect2(Vector2.ZERO, Terrain.SIZE))`.
10. `_pointer_down/_pointer_move/_pointer_up/_cancel_pointer/_pan_button_event`: keep only the strategic branches (delete the battle branches and the `_in_battle_control()` tests; `_pan_button_event` no longer issues a right-click order).
11. `_build_hud`: delete the `begin`, `pause`, `speed` buttons, the orders flow, the log panel and `_build_result_panel()` call. Keep picker, status, End Turn, Map (`peek`), Fit, Tuning, the bottom info label.
12. `_refresh_hud`:

```gdscript
func _refresh_hud() -> void:
	var in_battle := mode == Mode.BATTLE
	_hud["end_turn"].visible = not in_battle
	_hud["peek"].visible = in_battle
	_hud["fit"].visible = not in_battle or peek_map
	_hud["bottom"].visible = not in_battle or peek_map
	_hud["peek"].text = "Battle" if peek_map else "Map"
	if battle_view != null:
		battle_view.visible = not peek_map
```

13. `_on_peek`: `peek_map = not peek_map`, `_cancel_pointer()`, `_refresh_hud()`, `_fit_camera()` (hiding the view pauses the battle).
14. `_refresh_status`: in battle, `status.text = "Battle — %s" % Scenarios.all()[scenario_index]["name"]` plus `" · map (paused)"` when `peek_map`; the strategic branch unchanged. `_layout_overlays`: drop the log and result lines.
15. `_map_area`: unchanged.

- [ ] **Step 5: Import and run the tests**

Run: `$G --headless --path game --import` then `cd game && $G --headless --script tests/run_tests.gd`
Expected: `0 failed`, combat suite still 87 checks, `battle_shell` checks `ok`.

- [ ] **Step 6: Play it**

Run: `powershell -ExecutionPolicy Bypass -File tools/play-desktop.ps1 -Console`. Pick Combat Prototype → The Hill. Check by hand: End Turn until the armies meet; the battle opens; Move/Attack/Hold/Withdraw/Select all/Retreat all work with the mouse (left select, right-click order, box-select, wheel zoom, right-drag pan); Pause/space and 2× work; Map shows the strategic view with the field outlined and the clock stops; Battle returns; the result panel's Replay and Back to map both work. Then The Ford as the defender: blocks can be dragged before Begin. Any console error is a failure.

- [ ] **Step 7: Stage**

```bash
git add game/scripts/ui/battle_view.gd game/scripts/ui/battle_view.gd.uid game/scripts/ui/game_root.gd game/tests/test_battle_shell.gd game/tests/test_battle_shell.gd.uid
```
Suggested message: `WS-C: extract the battle screen into BattleView; the prototype hosts it`

---

### Task 6: Battles on the campaign map

**Files:**
- Create: `game/scripts/ui/layers/battle_layer.gd`
- Modify: `game/scripts/ui/campaign_root.gd` (`LAYERS`, one line)
- Modify: `game/tests/test_battle_shell.gd`

**Interfaces:**
- Consumes: `MapLayer` (`draw`, `tooltip`, `pressed`, `buttons`, `order`, `view`), `MapView` (`world`, `terrain`, `w2s`, `map_area()`, `font`, `get_parent()` is the `CampaignRoot`), `CampaignRoot.set_overlay/clear_overlay`, `BattleBridge.start/apply_result`, `BattleView`.
- Produces `BattleLayer extends MapLayer` (order 90):
  - draws a crossed-swords marker above every waiting battle's site, with `×R` (its ratio);
  - `tooltip` over a marker: `"Battle at <site>: your N regiments vs M · strength ratio R (auto-resolves at T)"`;
  - `pressed` on a marker opens that battle;
  - `buttons()`: `[{label: "Fight battle", action: open_next, enabled: has_waiting}]`;
  - `func open(battle: Dictionary) -> void`, `func open_next() -> void`, `func has_waiting() -> bool`, `var current: BattleView` (null when none open).
  - The result panel's single action, **"Back to the campaign"**, calls `BattleBridge.apply_result`, closes the overlay and redraws. If the world is replaced (Reset, scenario switch) or the battle leaves `pending_battles` (End Turn pressed mid-battle), the view closes itself without applying anything; an unfought battle is offered again next turn.

- [ ] **Step 1: Write the failing tests**

In `test_battle_shell.gd` `run()`, add after `_test_combat_scene_builds(tree)`:

```gdscript
	_test_campaign_battle_flow(tree)
```

Append:

```gdscript
func _test_campaign_battle_flow(tree: SceneTree) -> void:
	print("\nthe campaign puts a waiting battle on screen and writes it back")
	var packed := load("res://scenes/campaign.tscn") as PackedScene
	if packed == null:
		t.check("campaign.tscn loads", false)
		return
	var root = packed.instantiate()
	tree.root.add_child(root)
	var view: MapView = root.view
	var layer: BattleLayer = null
	for l in view.layers:
		if l is BattleLayer:
			layer = l
	t.check("the battle layer is registered", layer != null)
	if layer == null:
		tree.root.remove_child(root)
		root.free()
		return
	var w: World = view.world
	var hill := -1
	var watch := -1
	for s in w.graph.sites:
		if s.name == "East Hill":
			hill = s.id
		elif s.name == "Hilltop Watch":
			watch = s.id
	for s in w.stacks.duplicate():
		w.remove_stack(s)
	var mine := w.add_stack(0, watch, [0, 0, 0, 0])
	var theirs := w.add_stack(1, hill, [0, 0, 0])
	Orders.move(w, mine, hill)
	root._on_end_turn()
	t.check("End Turn leaves the fight waiting", w.pending_battles.size() == 1)
	t.check("Fight battle is enabled", layer.has_waiting())
	t.check("the marker explains the fight",
		"strength ratio" in layer.tooltip(view.s2w(layer._marker(w.pending_battles[0]))))
	layer.open_next()
	t.check("the battle view is up", layer.current != null and layer.current.get_parent() == root)
	t.check("the map is hidden under it", not view.visible)
	var sim: BattleSim = layer.current.sim
	for b in sim.side_blocks(GameConfig.Side.ENEMY):
		b.health = 0.0
		b.status = Block.Status.DESTROYED
	sim._finish("test")
	layer.current._process(0.0)
	t.check("the result panel shows", layer.current.result_shown())
	layer.current.result_actions[0]["action"].call()
	t.check("closing it puts the map back", layer.current == null and view.visible)
	t.check("the battle is no longer waiting", w.pending_battles.is_empty())
	t.check("its losses were applied", not w.stacks.has(theirs))
	# End Turn in the middle of a battle: the view closes and nothing is applied.
	var again := w.add_stack(1, hill, [0, 0, 0])
	w.pending_battles = []
	root._on_end_turn()
	t.check("the standoff is offered again", w.pending_battles.size() == 1)
	layer.open_next()
	root._on_end_turn()
	# In the running game the tree's process_frame calls this; headless, the test does.
	layer._watch()
	t.check("End Turn mid-battle closes the view", layer.current == null)
	t.check("without applying a result", w.stacks.has(again) and again.size() == 3)
	tree.root.remove_child(root)
	root.free()
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd game && $G --headless --script tests/run_tests.gd -- battle_shell`
Expected: FAIL — `BattleLayer` not found.

- [ ] **Step 3: Implement**

Create `game/scripts/ui/layers/battle_layer.gd`:

```gdscript
class_name BattleLayer
extends MapLayer

## WS-C: the campaign's battles. Marks every fight waiting for the player,
## explains it on hover (with the auto-resolve ratio), and puts it on screen in
## a BattleView over the map; the result goes back to the world through
## BattleBridge. AI fights and trivial ones never reach here — EngagementPhase
## resolved them already, and the log says how.

const MARKER_LIFT := 30.0            # screen px above the site
const MARKER_RADIUS := 12.0

var current: BattleView = null
var _battle := {}
var _world: World = null

func order() -> int:
	return 90

func has_waiting() -> bool:
	return view != null and view.world != null and not view.world.pending_battles.is_empty()

func buttons() -> Array[Dictionary]:
	return [{"label": "Fight battle", "action": open_next, "enabled": has_waiting}]

func open_next() -> void:
	if has_waiting():
		open(view.world.pending_battles[0])

func open(battle: Dictionary) -> void:
	var host := view.get_parent() as CampaignRoot
	if host == null or current != null:
		return
	var crop: Vector2 = GameConfig.strategic["battle_crop"]
	var area := view.map_area()
	if area.size.y > area.size.x:
		crop = Vector2(crop.y, crop.x)
	var sim := BattleBridge.start(view.world, view.terrain, battle, crop)
	_battle = battle
	_world = view.world
	current = BattleView.new()
	current.insets = func() -> Vector2: return Vector2(view.inset_top, view.inset_bottom)
	current.result_actions = [{"label": "Back to the campaign", "action": _finish}]
	host.set_overlay(current)
	current.open(view.terrain, sim, BattleView.detect_touch())
	# Every frame, check that the battle on screen still exists (see _watch).
	current.get_tree().process_frame.connect(_watch)

func _finish() -> void:
	if current == null:
		return
	if _still_pending() and current.sim.finished:
		BattleBridge.apply_result(_world, current.sim, _battle)
	_close()

## End Turn, Reset and the scenario picker stay clickable over the battle; any
## of them makes this battle stale, so the view goes without touching the world.
func _watch() -> void:
	if current != null and not _still_pending():
		_close()

## By identity, not value: End Turn re-collects an unfought standoff as a new
## dictionary with the same stacks in it, and that is a different battle —
## the one on screen was cancelled.
func _still_pending() -> bool:
	if view.world != _world:
		return false
	for b in _world.pending_battles:
		if is_same(b, _battle):
			return true
	return false

func _close() -> void:
	if current == null:
		return
	var tree := current.get_tree()
	if tree != null and tree.process_frame.is_connected(_watch):
		tree.process_frame.disconnect(_watch)
	var host := view.get_parent() as CampaignRoot
	if host != null:
		host.clear_overlay()
	current.queue_free()
	current = null
	_battle = {}
	_world = null
	view.queue_redraw()

func _marker(battle: Dictionary) -> Vector2:
	return view.w2s(view.world.graph.sites[battle["site_id"]].pos) + Vector2(0, -MARKER_LIFT)

func draw(canvas: CanvasItem) -> void:
	if view.world == null:
		return
	for b in view.world.pending_battles:
		var at := _marker(b)
		canvas.draw_circle(at, MARKER_RADIUS, ThemeColors.BACKGROUND)
		canvas.draw_arc(at, MARKER_RADIUS, 0.0, TAU, 24, ThemeColors.ACCENT, 2.0)
		canvas.draw_line(at + Vector2(-6, -6), at + Vector2(6, 6), ThemeColors.TEXT, 2.0)
		canvas.draw_line(at + Vector2(6, -6), at + Vector2(-6, 6), ThemeColors.TEXT, 2.0)
		canvas.draw_string(view.font, at + Vector2(MARKER_RADIUS + 4, 5),
			"×%.1f" % float(b.get("ratio", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ThemeColors.TEXT)

func _battle_at_screen(screen: Vector2) -> Dictionary:
	for b in view.world.pending_battles:
		if _marker(b).distance_to(screen) <= MARKER_RADIUS + 6.0:
			return b
	return {}

func tooltip(world_pos: Vector2) -> String:
	if view.world == null:
		return ""
	var b := _battle_at_screen(view.w2s(world_pos))
	if b.is_empty():
		return ""
	var mine := BattleBridge.player_stack(view.world, b)
	if mine == null:
		return ""
	var theirs := BattleBridge.other(b, mine)
	return "Battle at %s: your %d regiments vs %d · strength ratio %.1f (auto-resolves at %.1f)" % [
		view.world.graph.sites[b["site_id"]].name, mine.size(), theirs.size(),
		float(b.get("ratio", 0.0)), float(GameConfig.battle_bridge["auto_resolve_ratio"]),
	]

func pressed(world_pos: Vector2) -> bool:
	if view.world == null:
		return false
	var b := _battle_at_screen(view.w2s(world_pos))
	if b.is_empty():
		return false
	open(b)
	return true
```

In `game/scripts/ui/campaign_root.gd` `LAYERS`, add the last line:

```gdscript
	preload("res://scripts/ui/layers/battle_layer.gd"),
```

- [ ] **Step 4: Import and run every suite**

Run: `$G --headless --path game --import` then `cd game && $G --headless --script tests/run_tests.gd`
Expected: `0 failed`. `test_logistics_shell.gd` asserts the stacks layer is on top by `order()`; BattleLayer is 90, so it stays true.

- [ ] **Step 5: Play it**

Run `tools/play-desktop.ps1 -Console` → Campaign. Move the Empire army from Capital Depot toward the ford and on toward the Warlord army (or pick The Siege and march on the marcher). When the stacks meet: a ⚔ marker with a ratio appears on the site, hovering it explains the fight, "Fight battle" lights up; pressing it opens the battle over the map with the campaign HUD still above it; fight it; "Back to the campaign" returns to the map with the losses applied, the loser one hop away, and a "Battle at …" line in the log. Try End Turn mid-battle: the view closes, and the battle is offered again. Any console error is a failure.

- [ ] **Step 6: Stage**

```bash
git add game/scripts/ui/layers/battle_layer.gd game/scripts/ui/layers/battle_layer.gd.uid game/scripts/ui/campaign_root.gd game/tests/test_battle_shell.gd
```
Suggested message: `WS-C: fight the campaign's battles over the map and apply the result`

---

### Task 7: Docs, the full run, and the builds

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-09-21-logistics-roguelike-workstreams.md` (WS-C section)

- [ ] **Step 1: README**

In the layout block, under `scripts/sim/logistics/`, add:

```
    battle/                    the battle bridge: battle_bridge.gd (stack → army,
                               result → regiments and retreat), auto_resolve.gd
                               (the ratio, threshold auto-resolve, the AI stub)
```

under `scripts/ui/layers/`: add `battle_layer.gd` to the list; under `scripts/ui/game_root.gd` add:

```
  scripts/ui/battle_view.gd    the battle screen as a component: both shells host it
```

and to the tests list:

```
  tests/test_battle_bridge.gd  engagement, the bridge, results, auto-resolve, East Hill
  tests/test_battle_shell.gd   BattleView, the prototype on it, the campaign battle flow
```

After the `## Logistics` section's last subsection, add:

```markdown
## Battles on the campaign map

When a march ends on an enemy — or two enemies are still sharing a site from
last turn — End Turn turns it into a battle, one per site per turn:

- **Your fights are played.** The site gets a ⚔ marker with the strength
  ratio; **Fight battle** (or a tap on the marker) opens the real-time battle
  over the map, on a crop of the same ground, with the defender on the site and
  the attacker arriving along the edge it marched in on. A stack fields at most
  8 blocks, one of each role in turn, and the rest wait in reserve. Not ready?
  End the turn and it is offered again — or march away, which is a retreat.
- **Trivial fights are not.** When your stack's effective strength (size ×
  quality × supply) is at least **3×** the enemy's, the fight resolves in your
  favour for 10% attrition, 5 supply and the rest of the move, and the log says
  so with the ratio. About one time in twenty it goes wrong anyway.
- **AI fights** use the same stub: the winner is rolled on strength.

Afterwards, a destroyed block costs a regiment of its role; a block that fled,
routed or withdrew lives. Whoever holds the field wins (nobody: the defender).
The loser falls back one hop — an attacker the way it came, a defender toward
its depot — for 10 supply; a loser with every way out held by the enemy is
lost. Every number is in `GameConfig.battle_bridge` and the tuning panel.
```

- [ ] **Step 2: Mark WS-C done in the workstreams plan**

Under `### WS-C — Battle bridge…`, after the **Acceptance** line, add:

```markdown
**Done.** Step plan: `2026-09-23-ws-c-battle-bridge.md`. What the others need to know:

- **`World.pending_battles` after EngagementPhase holds only fights waiting for
  the player** (`{attacker, defender, site_id, from_site, ratio, sides}`); AI and
  trivial fights are resolved in the phase and logged as "Battle at …". WS-D
  reads the log or the stacks, not this list.
- **Standoffs persist.** Hostile stacks left on one site are a battle again next
  turn. Moving away is how a stack declines.
- **`BattleBridge.conclude(world, battle, winner, lost, how)`** is the one way a
  battle ends (losses by role, empty stacks removed, loser retreats, log). WS-B's
  escort fights and WS-D's planner should call `AutoResolve.resolve` or
  `conclude` rather than editing regiments.
- **`BattleView`** is the battle screen for any host; it takes the host's
  result buttons and HUD insets and pauses when hidden.
- Not done, by design: regiment health across battles (fled blocks come back
  whole), leader quality in the battle itself (WS-G), a "let the general fight
  it" button (`BattleBridge.start(..., ai_plays_player = true)` is ready for it).
```

- [ ] **Step 3: Full run and both builds**

Run: `cd game && $G --headless --script tests/run_tests.gd`
Expected: `N checks, 0 failed (8 suites)`; the combat suite's 87 unchanged.
Run: `powershell -ExecutionPolicy Bypass -File tools/build-windows.ps1 -Godot "<the _console.exe>"`
Expected: `Built …\build\windows\CombatPrototype.exe`; start it with `--quit-after 300` and check the output has no errors.

- [ ] **Step 4: Stage**

```bash
git add README.md docs/superpowers/plans/2026-09-21-logistics-roguelike-workstreams.md docs/superpowers/plans/2026-09-23-ws-c-battle-bridge.md
```
Suggested message: `WS-C: document the battle bridge`
