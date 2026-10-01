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
