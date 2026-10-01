class_name BattleLayer
extends MapLayer

## WS-C: the campaign's battles. Marks every fight waiting for the player,
## explains it on hover (with the auto-resolve ratio), and puts it on screen in
## a BattleView over the map; the result goes back to the world through
## BattleBridge. AI fights and trivial ones never reach here — EngagementPhase
## resolved them already, and the log says how.

const MARKER_LIFT := 30.0            # screen px above the site
const MARKER_RADIUS := 12.0

var current: BattleView = null
var _battle := {}
var _world: World = null
var _applied := false

func order() -> int:
	return 90

func has_waiting() -> bool:
	if view == null or view.world == null:
		return false
	for b in view.world.pending_battles:
		if BattleBridge.valid(view.world, b):
			return true
	return false

func buttons() -> Array[Dictionary]:
	return [{"label": "Fight battle", "action": open_next, "enabled": has_waiting}]

func open_next() -> void:
	if view == null or view.world == null:
		return
	for b in view.world.pending_battles:
		if BattleBridge.valid(view.world, b):
			open(b)
			return

func open(battle: Dictionary) -> void:
	var host := view.get_parent() as CampaignRoot
	if host == null or current != null or not BattleBridge.valid(view.world, battle):
		return
	var crop: Vector2 = GameConfig.strategic["battle_crop"]
	var area := view.map_area()
	if area.size.y > area.size.x:
		crop = Vector2(crop.y, crop.x)
	var sim := BattleBridge.start(view.world, view.terrain, battle, crop)
	_battle = battle
	_world = view.world
	_applied = false
	current = BattleView.new()
	current.insets = func() -> Vector2: return Vector2(view.inset_top, view.inset_bottom)
	current.result_actions = [{"label": "Back to the campaign", "action": _finish}]
	host.set_overlay(current)
	current.open(view.terrain, sim, BattleView.detect_touch())
	# Every frame, check that the battle on screen still exists (see _watch).
	current.get_tree().process_frame.connect(_watch)

func _finish() -> void:
	if current == null:
		return
	if not _applied and _still_pending() and current.sim.finished:
		BattleBridge.apply_result(_world, current.sim, _battle)
		_applied = true
	_close()

## End Turn, Reset and the scenario picker stay clickable over the battle.
## Before the result is applied, any of them makes this battle stale and the
## view goes without touching the world (a lost fight must not be a free
## re-roll, but nor may it be applied twice). The instant the sim finishes,
## the result is written back here — not only when the player clicks through
## — so the view stays up afterwards showing the result until the button
## closes it, unless the world itself changed underneath it (Reset, the
## scenario picker).
func _watch() -> void:
	if current == null:
		return
	if not _applied:
		if current.sim.finished and _still_pending():
			BattleBridge.apply_result(_world, current.sim, _battle)
			_applied = true
			return
		if not _still_pending():
			_close()
		return
	if view.world != _world:
		_close()

## By identity, not value: End Turn re-collects an unfought standoff as a new
## dictionary with the same stacks in it, and that is a different battle —
## the one on screen was cancelled.
func _still_pending() -> bool:
	if view.world != _world:
		return false
	for b in _world.pending_battles:
		if is_same(b, _battle):
			return true
	return false

func _close() -> void:
	if current == null:
		return
	var tree := current.get_tree()
	if tree != null and tree.process_frame.is_connected(_watch):
		tree.process_frame.disconnect(_watch)
	var host := view.get_parent() as CampaignRoot
	if host != null:
		host.clear_overlay()
	current.queue_free()
	current = null
	_battle = {}
	_world = null
	_applied = false
	view.queue_redraw()

func _marker(battle: Dictionary) -> Vector2:
	return view.w2s(view.world.graph.sites[battle["site_id"]].pos) + Vector2(0, -MARKER_LIFT)

func draw(canvas: CanvasItem) -> void:
	if view.world == null:
		return
	for b in view.world.pending_battles:
		if not BattleBridge.valid(view.world, b):
			continue
		var at := _marker(b)
		canvas.draw_circle(at, MARKER_RADIUS, ThemeColors.BACKGROUND)
		canvas.draw_arc(at, MARKER_RADIUS, 0.0, TAU, 24, ThemeColors.ACCENT, 2.0)
		canvas.draw_line(at + Vector2(-6, -6), at + Vector2(6, 6), ThemeColors.TEXT, 2.0)
		canvas.draw_line(at + Vector2(6, -6), at + Vector2(-6, 6), ThemeColors.TEXT, 2.0)
		canvas.draw_string(view.font, at + Vector2(MARKER_RADIUS + 4, 5),
			"×%.1f" % float(b.get("ratio", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ThemeColors.TEXT)

func _battle_at_screen(screen: Vector2) -> Dictionary:
	for b in view.world.pending_battles:
		if not BattleBridge.valid(view.world, b):
			continue
		if _marker(b).distance_to(screen) <= MARKER_RADIUS + 6.0:
			return b
	return {}

func tooltip(world_pos: Vector2) -> String:
	if view.world == null:
		return ""
	var b := _battle_at_screen(view.w2s(world_pos))
	if b.is_empty():
		return ""
	var mine := BattleBridge.player_stack(view.world, b)
	if mine == null:
		return ""
	var theirs := BattleBridge.other(b, mine)
	return "Battle at %s: your %d regiments vs %d · strength ratio %.1f (auto-resolves at %.1f)" % [
		view.world.graph.sites[b["site_id"]].name, mine.size(), theirs.size(),
		float(b.get("ratio", 0.0)), float(GameConfig.battle_bridge["auto_resolve_ratio"]),
	]

func pressed(world_pos: Vector2) -> bool:
	if view.world == null:
		return false
	var b := _battle_at_screen(view.w2s(world_pos))
	if b.is_empty():
		return false
	open(b)
	return true
