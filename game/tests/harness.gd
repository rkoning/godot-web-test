class_name TestHarness
extends RefCounted

## Shared by every tests/test_*.gd suite. A suite is a RefCounted with
## `func run(t: TestHarness) -> void` and calls t.check(...) for each assertion.

const DT := 1.0 / 60.0

var checks := 0
var failures := 0

func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s %s" % [label, detail])

func near(label: String, actual: float, expected: float, tol: float) -> void:
	check(label, absf(actual - expected) <= tol, "got %.3f, wanted %.3f ± %.3f" % [actual, expected, tol])

## A battle arena on the prototype terrain, both sides player-controlled.
func arena(terrain: Terrain = null) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(terrain if terrain != null else Terrain.new(), Rect2(500, 300, 300, 200))
	sim.supply[GameConfig.Side.PLAYER] = 1.0
	sim.supply[GameConfig.Side.ENEMY] = 1.0
	sim.behavior[GameConfig.Side.PLAYER] = ""
	sim.behavior[GameConfig.Side.ENEMY] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	return sim

func run_for(sim: BattleSim, seconds: float) -> void:
	for i in int(seconds / DT):
		sim.step(DT)

## The prototype world exactly as the shell seeds it, the map's two starting
## field armies included.
func world(seed := 1) -> World:
	return World.from_map(PrototypeMap.data(), seed)

## The same world with the map's starting armies left out. The unit tests for
## stacks, relations and presence place their own and would otherwise be
## counting the shell's two field armies as well.
func bare_world(seed := 1) -> World:
	var data := PrototypeMap.data()
	data.erase("stacks")
	return World.from_map(data, seed)
