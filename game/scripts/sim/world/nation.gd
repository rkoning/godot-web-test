class_name Nation
extends RefCounted

## One faction. Player and AI nations are the same class; `is_player` only
## decides who issues the orders.

var id := -1
var name := ""
var color := Color.WHITE
var is_player := false
var coin := 0.0
var influence := 0.0
var alive := true
var weights := {}                 # AI personality (WS-D)
var access_tags := {}             # node tag -> turn it expires (WS-B)

static func from_dict(d: Dictionary) -> Nation:
	var n := Nation.new()
	n.id = int(d["id"])
	n.name = str(d["name"])
	n.color = Color(str(d.get("color", "ffffff")))
	n.is_player = bool(d.get("player", false))
	n.coin = float(d.get("coin", 0))
	n.influence = float(d.get("influence", 0))
	return n
