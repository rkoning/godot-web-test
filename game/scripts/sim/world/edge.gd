class_name Edge
extends RefCounted

## A road, river, trail or mountain pass between two sites. Edges cross region
## borders freely; movement, supply and caravans all travel along them.

enum Kind { ROAD, RIVER, TRAIL, MOUNTAIN }

var id := -1
var a := -1
var b := -1
var kind := Kind.ROAD

func other(site_id: int) -> int:
	return b if site_id == a else a

static func from_dict(d: Dictionary, p_id: int) -> Edge:
	var e := Edge.new()
	e.id = p_id
	e.a = int(d["a"])
	e.b = int(d["b"])
	e.kind = Kind[str(d.get("kind", "road")).to_upper()]
	return e
