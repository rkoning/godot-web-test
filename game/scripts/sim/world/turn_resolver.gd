class_name TurnResolver
extends RefCounted

## End Turn runs every phase in this fixed order. Each phase is one static
## function in its own file under sim/phases/, owned by one workstream, so a
## system can be built without touching anyone else's. The order is the seam:
## do not reorder without telling every owner.
##
## WS-M (provinces) has no per-turn slot by design; consolidation is an action,
## not a phase.

static func phases() -> Array[Callable]:
	return [
		AiPhase.run,           # WS-D  AI nations issue orders (the player already did)
		MovementPhase.run,     # WS-A  walk paths along edges; merge on arrival
		EngagementPhase.run,   # WS-C  hostile stacks on one site → battle / stub
		OccupationPhase.run,   # WS-A  who holds each site and region
		SupplyPhase.run,       # WS-A  depots refill, upkeep, levels, pillage
		TradePhase.run,        # WS-B  dispatch, move, arrive, capture caravans
		EconomyPhase.run,      # WS-F  coin, levies, unrest, culture/faith drift
		CharacterPhase.run,    # WS-G  leaders act, history accrues, quality resolves
		InfluencePhase.run,    # WS-E  Influence income, AI diplomacy and shop
		GovernmentPhase.run,   # WS-I  constituencies, client drift, tribute
		CrisisPhase.run,       # WS-H  eligibility, announcements, clocks, resolution
		EraPhase.run,          # P0    era boundaries
	]

static func end_turn(world: World) -> void:
	for s in world.stacks:
		s.moved_this_turn = false
	for phase in phases():
		phase.call(world)
	world.turn += 1
