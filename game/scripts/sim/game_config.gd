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
		"speed": 20.0,
		"melee_dps": 8.0,
		"ranged_dps": 0.0,
		"range": 0.0,
		"charge_burst": 0.0,
		"can_brace": true,
	},
	Role.CAVALRY: {
		"name": "Cavalry",
		"mark": "cavalry",
		"size": Vector2(20, 12),
		"health": 80.0,
		"morale": 90.0,
		"speed": 45.0,
		"melee_dps": 6.0,
		"ranged_dps": 0.0,
		"range": 0.0,
		"charge_burst": 40.0,
		"can_brace": false,
	},
	Role.ARCHERS: {
		"name": "Archers",
		"mark": "archers",
		"size": Vector2(24, 10),
		"health": 60.0,
		"morale": 70.0,
		"speed": 20.0,
		"melee_dps": 3.0,
		"ranged_dps": 5.0,
		"range": 120.0,
		"charge_burst": 0.0,
		"can_brace": false,
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
