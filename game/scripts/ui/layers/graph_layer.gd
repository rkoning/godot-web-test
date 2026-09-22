class_name GraphLayer
extends MapLayer

## The map itself: regions, edges and sites. The bottom layer, so everything
## else is drawn over it.
##
## Regions are the convex hull of their sites, grown outward so a three-site
## region reads as a territory rather than a razor-thin triangle, tinted with
## its owner's colour. Edges are styled by kind, and an edge severed for the
## player (a hostile stack standing on either end) is overdrawn dashed red —
## the one piece of logistics state that has to be visible at a glance.

const REGION_PAD := 30.0            # world units the hull grows past its sites
const GLYPH := 7.0                  # site glyph radius, screen pixels
const LABEL_ZOOM := 1.0             # zoom above which every site is labelled

var show_labels := false            # the Labels button forces them on

## The bottom of the stack: the map everything else is drawn on top of.
func order() -> int:
	return 0

func buttons() -> Array[Dictionary]:
	var toggle := func() -> void:
		show_labels = not show_labels
	var always := func() -> bool:
		return true
	return [{"label": "Labels", "action": toggle, "enabled": always}]

# -------------------------------------------------------------------- drawing

func draw(canvas: CanvasItem) -> void:
	if view.world == null:
		return
	_draw_regions(canvas)
	_draw_edges(canvas)
	_draw_sites(canvas)

func _draw_regions(canvas: CanvasItem) -> void:
	var world := view.world
	for r in world.graph.regions:
		var hull := _region_hull(r)
		if hull.size() < 3:
			continue
		var col := ThemeColors.TEXT_DIM
		if r.owner >= 0:
			col = world.nation(r.owner).color
		var screen := PackedVector2Array()
		for p in hull:
			screen.append(view.w2s(p))
		canvas.draw_colored_polygon(screen, col * Color(1, 1, 1, 0.16))
		screen.append(screen[0])
		canvas.draw_polyline(screen, col * Color(1, 1, 1, 0.45), 1.5)

## The region's outline in world units. An authored `Region.polygon` wins —
## WS-J's map ships real borders — and otherwise the outline is derived: the
## convex hull of the region's sites, pushed `REGION_PAD` away from the hull's
## centre. Three sites in a line hull to a segment (Ironhold does), so that case
## is fattened into a stadium instead.
func _region_hull(r: Region) -> PackedVector2Array:
	if not r.polygon.is_empty():
		return r.polygon
	var pts := PackedVector2Array()
	for sid in r.sites:
		pts.append(view.world.graph.site(sid).pos)
	if pts.size() < 2:
		return PackedVector2Array()
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)

	var centre := Vector2.ZERO
	for p in hull:
		centre += p
	centre /= float(hull.size())

	var grown := PackedVector2Array()
	for p in hull:
		var out := p - centre
		if out.length() < 0.01:
			out = Vector2(REGION_PAD, 0.0)
		else:
			out = out.normalized() * (out.length() + REGION_PAD)
		grown.append(centre + out)
	if grown.size() >= 3:
		return grown
	var fat := Geometry2D.offset_polyline(grown, REGION_PAD,
		Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	return fat[0] if fat.size() > 0 else PackedVector2Array()

func _draw_edges(canvas: CanvasItem) -> void:
	var world := view.world
	var player := world.player()
	for e in world.graph.edges:
		var a := view.w2s(world.graph.site(e.a).pos)
		var b := view.w2s(world.graph.site(e.b).pos)
		match e.kind:
			Edge.Kind.ROAD:
				canvas.draw_line(a, b, ThemeColors.ROAD.lightened(0.25), 3.0)
			Edge.Kind.RIVER:
				canvas.draw_line(a, b, ThemeColors.WATER.lightened(0.35), 5.0)
			Edge.Kind.TRAIL:
				MapLayer.dashes(canvas, a, b, ThemeColors.ROAD.lightened(0.1), 2.0, 7.0, 0.35)
			Edge.Kind.MOUNTAIN:
				MapLayer.dashes(canvas, a, b, ThemeColors.CLIFF.lightened(0.35), 3.0, 14.0, 0.6)
		if player != null and world.is_severed(e, player.id):
			MapLayer.dashes(canvas, a, b, ThemeColors.ENEMY, 3.0, 12.0, 0.5)

func _draw_sites(canvas: CanvasItem) -> void:
	var hovered := view.site_at(view.hover_world)
	for s in view.world.graph.sites:
		var at := view.w2s(s.pos)
		_draw_glyph(canvas, s, at)
		if show_labels or view.camera.zoom > LABEL_ZOOM or s == hovered:
			var col := ThemeColors.TEXT if s == hovered else ThemeColors.TEXT_DIM
			canvas.draw_string(view.font, at + Vector2(0.0, GLYPH + 13.0), s.name,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 11, col)

## A shape per site kind, drawn at a fixed screen size. Shapes rather than
## letters: the fallback font has no glyph for a pickaxe, and a missing glyph
## renders as an empty box.
func _draw_glyph(canvas: CanvasItem, s: Site, at: Vector2) -> void:
	var edge := ThemeColors.TEXT * Color(1, 1, 1, 0.8)
	match s.kind:
		Site.Kind.FARM:
			canvas.draw_circle(at, GLYPH, ThemeColors.ACCENT.darkened(0.15))
			canvas.draw_arc(at, GLYPH, 0.0, TAU, 20, edge, 1.0)
		Site.Kind.VILLAGE:
			var r := Rect2(at - Vector2(GLYPH, GLYPH) * 0.7, Vector2(GLYPH, GLYPH) * 1.4)
			canvas.draw_rect(r, ThemeColors.TEXT_DIM, true)
			canvas.draw_rect(r, edge, false, 1.0)
		Site.Kind.MINE:
			MapLayer.polygon(canvas, at, GLYPH * 1.15, 3, ThemeColors.CLIFF.lightened(0.25), edge)
		Site.Kind.MARKET:
			MapLayer.polygon(canvas, at, GLYPH * 1.2, 4, ThemeColors.WARN, edge)
		Site.Kind.DEPOT:
			_draw_depot(canvas, s, at, edge)
		Site.Kind.NODE:
			MapLayer.polygon(canvas, at, GLYPH * 1.2, 6, ThemeColors.PANEL_EDGE.lightened(0.3), edge)
			if s.node_tag != "":
				canvas.draw_string(view.font, at + Vector2(-3.5, 4.0),
					s.node_tag.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, edge)
		Site.Kind.FEATURE:
			canvas.draw_arc(at, GLYPH, 0.0, TAU, 20, ThemeColors.TEXT_DIM, 1.5)

## A depot is a square that fills up: how much it is holding, against the
## capacity `Yields` reports, is the number the supply system lives or dies by.
func _draw_depot(canvas: CanvasItem, s: Site, at: Vector2, edge: Color) -> void:
	var box := Rect2(at - Vector2(GLYPH, GLYPH), Vector2(GLYPH, GLYPH) * 2.0)
	canvas.draw_rect(box, ThemeColors.PANEL, true)
	var cap: float = maxf(Yields.depot_capacity(s, view.world), 0.001)
	var full: float = clampf(s.stock / cap, 0.0, 1.0)
	if full > 0.0:
		canvas.draw_rect(Rect2(box.position + Vector2(0.0, box.size.y * (1.0 - full)),
			Vector2(box.size.x, box.size.y * full)), ThemeColors.ACCENT, true)
	canvas.draw_rect(box, edge, false, 1.0)

# ------------------------------------------------------------------- tooltips

func tooltip(world_pos: Vector2) -> String:
	if view.world == null:
		return ""
	var s := view.site_at(world_pos)
	if s == null:
		return ""
	var world := view.world
	var region := world.graph.region_of(s.id)
	var owner := "unowned"
	if region.owner >= 0:
		owner = world.nation(region.owner).name
	return "%s — %s. Owner: %s. Posture: %s. Supply +%.0f, Coin +%.0f" % [
		s.name,
		Site.Kind.keys()[s.kind].capitalize(),
		owner,
		Region.Posture.keys()[region.posture].capitalize(),
		Yields.supply(s, region, world),
		Yields.coin(s, region, world),
	]
