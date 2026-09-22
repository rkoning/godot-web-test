class_name Site
extends RefCounted

## A point on the map where a resource lives. Every resource in the game is on
## a site; regions are only containers. FEATURE sites hold nothing and exist so
## a hill or a ford is somewhere an army can stand.

enum Kind { FARM, VILLAGE, MINE, MARKET, DEPOT, NODE, FEATURE }

var id := -1
var region_id := -1
var kind := Kind.FEATURE
var pos := Vector2.ZERO           # world units on the Terrain
var name := ""
var stock := 0.0                  # depot stock (WS-A); farms keep nothing here
var node_tag := ""                # NODE only: horses | iron | grain | salt | timber | dye
var garrison_nation := -1         # who holds this site (WS-A occupation), -1 = nobody
var pillaged_until := 0           # yields suppressed while world.turn < this (WS-A)

static func from_dict(d: Dictionary) -> Site:
	var s := Site.new()
	s.id = int(d["id"])
	s.region_id = int(d["region"])
	s.kind = Kind[str(d["kind"]).to_upper()]
	s.pos = Vector2(d["pos"][0], d["pos"][1])
	s.name = str(d.get("name", "%s %d" % [str(d["kind"]).capitalize(), s.id]))
	s.node_tag = str(d.get("tag", ""))
	return s
