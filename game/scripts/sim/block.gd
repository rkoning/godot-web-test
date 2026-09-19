class_name Block
extends RefCounted

## One unit on the battlefield: a rectangle with a role, a facing, health and
## morale. Pure data plus geometry — everything that changes a block is done by
## BattleSim, so the whole fight can run headless.
##
## A block is a line of troops, so its long side is the front: `size().x` is
## the frontage (across the facing) and `size().y` is the depth (along it).
## It moves and fights along the short axis, the way a formation does.

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
var shooting_id := -1                  # who the block loosed at this step, for the view
var hit_flash := 0.0                   # seconds of "just took damage" left, for the view

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

## (frontage, depth) in world units.
func size() -> Vector2:
	return stats()["size"]

func frontage() -> float:
	return size().x

func depth() -> float:
	return size().y

func alive() -> bool:
	return status == Status.ACTIVE and health > 0.0

## True when the block is on the field but not under the player's control.
func out_of_the_fight() -> bool:
	return routing or order == OrderType.WITHDRAW

func corners() -> PackedVector2Array:
	var half_depth := depth() * 0.5
	var half_front := frontage() * 0.5
	var f := Vector2.RIGHT.rotated(facing)
	var r := Vector2(-f.y, f.x)
	return PackedVector2Array([
		pos + f * half_depth + r * half_front,
		pos + f * half_depth - r * half_front,
		pos - f * half_depth - r * half_front,
		pos - f * half_depth + r * half_front,
	])

## Distance from a point to the block's edge, zero inside it. Picking uses
## this rather than the distance to the centre so a block is hit anywhere on
## its body, plus a finger's worth of padding around it.
func distance_to_point(p: Vector2) -> float:
	var local := (p - pos).rotated(-facing)
	var dx := maxf(absf(local.x) - depth() * 0.5, 0.0)
	var dy := maxf(absf(local.y) - frontage() * 0.5, 0.0)
	return Vector2(dx, dy).length()

## The middle of the front edge, where an attack on this block arrives.
func front_point() -> Vector2:
	return pos + Vector2.RIGHT.rotated(facing) * depth() * 0.5

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
