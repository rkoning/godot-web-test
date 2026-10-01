class_name SupplyLayer
extends MapLayer

## Supply as a thing you can see: which way every army's level is going, how
## far its food travels, and — for the selected army — the road it comes by.
##
## Draws only. Every number is read from the report `SupplyPhase` wrote on the
## stack, so the picture and the arithmetic cannot disagree; no rule and no
## order lives here. It sits at 50, between the map and the armies, so the
## trend glyph never covers a stack's disc or steals its click.

const ARROW := 6.0                  # trend glyph half-height, screen pixels

func order() -> int:
	return 50

func draw(canvas: CanvasItem) -> void:
	if view.world == null:
		return
	if view.selected != null and view.world.stacks.has(view.selected):
		_draw_route(canvas, view.selected)
	for s in view.world.stacks:
		_draw_trend(canvas, s)

## An up or down arrow left of the stacks layer's label, and the hop count of
## the route feeding it. Silent on turn 1: nothing has been resolved yet, and an
## arrow drawn from no data would be a lie rather than a default.
func _draw_trend(canvas: CanvasItem, s: Stack) -> void:
	if s.supply_report.is_empty():
		return
	var at := view.w2s(view.stack_pos(s)) + Vector2(-StacksLayer.DISC - ARROW - 4.0, 0.0)
	var delta := float(s.supply_report["delta"])
	var up := delta >= 0.0
	var col := ThemeColors.ACCENT if up else ThemeColors.ENEMY
	var tip := at + Vector2(0.0, -ARROW if up else ARROW)
	var base := at + Vector2(0.0, ARROW if up else -ARROW)
	canvas.draw_colored_polygon(PackedVector2Array([
		tip, base + Vector2(-ARROW, 0.0), base + Vector2(ARROW, 0.0)]), col)
	var hops := int(s.supply_report["hops"])
	if hops >= 0:
		canvas.draw_string(view.font, at + Vector2(-ARROW - 30.0, 4.0),
			"%d hop%s" % [hops, "" if hops == 1 else "s"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ThemeColors.TEXT_DIM)

## The selected army's supply line: the route `Pathing.nearest_depot` chose,
## dotted from the army back to the depot that is feeding it. Nothing is drawn
## when no depot is in reach — the tooltip says why.
func _draw_route(canvas: CanvasItem, s: Stack) -> void:
	if s.supply_report.is_empty() or int(s.supply_report["depot_id"]) < 0:
		return
	var col := view.world.nation(s.nation_id).color.lightened(0.2)
	var from := view.w2s(view.stack_pos(s))
	for sid in s.supply_report["route"]:
		var to := view.w2s(view.world.graph.site(sid).pos)
		MapLayer.dashes(canvas, from, to, col, 2.0, 6.0, 0.4)
		from = to
