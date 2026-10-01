class_name LogisticsSetup
extends RefCounted

## WS-A's run-start hook: every depot that exists when the world is born opens
## with the configured stock. Map data has no stock field on purpose — a depot
## is a depot, and how full it starts is a tuning number, not a map fact.

static func run(world: World) -> void:
	for s in world.graph.sites:
		if Holdings.depot_ready(world, s):
			s.stock = float(GameConfig.logistics["depot_initial_stock"])
