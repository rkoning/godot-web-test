class_name Contact
extends RefCounted

## One lock between two enemy blocks in contact (spec 2026-09-23). The
## initiator is pulled flush against the face of the target it struck; the
## damage each deals the other through this contact is smoothed into pressure,
## and whoever is ahead by more than `push_deadband` pushes the other back.

var initiator: Block
var target: Block
var face := "front"            # side of the target the initiator struck
var pressure := {}             # block id -> smoothed damage per second through this lock
var _dealt := {}               # block id -> damage dealt through this lock this step

## A new lock. The initiator is the block whose front points more squarely at
## the other (ties: lower id), so a charge that arrives is the one that seats.
static func begin(a: Block, b: Block) -> Contact:
	var c := Contact.new()
	var da := Vector2.RIGHT.rotated(a.facing).dot((b.pos - a.pos).normalized())
	var db := Vector2.RIGHT.rotated(b.facing).dot((a.pos - b.pos).normalized())
	var a_first := da > db or (is_equal_approx(da, db) and a.id < b.id)
	c.initiator = a if a_first else b
	c.target = b if a_first else a
	c.face = face_of(c.target, c.initiator.pos)
	c.pressure = {a.id: 0.0, b.id: 0.0}
	c._dealt = {a.id: 0.0, b.id: 0.0}
	return c

## Which side of `target` a point lies on, by the 45°/135° arc rule; the flank
## is split by which side of the facing line the point falls.
static func face_of(target: Block, from: Vector2) -> String:
	var arc := target.arc_from(from)
	if arc != "flank":
		return arc
	var local := (from - target.pos).rotated(-target.facing)
	return "left" if local.y < 0.0 else "right"

## Unit vector out of that face of `target`.
static func normal(target: Block, p_face: String) -> Vector2:
	var f := Vector2.RIGHT.rotated(target.facing)
	match p_face:
		"rear": return -f
		"left": return f.rotated(-PI / 2.0)
		"right": return f.rotated(PI / 2.0)
	return f

## Distance from the target's centre to that face.
static func half_extent(target: Block, p_face: String) -> float:
	return target.depth() * 0.5 if p_face == "front" or p_face == "rear" else target.frontage() * 0.5

func squares() -> bool:
	return face == "front"

func has(b: Block) -> bool:
	return b == initiator or b == target

func other(b: Block) -> Block:
	return target if b == initiator else initiator

func record(from: Block, amount: float) -> void:
	_dealt[from.id] = float(_dealt.get(from.id, 0.0)) + amount

## Fold this step's damage into the smoothed pressure.
func settle(dt: float) -> void:
	var k := clampf(dt / maxf(float(GameConfig.combat["push_smoothing"]), 0.001), 0.0, 1.0)
	for id in _dealt:
		var rate: float = float(_dealt[id]) / maxf(dt, 0.0001)
		pressure[id] = lerpf(float(pressure.get(id, 0.0)), rate, k)
		_dealt[id] = 0.0

func gap(b: Block) -> float:
	return float(pressure.get(b.id, 0.0)) - float(pressure.get(other(b).id, 0.0))

func loser() -> Block:
	var g := gap(initiator)
	if absf(g) <= float(GameConfig.combat["push_deadband"]):
		return null
	return target if g > 0.0 else initiator
