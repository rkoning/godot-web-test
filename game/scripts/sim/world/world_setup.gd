class_name WorldSetup
extends RefCounted

## Run-start setup: the mirror of `TurnResolver` for turn zero. `World.from_map`
## calls every hook here once, with the finished world, after the graph,
## nations, relations and the map's starting stacks are in place.
##
## One line per workstream, in this fixed order. A hook may append to
## `world.era_listeners`, so a system that only wakes up at an era boundary
## still needs no per-turn slot:
##
##   CharacterSetup.run   # WS-G  roster, rulers, governors, stack leaders
##   ShopSetup.run        # WS-E  era-1 shop stock, and the refresh listener
##   SocietySetup.run     # WS-F  region culture, faith and unrest defaults
##   CrisisSetup.run      # WS-H  crisis catalogue and eligibility state
##
## WS-M (provinces) has no setup slot by design; consolidation is an action.

static var _hooks: Array[Callable] = []

## The live hook list, **by reference**.
##
## A workstream registers its setup by adding one line to the `_hooks`
## initializer above — the same additive one-line hunk as `TurnResolver.phases()`
## — and never calls `hooks().append()` at run time. This is process-global
## mutable state shared by every suite in the test runner: a hook appended and
## not erased leaks into every later `World.from_map` and surfaces as a baffling
## failure in somebody else's suite. A test that appends one owns erasing it.
static func hooks() -> Array[Callable]:
	return _hooks
