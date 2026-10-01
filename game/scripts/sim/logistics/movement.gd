class_name Movement
extends RefCounted

## Walks a stack's ordered path on End Turn and folds friendly stacks together
## where they end up. No rules about *where* to go live here (see Orders and
## Pathing); this is only what happens once the order is given.

## Edge kinds in the player's words, indexed by `Edge.Kind`, for the one log
## line that has to name the obstacle.
const KIND_NAMES := ["road", "river", "trail", "mountain pass"]

## Walk `s` as far as its points reach. Returns the site it stepped in *from*
## when it stopped on hostile presence, or -1 when it did not — `MovementPhase`
## turns that into a pending battle for WS-C.
static func walk(world: World, s: Stack) -> int:
	if s.path.is_empty():
		return -1
	var allowance := SupplyRules.move_points(s)
	var points := allowance
	while points > 0 and not s.path.is_empty():
		var next: int = s.path[0]
		var e := world.graph.edge_between(s.site_id, next)
		if e == null:
			# The map cannot change, so a stale route means a bad order; say so and drop it.
			world.record("%s's route no longer leads anywhere and was dropped" % s.label)
			s.path.clear()
			return -1
		var cost := SupplyRules.move_cost(e.kind)
		if cost > points:
			# Waiting only helps if next turn buys more, and it does not: the
			# allowance is the same every turn. A step the stack could never
			# afford — a starving army at a trail — is as dead an order as a
			# stale route, so it is dropped the same way rather than leaving the
			# army standing on it forever.
			if points == allowance:
				world.record("%s cannot cross the %s ahead and its route was dropped"
					% [s.label, KIND_NAMES[e.kind]])
				s.path.clear()
			return -1
		points -= cost
		var from := s.site_id
		s.site_id = next
		s.path.remove_at(0)
		s.moved_this_turn = true
		if world.hostile_presence(next, s.nation_id):
			# The march ends where the enemy is; EngagementPhase (WS-C) takes it from here.
			s.path.clear()
			return from
	return -1

## Fold `other` into `into`: regiments pooled, supply size-weighted, the
## survivor keeps its own order and route.
static func merge(world: World, into: Stack, other: Stack) -> void:
	var n_a := into.size()
	var n_b := other.size()
	if n_a + n_b > 0:
		into.supply = (into.supply * float(n_a) + other.supply * float(n_b)) / float(n_a + n_b)
	into.regiments.append_array(other.regiments)
	world.remove_stack(other)
	world.record("%s joined %s (%d regiments)" % [other.label, into.label, into.size()])

## Every site, every nation: the lowest-id stack absorbs the rest, unless a
## stack asked to be left alone.
static func merge_all(world: World) -> void:
	var ordered: Array = world.stacks.duplicate()
	ordered.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	var survivors := {}                 # "site:nation" -> Stack
	for s in ordered:
		if s.hold_separate:
			continue
		var key := "%d:%d" % [s.site_id, s.nation_id]
		if survivors.has(key):
			merge(world, survivors[key], s)
		else:
			survivors[key] = s
