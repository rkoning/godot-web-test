class_name EraPhase
extends RefCounted

## Announces era boundaries. Runs last, so listeners see the finished turn.
## The turn counter has not advanced yet, so compare this turn with the next
## through `World.era_of`, which is the only copy of the formula.

static func run(world: World) -> void:
	var next := World.era_of(world.turn + 1)
	if next == world.era():
		return
	world.record("Era %d begins" % next)
	for l in world.era_listeners:
		l.call(world, next)
