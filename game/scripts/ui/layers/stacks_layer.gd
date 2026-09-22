class_name StacksLayer
extends MapLayer

## Armies on the map: one disc per stack, and the click handling that selects
## one and points it at an adjacent site.
##
## Nothing moves here. A pending order is `stack.path`, which MovementPhase
## walks on End Turn (a later workstream); this layer only writes it and draws
## it, so the shell is honest about what is and is not simulated yet.

const DISC := 12.0                  # marker radius, screen pixels

## The top of the stack, and it stays there: armies are what the player clicks,
## so no overlay may draw over them or take a click before them.
func order() -> int:
	return 100

func buttons() -> Array[Dictionary]:
	var clear := func() -> void:
		if view.selected != null:
			view.selected.path.clear()
	var has_order := func() -> bool:
		return view.selected != null and not view.selected.path.is_empty()
	return [{"label": "Clear order", "action": clear, "enabled": has_order}]

# -------------------------------------------------------------------- drawing

func draw(canvas: CanvasItem) -> void:
	if view.world == null:
		return
	for s in view.world.stacks:
		_draw_path(canvas, s)
	for s in view.world.stacks:
		_draw_stack(canvas, s)

func _draw_stack(canvas: CanvasItem, s: Stack) -> void:
	var at := view.w2s(view.stack_pos(s))
	var col := view.world.nation(s.nation_id).color
	canvas.draw_circle(at, DISC, col.darkened(0.35))
	canvas.draw_arc(at, DISC, 0.0, TAU, 24, col.lightened(0.35), 2.0)
	if view.selected == s:
		canvas.draw_arc(at, DISC + 5.0, 0.0, TAU, 28, ThemeColors.TEXT, 1.5)
	canvas.draw_string(view.font, at + Vector2(DISC + 5.0, 4.0),
		"%d rgt · %d%%" % [s.size(), int(round(s.supply))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lightened(0.5))

## The pending route: dashed, because it has not happened yet.
func _draw_path(canvas: CanvasItem, s: Stack) -> void:
	if s.path.is_empty():
		return
	var col := view.world.nation(s.nation_id).color * Color(1, 1, 1, 0.8)
	var from := view.w2s(view.stack_pos(s))
	for sid in s.path:
		var to := view.w2s(view.world.graph.site(sid).pos)
		MapLayer.dashes(canvas, from, to, col, 2.5, 12.0, 0.5)
		canvas.draw_arc(to, 5.0, 0.0, TAU, 16, col, 1.5)
		from = to

# ---------------------------------------------------------------------- input

## A click on a stack selects it. A click on a site with one of your own
## stacks selected points that stack at the site, if an edge joins the two.
func pressed(world_pos: Vector2) -> bool:
	if view.world == null:
		return false
	var hit := view.stack_at(world_pos)
	if hit != null:
		# Clicking the selected stack again deselects it.
		if view.selected == hit:
			view.selected = null
		else:
			view.selected = hit
		return true

	var s := view.selected
	if s == null or view.world.player() == null or s.nation_id != view.world.player().id:
		return false
	var site := view.site_at(world_pos)
	if site == null or site.id == s.site_id:
		return false
	if view.world.graph.edge_between(s.site_id, site.id) == null:
		return false
	s.path = [site.id] as Array[int]
	return true

# ------------------------------------------------------------------- tooltips

func tooltip(world_pos: Vector2) -> String:
	if view.world == null:
		return ""
	var s := view.stack_at(world_pos)
	if s == null:
		return ""
	var lines: PackedStringArray = ["%s — %s" % [s.label, _roster(s)]]
	lines.append("Supply %d%%%s" % [int(round(s.supply)), _destination(s)])
	if not s.supply_report.is_empty():
		var parts: PackedStringArray = []
		for key in s.supply_report:
			parts.append("%s %s" % [str(key).replace("_", " "), str(s.supply_report[key])])
		lines.append(", ".join(parts))
	return "\n".join(lines)

func _roster(s: Stack) -> String:
	var counts := {}
	for r in s.regiments:
		counts[r] = int(counts.get(r, 0)) + 1
	var parts: PackedStringArray = []
	for role in GameConfig.Role.values():
		if counts.has(role):
			parts.append("%d %s" % [counts[role], str(GameConfig.unit(role)["name"]).to_lower()])
	return ", ".join(parts) if parts.size() > 0 else "empty"

func _destination(s: Stack) -> String:
	if s.path.is_empty():
		return ""
	return " · ordered to %s" % view.world.graph.site(s.path[s.path.size() - 1]).name
