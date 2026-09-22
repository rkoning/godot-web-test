class_name World
extends RefCounted

## Everything the campaign simulates, and the only place randomness comes from.
## Headless by construction: no nodes, no signals, no rendering.

## The two relation states. Compare against these rather than the strings: a
## typo in a literal is a silent "peace", which reads as a bug in diplomacy
## rather than as a misspelling.
const WAR := "war"
const PEACE := "peace"

var graph: WorldGraph
var nations: Array[Nation] = []
var stacks: Array[Stack] = []
var routes: Array = []            # TradeRoute (WS-B)
var characters: Array = []        # Character (WS-G)
var crises: Array = []            # Crisis (WS-H)
var pending_battles: Array = []   # {attacker, defender, site_id, from_site} (WS-C)
var provinces: Array = []         # Province (WS-M)
var turn := 1
var rng := RandomNumberGenerator.new()
var events: PackedStringArray = []
var era_listeners: Array[Callable] = []   # called (world, new_era) by EraPhase

var _next_stack_id := 1
var _relations := {}              # "lo:hi" -> WAR | PEACE

func _init(p_graph: WorldGraph, seed := 1) -> void:
	graph = p_graph
	rng.seed = seed

## Build a whole world from one map dictionary: graph, nations, relations, the
## map's starting stacks, then every `WorldSetup` hook. This is the only way a
## world is born, so a run set up by the shell, by a test and by the headless
## AI harness are the same world.
static func from_map(data: Dictionary, seed := 1) -> World:
	var w := World.new(WorldGraph.from_data(data), seed)
	for nd in data.get("nations", []):
		var n := Nation.from_dict(nd)
		assert(n.id == w.nations.size(), "nation ids must be 0..n-1 in order")
		w.nations.append(n)
	for rd in data.get("relations", []):
		var state := str(rd["state"])
		if state != WAR and state != PEACE:
			push_error("map relation %d:%d has unknown state '%s' (expected '%s' or '%s')"
				% [int(rd["a"]), int(rd["b"]), state, WAR, PEACE])
			continue
		w.set_relation(int(rd["a"]), int(rd["b"]), state)
	for sd in data.get("stacks", []):
		w._add_map_stack(sd)
	for hook in WorldSetup.hooks():
		hook.call(w)
	return w

## One `"stacks"` entry from map data:
##   {"nation": 0, "site": "Capital Depot", "regiments": ["infantry", ...], "supply": 100}
## The site is named rather than numbered so renumbering the map cannot move an
## army somewhere else, and an unknown name is reported and skipped rather than
## crashing a run over one bad line. Roles are role names or raw ints.
func _add_map_stack(d: Dictionary) -> void:
	var site_name := str(d.get("site", ""))
	var nation_id := int(d.get("nation", -1))
	# Checked, not defaulted: a typo'd key would otherwise hand the army to
	# nation 0, and an out-of-range id reaches `nation(id).name` as an index
	# error a long way from the map line that caused it.
	if nation_id < 0 or nation_id >= nations.size():
		push_error("map stack on '%s' names nation %d, which is outside 0..%d"
			% [site_name, nation_id, nations.size() - 1])
		return
	var site := _site_named(site_name)
	if site == null:
		push_error("map stack for nation %d references unknown site '%s'"
			% [nation_id, site_name])
		return
	var roster: Array = []
	for r in d.get("regiments", []):
		if typeof(r) == TYPE_INT or typeof(r) == TYPE_FLOAT:
			roster.append(int(r))
			continue
		var key := str(r).to_upper()
		if not GameConfig.Role.has(key):
			push_error("map stack on '%s' names unknown regiment role '%s'" % [site_name, str(r)])
			continue
		roster.append(int(GameConfig.Role[key]))
	add_stack(nation_id, site.id, roster, float(d.get("supply", 100.0)))

func _site_named(site_name: String) -> Site:
	for s in graph.sites:
		if s.name == site_name:
			return s
	return null

func player() -> Nation:
	for n in nations:
		if n.is_player:
			return n
	return null

func nation(id: int) -> Nation:
	return nations[id]

func add_stack(nation_id: int, site_id: int, regiments: Array, supply := 100.0) -> Stack:
	var s := Stack.new()
	s.id = _next_stack_id
	_next_stack_id += 1
	s.nation_id = nation_id
	s.site_id = site_id
	for r in regiments:
		s.regiments.append(int(r))
	s.supply = supply
	s.label = "%s stack %d" % [nation(nation_id).name, s.id]
	stacks.append(s)
	return s

func remove_stack(s: Stack) -> void:
	stacks.erase(s)

func stacks_at(site_id: int) -> Array[Stack]:
	var out: Array[Stack] = []
	for s in stacks:
		if s.site_id == site_id:
			out.append(s)
	return out

func stacks_of(nation_id: int) -> Array[Stack]:
	var out: Array[Stack] = []
	for s in stacks:
		if s.nation_id == nation_id:
			out.append(s)
	return out

func _rel_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

func relation(a: int, b: int) -> String:
	return _relations.get(_rel_key(a, b), PEACE)

func set_relation(a: int, b: int, state: String) -> void:
	_relations[_rel_key(a, b)] = state

func hostile(a: int, b: int) -> bool:
	return a != b and relation(a, b) == WAR

## Walks `stacks` rather than calling `stacks_at`: this is the hottest query in
## the game (pathing and supply ask it per site per hop per nation per turn) and
## it must not allocate an array to answer a yes/no question.
func hostile_presence(site_id: int, nation_id: int) -> bool:
	for s in stacks:
		if s.site_id == site_id and hostile(s.nation_id, nation_id):
			return true
	return false

## Presence severs: an edge is cut for `nation_id` while a hostile stack stands
## on either end. Repair is free the turn the stack leaves. Pathing and supply
## (WS-A) refuse to pass *through* a site with hostile presence; this query is
## what the map draws dashed red and what edge value (WS-D) reads.
func is_severed(e: Edge, nation_id: int) -> bool:
	return hostile_presence(e.a, nation_id) or hostile_presence(e.b, nation_id)

## The era a turn falls in, 1-based. The one place the formula lives: `era()`
## and `EraPhase` both go through it, so a tuning change to `turns_per_era`
## cannot make the status line and the era edges disagree.
##
## The last era does not roll over — turn 1000 is still era 3 — because what
## happens when a run's turns are spent is Phase 3's decision, not arithmetic's.
## Both config numbers are floored at 1: the tuning panel can drag either to
## zero mid-run, and neither a division by zero nor an era 0 is a thing the rest
## of the game is written to survive.
static func era_of(t: int) -> int:
	var per: int = maxi(1, int(GameConfig.run["turns_per_era"]))
	return mini(int((t - 1) / per) + 1, maxi(1, int(GameConfig.run["eras"])))

func era() -> int:
	return era_of(turn)

func record(text: String) -> void:
	events.append("T%d %s" % [turn, text])
