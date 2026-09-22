class_name MapLayer
extends RefCounted

## One stratum of the campaign map: it draws, it answers hover, it consumes
## clicks, and it may contribute HUD buttons.
##
## This is the seam every workstream builds its map presentation on. A layer
## touches only its own file, its own `order()` decides both draw order and
## input priority (so `CampaignRoot.LAYERS` can be appended to in any position),
## and nobody has to edit anybody else's renderer to add a system's overlay.
## Layers read the `World` through `view` and issue orders by writing order
## fields on it — no rules live here.
##
## The contract is frozen: `draw`, `tooltip`, `pressed`, `buttons`, `order`,
## `panel`.
##   draw     — paint, converting world to screen through `view.w2s`
##   tooltip  — text for a hover, first non-empty wins, top layer asked first
##   pressed  — true when the click was consumed, top layer asked first
##   buttons  — [{label: String, action: Callable, enabled: Callable}]
##   order    — where in the stack this layer sits
##   panel    — an optional side panel, or null

var view: MapView

func draw(_canvas: CanvasItem) -> void:
	pass

func tooltip(_world_pos: Vector2) -> String:
	return ""

func pressed(_world_pos: Vector2) -> bool:
	return false

func buttons() -> Array[Dictionary]:
	return []

## Draw order and input priority; lower draws first and answers last.
## `StacksLayer` is 100 and stays on top; workstreams use 10–90.
##
## The number rather than the registry position is the seam: `CampaignRoot`
## sorts by it, so a workstream appends its layer to `LAYERS` in any position
## and still lands where it means to, and no two streams ever conflict over a
## line of that array.
func order() -> int:
	return 0

## An optional side panel `CampaignRoot` hosts in a right-hand column, or null
## for a layer that only draws on the map. Return the same instance each call —
## it is asked once at build time and again whenever the column is rebuilt, and
## a fresh `Control` per call would leak a node per rebuild.
func panel() -> Control:
	return null

# ------------------------------------------------------- shared drawing helpers

## A dashed line between two screen points. `period` is the dash pitch in
## pixels and `duty` how much of it is ink, so the same call draws a road's
## long dashes and a trail's dots.
static func dashes(canvas: CanvasItem, from: Vector2, to: Vector2, col: Color,
		width := 2.0, period := 12.0, duty := 0.5) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var s := 0.0
	while s < length:
		var e: float = minf(s + period * duty, length)
		canvas.draw_line(from + dir * s, from + dir * e, col, width)
		s += period

## A regular polygon of `sides` at a screen point, filled and outlined. Site
## glyphs are all drawn through this so they share one size and one weight.
static func polygon(canvas: CanvasItem, at: Vector2, radius: float, sides: int,
		fill: Color, edge: Color, rotation := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(at + Vector2.UP.rotated(rotation + TAU * float(i) / float(sides)) * radius)
	canvas.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	canvas.draw_polyline(pts, edge, 1.0)
