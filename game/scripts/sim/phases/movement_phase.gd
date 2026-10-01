class_name MovementPhase
extends RefCounted

## WS-A. Scripted enemies decide, every stack walks its route in id order (so
## a turn resolves identically every time), then arrivals merge.

static func run(world: World) -> void:
	# Last turn's offers are stale the moment armies move again; an entry
	# left behind would pin a Stack that may since have merged or dissolved.
	world.pending_battles.clear()
	ScriptedEnemy.issue_orders(world)
	var ordered: Array = world.stacks.duplicate()
	ordered.sort_custom(func(a: Stack, b: Stack) -> bool: return a.id < b.id)
	for s in ordered:
		if not world.stacks.has(s):
			continue
		var from := Movement.walk(world, s)
		if from >= 0:
			# A march that ended on an enemy is a battle offered, not fought.
			# EngagementPhase (WS-C) resolves these the same turn; the list is
			# emptied at the top of the next MovementPhase either way.
			world.pending_battles.append({
				"attacker": s,
				"site_id": s.site_id,
				"from_site": from,
			})
	Movement.merge_all(world)
