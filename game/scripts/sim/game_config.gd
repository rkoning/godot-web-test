class_name GameConfig
extends RefCounted

## Every tunable number in the prototype. Logic reads from here and never
## hardcodes a value, so the dev tuning panel can change the feel of a battle
## while it is running.

enum Role { INFANTRY, CAVALRY, ARCHERS }
enum Side { PLAYER, ENEMY }

static var units := {
	Role.INFANTRY: {
		"name": "Infantry",
		"mark": "infantry",
		"size": Vector2(24, 12),
		"health": 100.0,
		"morale": 100.0,
		"speed": 14.0,          # was 20: slowed for game feel (2026-09-30)
		"melee_dps": 8.0,
		"ranged_dps": 0.0,
		"range": 0.0,
		"charge_burst": 0.0,
		"can_brace": true,
		"turn_rate": 90.0,     # deg/s (infantry)
		"reform_time": 2.0,    # s to turn to face a flanker
	},
	Role.CAVALRY: {
		"name": "Cavalry",
		"mark": "cavalry",
		"size": Vector2(20, 12),
		"health": 80.0,
		"morale": 90.0,
		"speed": 30.0,          # was 45: slowed for game feel (2026-09-30)
		"melee_dps": 6.0,
		"ranged_dps": 0.0,
		"range": 0.0,
		"charge_burst": 40.0,
		"can_brace": false,
		"turn_rate": 180.0,
		"reform_time": 1.5,
	},
	Role.ARCHERS: {
		"name": "Archers",
		"mark": "archers",
		"size": Vector2(24, 10),
		"health": 60.0,
		"morale": 70.0,
		"speed": 14.0,          # was 20: slowed for game feel (2026-09-30)
		"melee_dps": 3.0,
		"ranged_dps": 5.0,
		"range": 120.0,
		"charge_burst": 0.0,
		"can_brace": false,
		"turn_rate": 120.0,
		"reform_time": 1.5,
	},
}

static var combat := {
	# Facing multipliers: [health damage multiplier, morale drain per second]
	"front_damage": 1.0,
	"front_morale": 2.0,
	"flank_damage": 1.5,
	"flank_morale": 8.0,
	"rear_damage": 2.0,
	"rear_morale": 15.0,
	# Being hit in the flank/rear while already fighting to the front.
	"flanked_morale_multiplier": 2.0,
	"outnumbered_morale": 1.0,
	"morale_per_health": 1.0 / 3.0,
	"morale_recovery": 3.0,
	"ally_rout_morale": 15.0,
	"ally_rout_radius": 80.0,
	"charge_min_distance": 30.0,
	"charge_cooldown": 4.0,
	"brace_time": 1.0,
	"brace_charge_multiplier": 0.25,
	"brace_counter_burst": 20.0,
	"rout_damage_multiplier": 2.0,
	"rout_speed_multiplier": 1.2,
	"rout_recover_time": 6.0,
	"rout_recover_morale": 20.0,
	"withdraw_speed_multiplier": 0.75,
	# Contact (spec 2026-09-23): locks, pressure, push, turning, reform.
	"seat_speed": 15.0,        # was 30 (halved for game feel 2026-09-30); u/s an attacker slides to sit flush on the face it struck
	# push_per_dps / push_deadband / push_smoothing tuned in Task 4 (was 1.0 / 0.5 /
	# 1.0): narrow green region, re-measure in Task 7.
	# push_per_dps 0.5 -> 0.45 (drawn-orders last gate: no stacking onto a fight
	# flipped the Ford near-miss to a win; 0.4 and 0.45 pass, 0.5 and 0.55 fail).
	"push_per_dps": 0.45,      # push speed per point of damage-per-second advantage
	"push_max": 6.0,           # u/s cap on how fast a loser gives ground
	"push_deadband": 1.0,      # dps advantage below which a fight is even
	"push_smoothing": 1.5,     # s over which pressure is averaged
	"pivot_angle": 45.0,       # deg off heading beyond which a block turns in place
	"reform_damage": 0.5,      # damage dealt while reforming
	# Drawn orders (spec 2026-09-24).
	"route_sample": 12.0,        # u between points of a cleaned stroke
	"route_reach": 2.0,          # u within which a route point counts as reached
	"formation_rank_gap": 32.0,  # u between ranks of a formation line
	"draw_time_scale": 0.25,     # battle speed while a stroke is being drawn
	"march_overlap_speed": 0.6,  # × speed while a marching block passes through a friend
	"battle_seconds": 90.0,
}

static var terrain_mods := {
	"hill_height_threshold": 8.0,     # world height difference that counts as upslope
	"hill_damage_dealt": 1.25,
	"hill_damage_taken": 0.75,
	"hill_charge_multiplier": 0.5,    # charging uphill
	"hill_range_bonus": 1.2,
	"forest_hidden_range": 40.0,
	"forest_cavalry_speed": 0.5,
	"forest_archer_range": 0.5,
	"swamp_speed": 0.5,
	"swamp_morale_drain": 2.0,
	"road_speed": 1.25,
}

static var strategic := {
	"engagement_range": 60.0,
	"battle_crop": Vector2(300, 200),
	"army_move_budget": 260.0,
}

## Supply stub: scales damage dealt and starting morale.
static func supply_multiplier(supply: float) -> float:
	return 0.5 + 0.5 * clampf(supply, 0.0, 1.0)

static func unit(role: int) -> Dictionary:
	return units[role]

## Run structure. Three eras; the crisis occupies the last third of each.
static var run := {
	"turns_per_era": 24,
	"eras": 3,
}

## Base per-turn yields and capacities per site kind (Appendix B table).
## WS-F multiplies by posture/culture/unrest; WS-A reads capacities.
static var sites := {
	"farm_supply": 6.0,
	"farm_forage_regiments": 3,
	"village_levy_every_turns": 2,
	"village_forage_regiments": 1,
	"mine_coin": 4.0,
	"market_coin": 3.0,
	"market_forage_regiments": 2,
	"market_trade_multiplier": 1.5,
	"node_coin": 2.0,
	"depot_max_stock": 120.0,
}

## Logistics (Appendix B): upkeep, hop loss, movement, depots, starvation,
## pillage. WS-A reads these through SupplyRules; nobody indexes them directly.
static var logistics := {
	"upkeep_per_regiment": 2.0,        # Supply one regiment eats per turn
	"big_stack": 8,                    # above this many regiments: upkeep ×1.5, movement 3
	"big_stack_upkeep": 1.5,
	"huge_stack": 12,                  # above this: upkeep ×2, movement 2
	"huge_stack_upkeep": 2.0,
	"hop_loss_road": 0.10,
	"hop_loss_river": 0.05,
	"hop_loss_trail": 0.20,
	"hop_loss_mountain": 0.35,
	"move_cost_road": 1,
	"move_cost_river": 1,
	"move_cost_trail": 2,
	"move_cost_mountain": 3,
	"move_points": 4,
	"move_points_big": 3,
	"move_points_huge": 2,
	"raider_max_regiments": 3,         # a stack this small is a raider
	"raider_move_points": 5,
	"depot_cost": 40.0,
	"depot_build_turns": 2,
	"depot_farm_reach": 3,             # hops a farm's yield travels to its depot
	"depot_initial_stock": 60.0,       # what every depot opens the run with
	"level_gain": 10.0,                # supply level change when fully fed
	"level_loss_per_shortfall": 5.0,   # × (shortfall / regiments) when not
	"supply_warning": 50.0,            # the level whose crossing is logged
	"desertion_below": 30.0,
	"desertion_every": 2,              # turns under the threshold per regiment lost
	"slow_below": 10.0,                # movement halved under this level
	"pillage_farm_turns": 2,           # yield destroyed per turn pillaged
	"pillage_village_coin": 2.0,
	"pillage_village_turns": 4,
	"pillage_mine_coin": 8.0,
	"pillage_mine_turns": 6,
	"pillage_market_coin": 10.0,
	"pillage_market_turns": 3,
	"pillage_node_turns": 3,
	"detach_quality": 0.5,             # a detachment with no leader of its own
	"marcher_split_below": 40.0,       # scripted marcher splits under this level
}

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
