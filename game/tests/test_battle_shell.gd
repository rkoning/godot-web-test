extends RefCounted

## WS-C: the battle screen as a component. BattleView runs a sim and shows a
## result with the host's buttons; the combat prototype still builds on it; the
## campaign opens it over the map for a waiting battle and writes the result
## back (Task 6 adds that half).

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		t.check("a SceneTree root is available to host the scene", false)
		return
	_test_battle_view(tree)
	_test_reform_shows(tree)
	_test_view_input(tree)
	_test_drawing(tree)
	_test_click_to_shoot(tree)
	_test_off_centre_drag(tree)
	_test_drawing_edges(tree)
	_test_touch_pad_press(tree)
	_test_combat_scene_builds(tree)
	_test_campaign_battle_flow(tree)
	_test_result_applied_when_sim_finishes(tree)
	_test_has_waiting_ignores_invalid_battle(tree)
	_test_combat_scene_peek(tree)

func _test_battle_view(tree: SceneTree) -> void:
	print("\nBattleView runs a battle and ends on the host's buttons")
	var host := Control.new()
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := t.arena(terrain)
	sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(620, 400), 0.0)
	sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(680, 400), PI)
	var view := BattleView.new()
	var pressed := [0]
	view.result_actions = [{"label": "Continue", "action": func(): pressed[0] += 1}]
	host.add_child(view)
	view.open(terrain, sim, false)
	view._process(0.5)
	t.check("the view advances its sim while visible", sim.time > 0.0, str(sim.time))
	var before := sim.time
	view.visible = false
	view._process(0.5)
	t.check("a hidden view is a paused battle", is_equal_approx(sim.time, before))
	view.visible = true
	sim._finish("test")
	view._process(0.0)
	t.check("a finished sim shows the result panel", view.result_shown())
	var buttons := view.find_children("*", "Button", true, false)
	var cont: Button = null
	for b in buttons:
		if b.text == "Continue" and b.is_visible_in_tree():
			cont = b
	t.check("the host's action is on the result panel", cont != null)
	if cont != null:
		cont.pressed.emit()
	t.check("pressing it calls the host", pressed[0] == 1)
	t.check("terrain_texture is cached per terrain",
		BattleView.terrain_texture(terrain) == BattleView.terrain_texture(terrain))
	tree.root.remove_child(host)
	host.free()

func _test_reform_shows(tree: SceneTree) -> void:
	print("\nBattleView names a reform and a push")
	var host := Control.new()
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := BattleSim.new()
	sim.setup(terrain, Rect2(10, 10, 220, 160))
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	var p := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(120, 90), 0.0)
	var flank := sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(120, 50), PI / 2.0)
	sim.order_hold(p)
	sim.order_attack(flank, p)
	t.run_for(sim, 3.0)
	sim.order_attack(p, flank)
	var view := BattleView.new()
	host.add_child(view)
	view.open(terrain, sim, false)
	view.selection = [p] as Array[Block]
	view._process(0.1)
	t.check("the tag reads REFORMING", view._block_tag(p) == "REFORMING", view._block_tag(p))
	t.check("the tooltip says how long is left", view._block_state(p).begins_with("reforming ("),
		view._block_state(p))
	tree.root.remove_child(host)
	host.free()

func _click(view: BattleView, button: MouseButton, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.position = at
	e.pressed = pressed
	view._gui_input(e)

func _motion(view: BattleView, at: Vector2, relative := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.relative = relative
	view._gui_input(e)

func _test_view_input(tree: SceneTree) -> void:
	print("\nBattleView takes orders by mouse")
	var host := Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := t.arena(terrain)
	var mine := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(560, 400), 0.0)
	var foe := sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(760, 400), PI)
	var view := BattleView.new()
	host.add_child(view)
	view.open(terrain, sim, false)
	view._process(0.0)
	var cam := view.camera

	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), false)
	t.check("a left click selects the player's block", view.selection.size() == 1 and view.selection[0] == mine)

	var ground := cam.w2s(Vector2(640, 460))
	_click(view, MOUSE_BUTTON_RIGHT, ground, true)
	_click(view, MOUSE_BUTTON_RIGHT, ground, false)
	t.check("a right click on ground orders a move there",
		mine.order == Block.OrderType.MOVE and mine.order_point.distance_to(Vector2(640, 460)) < 1.0,
		"order %d at %s" % [mine.order, mine.order_point])

	_click(view, MOUSE_BUTTON_RIGHT, cam.w2s(foe.pos), true)
	_click(view, MOUSE_BUTTON_RIGHT, cam.w2s(foe.pos), false)
	t.check("a right click on an enemy orders an attack",
		mine.order == Block.OrderType.ATTACK and mine.target_id == foe.id)

	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(700, 480)), true)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(700, 480)), false)
	t.check("a left click on open ground deselects", view.selection.is_empty())

	var from := cam.w2s(Vector2(510, 320))
	var to := cam.w2s(Vector2(600, 480))
	_click(view, MOUSE_BUTTON_LEFT, from, true)
	_motion(view, to, to - from)
	_click(view, MOUSE_BUTTON_LEFT, to, false)
	t.check("a left drag box-selects", view.selection.size() == 1 and view.selection[0] == mine)

	var zoom := cam.zoom
	_click(view, MOUSE_BUTTON_WHEEL_UP, ground, true)
	t.check("the wheel zooms", cam.zoom > zoom)

	# Zoomed in about the field's centre there is room to pan either way.
	var mid := cam.w2s(sim.field.get_center())
	for i in 3:
		_click(view, MOUSE_BUTTON_WHEEL_UP, mid, true)
	var origin := cam.w2s(Vector2(600, 400))
	_click(view, MOUSE_BUTTON_MIDDLE, mid, true)
	_motion(view, mid + Vector2(40, 0), Vector2(40, 0))
	_click(view, MOUSE_BUTTON_MIDDLE, mid + Vector2(40, 0), false)
	t.check("a middle drag pans", cam.w2s(Vector2(600, 400)).x > origin.x + 1.0,
		"%s -> %s" % [origin, cam.w2s(Vector2(600, 400))])
	var order_before := mine.order
	var pt_before := mine.order_point
	_click(view, MOUSE_BUTTON_RIGHT, mid, true)
	_motion(view, mid + Vector2(40, 0), Vector2(40, 0))
	_click(view, MOUSE_BUTTON_RIGHT, mid + Vector2(40, 0), false)
	t.check("a right drag pans and gives no order",
		mine.order == order_before and mine.order_point == pt_before)

	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	view._unhandled_key_input(space)
	var before := sim.time
	view._process(0.5)
	t.check("space pauses the clock", view.paused and is_equal_approx(sim.time, before))
	view._unhandled_key_input(space)
	t.check("space again resumes it", not view.paused)

	# The defender arranges before Begin: drag a block, then start the clock.
	sim.started = false
	sim.player_is_defender = true
	view._refresh_hud()
	var start := mine.pos
	# The arena sits partly on water; drop on the first open ground in the field.
	var target := start
	for y in range(330, 480, 10):
		for x in range(530, 780, 10):
			if target == start and not terrain.is_blocked(Vector2(x, y), mine.role):
				target = Vector2(x, y)
	var grab := cam.w2s(mine.pos)
	var drop := cam.w2s(target)
	_click(view, MOUSE_BUTTON_LEFT, grab, true)
	_motion(view, drop, drop - grab)
	_click(view, MOUSE_BUTTON_LEFT, drop, false)
	t.check("the defender drags a block before Begin", mine.pos.distance_to(start) > 5.0,
		"%s -> %s" % [start, mine.pos])
	var begin: Button = view._hud["begin"]
	t.check("Begin shows before the clock starts", begin.is_visible_in_tree())
	begin.pressed.emit()
	t.check("Begin starts the clock", sim.started and not begin.visible)

	tree.root.remove_child(host)
	host.free()

func _test_drawing(tree: SceneTree) -> void:
	print("\nBattleView: drawing routes and formation lines")
	var host := Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := BattleSim.new()
	sim.setup(terrain, Rect2(10, 10, 220, 160))
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	var mine := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(50, 90), 0.0)
	var mate := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(50, 130), 0.0)
	var foe := sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(220, 160), PI)
	var view := BattleView.new()
	host.add_child(view)
	view.open(terrain, sim, false)
	view._process(0.0)
	var cam := view.camera

	var no_buttons := true
	for b in view.find_children("*", "Button", true, false):
		if b.text == "Move" or b.text == "Attack":
			no_buttons = false
	t.check("the Move and Attack buttons are gone", no_buttons)

	# Drag from a block: a route.
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	for p in [Vector2(80, 70), Vector2(120, 50), Vector2(160, 60)]:
		_motion(view, cam.w2s(p))
	t.check("time slows while drawing", is_equal_approx(view._time_scale(),
		float(GameConfig.combat["draw_time_scale"])), str(view._time_scale()))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(160, 60)), false)
	t.check("and returns to normal on release", is_equal_approx(view._time_scale(), 1.0))
	t.check("a drag from a block gives it a route", mine.order == Block.OrderType.MOVE and mine.route.size() > 1,
		"order %d route %d" % [mine.order, mine.route.size()])
	t.check("ending near (160, 60)", mine.order_point.distance_to(Vector2(160, 60)) < 13.0, str(mine.order_point))
	t.check("the dragged block is the selection", view.selection.size() == 1 and view.selection[0] == mine)

	# Nothing selected: a ground drag box-selects.
	view.selection.clear()
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(20, 20)), true)
	_motion(view, cam.w2s(Vector2(100, 160)))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(100, 160)), false)
	t.check("with nothing selected a ground drag box-selects", view.selection.has(mine) and view.selection.has(mate),
		str(view.selection.size()))

	# With a selection: a ground drag draws their formation line.
	sim.order_hold(mine)
	sim.order_hold(mate)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(140, 40)), true)
	_motion(view, cam.w2s(Vector2(140, 90)))
	_motion(view, cam.w2s(Vector2(140, 140)))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(140, 140)), false)
	t.check("a ground drag with a selection forms them on the line",
		mine.order == Block.OrderType.MOVE and mate.order == Block.OrderType.MOVE
		and not is_nan(mine.end_facing) and not is_nan(mate.end_facing))

	# A short scribble from a block is a tap: it selects, it gives no route.
	sim.order_hold(mine)
	view.selection = [mate] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	_motion(view, cam.w2s(mine.pos) + Vector2(12, 0))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos) + Vector2(12, 0), false)
	t.check("a stroke shorter than 20 px gives no route", mine.order == Block.OrderType.HOLD)
	t.check("but taps: the block is selected", view.selection.size() == 1 and view.selection[0] == mine)

	# A shaky click on an enemy with a selection still attacks it.
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(foe.pos), true)
	_motion(view, cam.w2s(foe.pos) + Vector2(15, 0))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(foe.pos) + Vector2(15, 0), false)
	t.check("a shaky click on an enemy attacks it", mine.order == Block.OrderType.ATTACK and mine.target_id == foe.id,
		"order %d" % mine.order)

	# A right press mid-stroke ends the stroke: nothing stale survives.
	sim.order_hold(mine)
	sim.order_hold(mate)
	view.selection = [mine] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	_motion(view, cam.w2s(Vector2(90, 60)))
	_motion(view, cam.w2s(Vector2(120, 50)))
	_click(view, MOUSE_BUTTON_RIGHT, cam.w2s(Vector2(120, 50)), true)
	_click(view, MOUSE_BUTTON_RIGHT, cam.w2s(Vector2(120, 50)), false)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(120, 50)), false)
	t.check("a right press mid-stroke cancels it", view._stroke_kind == "" and is_equal_approx(view._time_scale(), 1.0),
		"kind '%s' scale %s" % [view._stroke_kind, view._time_scale()])
	sim.order_hold(mine)
	view.selection.clear()
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(20, 20)), true)
	_motion(view, cam.w2s(Vector2(100, 160)))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(100, 160)), false)
	t.check("and the next ground drag box-selects, ordering nobody",
		view.selection.has(mine) and view.selection.has(mate) and mine.order == Block.OrderType.HOLD,
		"selected %d, order %d" % [view.selection.size(), mine.order])

	# A route drawn onto an enemy attacks it at the end.
	view.selection = [mine] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	for p in [Vector2(90, 110), Vector2(150, 140), Vector2(190, 155), foe.pos]:
		_motion(view, cam.w2s(p))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(foe.pos), false)
	t.check("a route ending on an enemy targets it", mine.order == Block.OrderType.MOVE and mine.route_target_id == foe.id,
		"order %d target %d" % [mine.order, mine.route_target_id])
	sim.order_hold(foe)
	var attacked := false
	for i in 60 * 30:
		sim.step(1.0 / 60.0)
		if mine.order == Block.OrderType.ATTACK:
			attacked = mine.target_id == foe.id
			break
	t.check("and ends in an attack on it", attacked, "order %d at %s" % [mine.order, mine.pos])

	# Touch: tapping a selected block again deselects it.
	sim.order_hold(mine)
	view.touch = true
	view.selection = [mine] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), true)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mine.pos), false)
	t.check("on touch, tapping the selected block deselects it", view.selection.is_empty())

	# Touch: tapping ground with a selection still moves there.
	view.selection = [mate] as Array[Block]
	var spot := mate.pos + Vector2(40, -10)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(spot), true)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(spot), false)
	t.check("on touch, tapping ground with a selection moves there",
		mate.order == Block.OrderType.MOVE and mate.order_point.distance_to(spot) < 13.0,
		"order %d at %s" % [mate.order, mate.order_point])

	# Touch: a second finger mid-stroke turns it into a pinch.
	sim.order_hold(mate)
	view.selection = [mate] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mate.pos), true)
	_motion(view, cam.w2s(mate.pos + Vector2(30, 0)))
	_motion(view, cam.w2s(mate.pos + Vector2(60, 0)))
	for i in 2:
		var touch_ev := InputEventScreenTouch.new()
		touch_ev.index = i
		touch_ev.pressed = true
		touch_ev.position = cam.w2s(mate.pos) + Vector2(60 * i, 0)
		view._gui_input(touch_ev)
	t.check("a second finger cancels the stroke", view._stroke_kind == "" and is_equal_approx(view._time_scale(), 1.0))
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mate.pos + Vector2(60, 0)), false)
	for i in 2:
		var up := InputEventScreenTouch.new()
		up.index = i
		up.pressed = false
		view._gui_input(up)
	t.check("and gives no order", mate.order == Block.OrderType.HOLD)

	# Hidden mid-stroke: the stroke is dropped.
	view.touch = false
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mate.pos), true)
	_motion(view, cam.w2s(mate.pos + Vector2(40, 0)))
	view.visible = false
	t.check("hiding the view mid-stroke drops it", view._stroke_kind == "" and is_equal_approx(view._time_scale(), 1.0))
	view.visible = true
	tree.root.remove_child(host)
	host.free()


## A drawing sim: flat arena, started, both sides player-driven.
func _drawing_sim(terrain: Terrain) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(terrain, Rect2(10, 10, 220, 160))
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(220, 160), PI)
	return sim

## A mouse drag pressed off the lead's centre (inside its body, or on the hit
## pad just past its side) gives the same shape as one pressed dead centre.
func _test_off_centre_drag(tree: SceneTree) -> void:
	print("\nBattleView: an off-centre drag keeps the group's shape")
	var terrain := Terrain.new()
	for case in ["centre", "in the body", "on the pad"]:
		var host := Control.new()
		host.size = Vector2(1280, 720)
		tree.root.add_child(host)
		var sim := _drawing_sim(terrain)
		var lead := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(60, 90), 0.0)
		var mate := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(60, 125), 0.0)
		var view := BattleView.new()
		host.add_child(view)
		view.open(terrain, sim, false)
		view._process(0.0)
		var cam := view.camera
		view.selection = [lead, mate] as Array[Block]
		var press := cam.w2s(lead.pos)
		match case:
			"in the body": press = cam.w2s(lead.pos + Vector2(-4, 6))
			"on the pad": press = cam.w2s(lead.pos + Vector2(-4, -12)) + Vector2(0, -5)
		t.check("%s: the press picks the lead" % case, view._block_at(cam.s2w(press), GameConfig.Side.PLAYER) == lead)
		var dy := cam.s2w(press).y - lead.pos.y
		_click(view, MOUSE_BUTTON_LEFT, press, true)
		for x in [80.0, 110.0, 150.0]:
			_motion(view, cam.w2s(Vector2(x, 90.0 + dy)))
		_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(150, 90.0 + dy)), false)
		var ok := lead.route.size() > 0 and mate.route.size() > 0
		var gap := INF
		if ok:
			gap = mate.route[mate.route.size() - 1].distance_to(lead.route[lead.route.size() - 1] + Vector2(0, 35))
		t.check("%s: the follower's route ends on its offset" % case, ok and gap <= 3.0, "off by %.1f" % gap)
		tree.root.remove_child(host)
		host.free()


## Final review of drawn orders: the stroke preview follows a moving lead and a
## changed selection; on touch a tap on any selected block clears a
## multi-selection; losing window focus mid-stroke drops the stroke.
func _test_drawing_edges(tree: SceneTree) -> void:
	print("\nBattleView: preview refresh, touch deselect, focus loss")
	var terrain := Terrain.new()
	var host := Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)
	var sim := _drawing_sim(terrain)
	var lead := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(60, 90), 0.0)
	var mate := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(60, 125), 0.0)
	var view := BattleView.new()
	host.add_child(view)
	view.open(terrain, sim, false)
	view._process(0.0)
	var cam := view.camera

	# The route preview is recomputed when the lead walks on, with the stroke unchanged.
	view.selection = [lead] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(lead.pos), true)
	for x in [80.0, 110.0, 150.0]:
		_motion(view, cam.w2s(Vector2(x, 90)))
	var first: PackedVector2Array = view._stroke_preview()
	lead.pos = Vector2(100, 90)
	var moved: PackedVector2Array = view._stroke_preview()
	t.check("the route preview follows a moving lead", moved.size() > 0 and first.size() > 0
		and moved[0].distance_to(first[0]) > 1.0, "%s -> %s" % [first, moved])
	view._cancel_pointer()
	lead.pos = Vector2(60, 90)

	# The formation preview is recomputed when the selection changes at the same size.
	var other := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.ARCHERS, Vector2(30, 60), 0.0)
	view.selection = [lead, mate] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(150, 40)), true)
	_motion(view, cam.w2s(Vector2(150, 90)))
	_motion(view, cam.w2s(Vector2(150, 140)))
	var slots: Array = view._stroke_preview()
	view.selection = [lead, other] as Array[Block]
	var slots2: Array = view._stroke_preview()
	var has_other := false
	for s in slots2:
		if s["block"] == other:
			has_other = true
	t.check("the formation preview follows a changed selection", slots.size() == 2 and has_other)
	view._cancel_pointer()

	# Touch: a tap on any block of a multi-selection clears it.
	view.touch = true
	view.selection = [lead, mate] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mate.pos), true)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mate.pos), false)
	t.check("on touch, tapping a block of a multi-selection clears it", view.selection.is_empty(),
		str(view.selection.size()))
	# Mouse: unchanged, the tap selects that block alone.
	view.touch = false
	view.selection = [lead, mate] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mate.pos), true)
	_click(view, MOUSE_BUTTON_LEFT, cam.w2s(mate.pos), false)
	t.check("with a mouse, clicking one of a multi-selection selects it alone",
		view.selection.size() == 1 and view.selection[0] == mate)

	# Focus lost mid-stroke (released outside the window): the stroke is dropped.
	for what in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Window.NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_click(view, MOUSE_BUTTON_LEFT, cam.w2s(lead.pos), true)
		_motion(view, cam.w2s(Vector2(100, 60)))
		t.check("fixture: drawing slows time", not is_equal_approx(view._time_scale(), 1.0))
		view.notification(what)
		t.check("focus loss %d drops the stroke and the slow-mo" % what,
			view._stroke_kind == "" and is_equal_approx(view._time_scale(), 1.0))
	tree.root.remove_child(host)
	host.free()


## Last gate: a touch press on the hit pad behind a block (outside its body,
## inside the finger pad, further than a route sample from its centre at this
## zoom) must not turn it round: the route's first leg points along the stroke.
func _test_touch_pad_press(tree: SceneTree) -> void:
	print("\nBattleView: a touch press on the pad behind a block does not turn it round")
	var terrain := Terrain.new()
	for offset in [Vector2(-1, 0), Vector2(-0.6, -0.8), Vector2(-0.6, 0.8)]:
		var host := Control.new()
		host.size = Vector2(1280, 720)
		tree.root.add_child(host)
		var sim := _drawing_sim(terrain)
		var lead := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(60, 90), 0.0)
		var view := BattleView.new()
		host.add_child(view)
		view.open(terrain, sim, true)
		view._process(0.0)
		var cam := view.camera
		cam.zoom = 1.5                                  # the pad is 16 u here
		view.selection = [lead] as Array[Block]
		# Just inside the pad, beyond the body, in the direction `offset`.
		var edge := lead.pos
		while lead.distance_to_point(edge) <= 0.0:
			edge += offset.normalized() * 0.25
		var press_w: Vector2 = edge + offset.normalized() * view._hit_pad() * 0.9
		t.check("fixture %s: the press is on the pad, off the body, over 12 u out" % offset,
			view._block_at(press_w, GameConfig.Side.PLAYER) == lead and lead.distance_to_point(press_w) > 0.0
			and press_w.distance_to(lead.pos) > 12.0, "%s at %.1f u" % [press_w, press_w.distance_to(lead.pos)])
		_click(view, MOUSE_BUTTON_LEFT, cam.w2s(press_w), true)
		for x in [100.0, 130.0, 160.0]:
			_motion(view, cam.w2s(Vector2(x, press_w.y)))
		var preview: PackedVector2Array = view._stroke_preview()
		var preview_ok := preview.size() > 0 and absf((preview[0] - lead.pos).angle()) <= deg_to_rad(30.0)
		_click(view, MOUSE_BUTTON_LEFT, cam.w2s(Vector2(160, press_w.y)), false)
		var ok := lead.route.size() > 0
		var off := INF
		if ok:
			off = absf((lead.route[0] - lead.pos).angle())
		t.check("%s: the preview's first leg points along the stroke" % offset, preview_ok, str(preview))
		t.check("%s: the route's first leg is within 30 degrees of the stroke" % offset, ok and off <= deg_to_rad(30.0),
			"%.0f deg, route %s" % [rad_to_deg(off), lead.route])
		tree.root.remove_child(host)
		host.free()

## A finished battle's result is applied the moment the sim finishes, not only
## when the player clicks through — so a loss can no longer be discarded by
## clicking End Turn instead of the result button.
func _test_result_applied_when_sim_finishes(tree: SceneTree) -> void:
	print("\nBattleLayer applies a finished battle's result as soon as it finishes")
	var packed := load("res://scenes/campaign.tscn") as PackedScene
	if packed == null:
		t.check("campaign.tscn loads", false)
		return
	var root = packed.instantiate()
	tree.root.add_child(root)
	var view: MapView = root.view
	var layer: BattleLayer = null
	for l in view.layers:
		if l is BattleLayer:
			layer = l
	var w: World = view.world
	var hill := -1
	var watch := -1
	for s in w.graph.sites:
		if s.name == "East Hill":
			hill = s.id
		elif s.name == "Hilltop Watch":
			watch = s.id
	for s in w.stacks.duplicate():
		w.remove_stack(s)
	var mine := w.add_stack(0, watch, [0, 0, 0, 0])
	var theirs := w.add_stack(1, hill, [0, 0, 0])
	Orders.move(w, mine, hill)
	root._on_end_turn()
	layer.open_next()
	var sim: BattleSim = layer.current.sim
	for b in sim.side_blocks(GameConfig.Side.ENEMY):
		b.health = 0.0
		b.status = Block.Status.DESTROYED
	sim._finish("test")
	layer.current._process(0.0)
	layer._watch()
	t.check("the losses were applied without a click", not w.stacks.has(theirs))
	t.check("the view is still up showing the result", layer.current != null and layer.current.result_shown())
	# End Turn (and Reset, the scenario picker) stay clickable over the result
	# panel; once the result is applied, End Turn must not discard the view.
	root._on_end_turn()
	layer._watch()
	t.check("the view is still up after End Turn", layer.current != null)
	t.check("nothing was re-offered: the win was not undone", w.pending_battles.is_empty())
	layer.current.result_actions[0]["action"].call()
	t.check("the button then only closes it", layer.current == null)
	t.check("no double application: the winner holds exactly what it should",
		mine.site_id == hill and mine.size() == 4)
	tree.root.remove_child(root)
	root.free()

func _test_has_waiting_ignores_invalid_battle(tree: SceneTree) -> void:
	print("\nBattleLayer.has_waiting() ignores a battle SupplyPhase invalidated")
	var packed := load("res://scenes/campaign.tscn") as PackedScene
	if packed == null:
		t.check("campaign.tscn loads", false)
		return
	var root = packed.instantiate()
	tree.root.add_child(root)
	var view: MapView = root.view
	var layer: BattleLayer = null
	for l in view.layers:
		if l is BattleLayer:
			layer = l
	var w: World = view.world
	var hill := -1
	var watch := -1
	for s in w.graph.sites:
		if s.name == "East Hill":
			hill = s.id
		elif s.name == "Hilltop Watch":
			watch = s.id
	for s in w.stacks.duplicate():
		w.remove_stack(s)
	var mine := w.add_stack(0, watch, [0, 0, 0, 0])
	var theirs := w.add_stack(1, hill, [0, 0, 0])
	Orders.move(w, mine, hill)
	root._on_end_turn()
	t.check("fixture: a battle waits", w.pending_battles.size() == 1)
	t.check("fixture: Fight battle is enabled", layer.has_waiting())
	w.remove_stack(theirs)
	t.check("has_waiting() is false once the enemy stack is gone", not layer.has_waiting())
	tree.root.remove_child(root)
	root.free()

func _test_combat_scene_peek(tree: SceneTree) -> void:
	print("\nthe prototype's Map peek hides the battle and stops its clock")
	var root := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Control
	tree.root.add_child(root)
	var campaign: Campaign = root.campaign
	root._begin_battle(campaign.armies[0], campaign.armies[1])
	var view: BattleView = root.battle_view
	view.sim.started = true
	view._process(0.5)
	var before: float = view.sim.time
	root._on_peek()
	view._process(0.5)
	t.check("Map hides the view and the clock stops",
		not view.visible and is_equal_approx(view.sim.time, before))
	root._on_peek()
	view._process(0.5)
	t.check("Battle shows it again and the clock runs", view.visible and view.sim.time > before)
	view.result_actions[0]["action"].call()
	t.check("Replay scenario closes the battle on a fresh map",
		root.battle_view == null and root.mode == root.Mode.STRATEGIC and root.campaign != campaign)
	tree.root.remove_child(root)
	root.free()

func _test_combat_scene_builds(tree: SceneTree) -> void:
	print("\nthe combat prototype still builds on BattleView")
	var packed := load("res://scenes/game.tscn") as PackedScene
	t.check("game.tscn loads", packed != null)
	if packed == null:
		return
	var root := packed.instantiate() as Control
	tree.root.add_child(root)
	var campaign: Campaign = root.campaign
	t.check("it opens on the strategic map", campaign != null and root.battle_view == null)
	root._begin_battle(campaign.armies[0], campaign.armies[1])
	t.check("a battle opens a BattleView", root.battle_view != null and root.battle_view.sim != null)
	t.check("with Replay and Back to map on its result panel",
		root.battle_view.result_actions.size() == 2)
	root._end_battle()
	t.check("Back to map closes it", root.battle_view == null and root.sim == null)
	tree.root.remove_child(root)
	root.free()

func _test_campaign_battle_flow(tree: SceneTree) -> void:
	print("\nthe campaign puts a waiting battle on screen and writes it back")
	var packed := load("res://scenes/campaign.tscn") as PackedScene
	if packed == null:
		t.check("campaign.tscn loads", false)
		return
	var root = packed.instantiate()
	tree.root.add_child(root)
	var view: MapView = root.view
	var layer: BattleLayer = null
	for l in view.layers:
		if l is BattleLayer:
			layer = l
	t.check("the battle layer is registered", layer != null)
	if layer == null:
		tree.root.remove_child(root)
		root.free()
		return
	var w: World = view.world
	var hill := -1
	var watch := -1
	for s in w.graph.sites:
		if s.name == "East Hill":
			hill = s.id
		elif s.name == "Hilltop Watch":
			watch = s.id
	for s in w.stacks.duplicate():
		w.remove_stack(s)
	var mine := w.add_stack(0, watch, [0, 0, 0, 0])
	var theirs := w.add_stack(1, hill, [0, 0, 0])
	Orders.move(w, mine, hill)
	root._on_end_turn()
	t.check("End Turn leaves the fight waiting", w.pending_battles.size() == 1)
	t.check("Fight battle is enabled", layer.has_waiting())
	t.check("the marker explains the fight",
		"strength ratio" in layer.tooltip(view.s2w(layer._marker(w.pending_battles[0]))))
	layer.open_next()
	t.check("the battle view is up", layer.current != null and layer.current.get_parent() == root)
	t.check("the map is hidden under it", not view.visible)
	var sim: BattleSim = layer.current.sim
	for b in sim.side_blocks(GameConfig.Side.ENEMY):
		b.health = 0.0
		b.status = Block.Status.DESTROYED
	sim._finish("test")
	layer.current._process(0.0)
	t.check("the result panel shows", layer.current.result_shown())
	layer.current.result_actions[0]["action"].call()
	t.check("closing it puts the map back", layer.current == null and view.visible)
	t.check("the battle is no longer waiting", w.pending_battles.is_empty())
	t.check("its losses were applied", not w.stacks.has(theirs))
	# End Turn in the middle of a battle: the view closes and nothing is applied.
	var again := w.add_stack(1, hill, [0, 0, 0])
	w.pending_battles = []
	root._on_end_turn()
	t.check("the standoff is offered again", w.pending_battles.size() == 1)
	layer.open_next()
	root._on_end_turn()
	# In the running game the tree's process_frame calls this; headless, the test does.
	layer._watch()
	t.check("End Turn mid-battle closes the view", layer.current == null)
	t.check("without applying a result", w.stacks.has(again) and again.size() == 3)
	tree.root.remove_child(root)
	root.free()

## Click an enemy: archers shoot it, everyone else attacks it. Double-click:
## the whole selection charges in, archers included.
func _test_click_to_shoot(tree: SceneTree) -> void:
	print("\nBattleView: click to shoot, double-click to charge")
	var host := Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)
	var terrain := Terrain.new()
	var sim := BattleSim.new()
	sim.setup(terrain, Rect2(10, 10, 220, 160))
	for side in [GameConfig.Side.PLAYER, GameConfig.Side.ENEMY]:
		sim.supply[side] = 1.0
		sim.behavior[side] = ""
	sim.home_dir[GameConfig.Side.PLAYER] = Vector2.LEFT
	sim.home_dir[GameConfig.Side.ENEMY] = Vector2.RIGHT
	sim.started = true
	var archers := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.ARCHERS, Vector2(50, 90), 0.0)
	var foot := sim.add_block(GameConfig.Side.PLAYER, GameConfig.Role.INFANTRY, Vector2(50, 130), 0.0)
	var foe := sim.add_block(GameConfig.Side.ENEMY, GameConfig.Role.INFANTRY, Vector2(180, 110), PI)
	var view := BattleView.new()
	host.add_child(view)
	view.open(terrain, sim, false)
	view._process(0.0)
	var cam := view.camera
	var at := cam.w2s(foe.pos)

	view.selection = [archers, foot] as Array[Block]
	_click(view, MOUSE_BUTTON_LEFT, at, true)
	_click(view, MOUSE_BUTTON_LEFT, at, false)
	t.check("a click on an enemy: the archers shoot it",
		archers.order == Block.OrderType.SHOOT and archers.target_id == foe.id, str(archers.order))
	t.check("and the infantry attack it", foot.order == Block.OrderType.ATTACK and foot.target_id == foe.id)
	t.check("the archers are tagged", view._block_tag(archers) in ["SHOOTING", "CLOSING IN"], view._block_tag(archers))

	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.position = at
	dbl.pressed = true
	dbl.double_click = true
	view._gui_input(dbl)
	_click(view, MOUSE_BUTTON_LEFT, at, false)
	t.check("a double-click charges: the archers attack it hand to hand",
		archers.order == Block.OrderType.ATTACK and archers.target_id == foe.id, str(archers.order))
	t.check("and so do the infantry", foot.order == Block.OrderType.ATTACK)

	_click(view, MOUSE_BUTTON_RIGHT, at, true)
	_click(view, MOUSE_BUTTON_RIGHT, at, false)
	t.check("a right-click on an enemy is the same as a click (archers shoot)",
		archers.order == Block.OrderType.SHOOT)
	tree.root.remove_child(host)
	host.free()
