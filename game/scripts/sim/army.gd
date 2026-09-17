class_name Army
extends RefCounted

## A strategic-zoom army: a point on the map plus the blocks it will field.

var side := GameConfig.Side.PLAYER
var pos := Vector2.ZERO
var supply := 1.0
var roster: Array[int] = []              # GameConfig.Role values
var path: PackedVector2Array = []        # remaining waypoints
var scripted: PackedVector2Array = []    # enemy-only: where it walks each turn
var behavior := ""                       # battle AI mode for this army
var moved_this_turn := false
var label := "Army"

func _init(p_side: int, p_pos: Vector2, p_roster: Array[int], p_supply: float) -> void:
	side = p_side
	pos = p_pos
	roster = p_roster
	supply = p_supply
