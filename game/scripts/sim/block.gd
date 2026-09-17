class_name Block
extends RefCounted

## One unit on the battlefield: a rectangle with a role, a facing, health and
## morale. Pure data plus geometry — everything that changes a block is done by
## BattleSim, so the whole fight can run headless.

enum OrderType { NONE, MOVE, ATTACK, HOLD, WITHDRAW }
enum Status { ACTIVE, FLED, DESTROYED }

var id := 0
var side := GameConfig.Side.PLAYER
var role := GameConfig.Role.INFANTRY
var pos := Vector2.ZERO
var facing := 0.0                      # radians; 0 = +x

var health := 100.0
var max_health := 100.0
var morale := 100.0
var max_morale := 100.0
var supply := 1.0

var order := OrderType.NONE
var order_point := Vector2.ZERO
var target_id := -1

var status := Status.ACTIVE
var routing := false
var rout_recover := 0.0                # seconds spent unengaged while routing
var braced := false
var hold_time := 0.0
var charge_cooldown := 0.0
var charge_run := 0.0                  # straight-line distance built up for a charge
var last_move_dir := Vector2.ZERO
var seen_ally_rout := false

# Bookkeeping for the result screen.
var withdrew := false
var ever_routed := false

func _init(p_id: int, p_side: int, p_role: int, p_pos: Vector2, p_facing: float, p_supply: float) -> void:
	id = p_id
	side = p_side
	role = p_role
	pos = p_pos
	facing = p_facing
	supply = p_supply
	var u := GameConfig.unit(role)
	max_health = u["health"]
	health = max_health
	max_morale = u["morale"]
	# Supply stub scales starting morale as well as damage dealt.
	morale = max_morale * GameConfig.supply_multiplier(supply)

func stats() -> Dictionary:
	return GameConfig.unit(role)

func size() -> Vector2:
	return stats()["size"]

func alive() -> bool:
	return status == Status.ACTIVE and health > 0.0

## True when the block is on the field but not under the player's control.
func out_of_the_fight() -> bool:
	return routing or order == OrderType.WITHDRAW

func corners() -> PackedVector2Array:
	var s := size() * 0.5
	var f := Vector2.RIGHT.rotated(facing)
	var r := Vector2(-f.y, f.x)
	return PackedVector2Array([
		pos + f * s.x + r * s.y,
		pos + f * s.x - r * s.y,
		pos - f * s.x - r * s.y,
		pos - f * s.x + r * s.y,
	])

## Separating-axis test between two oriented rectangles. Touching counts as
## overlapping, which is what "engaged" means in the spec.
func touches(other: Block) -> bool:
	return _overlaps(other, 0.0)

## Real interpenetration rather than contact. Blocks may touch — that is what
## being engaged means — but they may not stand in the same space, which is what
## makes a one-block-wide bridge a chokepoint instead of a queue of stacked
## blocks all fighting at once.
func overlaps_deeply(other: Block, slack := 5.0) -> bool:
	return _overlaps(other, slack)

func _overlaps(other: Block, slack: float) -> bool:
	# Cheap reject first: the fight has few blocks but this runs every pair,
	# every frame.
	var reach := (size().length() + other.size().length()) * 0.5
	if pos.distance_squared_to(other.pos) > reach * reach:
		return false

	var a := corners()
	var b := other.corners()
	for axis in [
		Vector2.RIGHT.rotated(facing), Vector2.UP.rotated(facing),
		Vector2.RIGHT.rotated(other.facing), Vector2.UP.rotated(other.facing),
	]:
		var a_lo := INF
		var a_hi := -INF
		for p in a:
			var d: float = p.dot(axis)
			a_lo = minf(a_lo, d)
			a_hi = maxf(a_hi, d)
		var b_lo := INF
		var b_hi := -INF
		for p in b:
			var d: float = p.dot(axis)
			b_lo = minf(b_lo, d)
			b_hi = maxf(b_hi, d)
		if a_hi - slack < b_lo or b_hi - slack < a_lo:
			return false
	return true

## Which arc an attack coming from `from` lands in: "front", "flank" or "rear".
func arc_from(from: Vector2) -> String:
	var to_attacker := (from - pos)
	if to_attacker.length_squared() < 0.0001:
		return "front"
	var angle := absf(rad_to_deg(Vector2.RIGHT.rotated(facing).angle_to(to_attacker)))
	if angle <= 45.0:
		return "front"
	if angle <= 135.0:
		return "flank"
	return "rear"

func face_towards(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		facing = dir.angle()
