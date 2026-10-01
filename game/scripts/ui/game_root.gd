extends Control

## Combat prototype shell: one terrain dataset, two zooms, mouse or finger.
##
## Strategic zoom is turn-based and is where position is chosen; battle zoom is
## real time and is where that choice pays off. The battle screen is a
## `BattleView` hosted under this shell's top HUD. All simulation lives in
## scripts/sim — this file is presentation and input only.
##
## Input model, the same on both zooms:
##   one finger / left button   tap to select or order, drag to draw or box-select
##   two fingers                pinch to zoom, drag to pan
##   wheel, right/middle drag   zoom and pan with a mouse
##   right click                explicit order (mouse only; a finger taps instead)

const DRAG_THRESHOLD_PX := 10.0
const STROKE_SAMPLE_WORLD := 22.0     # how far a finger travels between path samples
const HUD_MARGIN := 8.0

enum Mode { STRATEGIC, BATTLE }

var terrain: Terrain
var campaign: Campaign
var sim: BattleSim
var battle_view: BattleView = null
var scenario_index := 0

var mode := Mode.STRATEGIC
var peek_map := false             # zoomed out to the strategic view mid-battle

var camera := MapCamera.new()
var touch := false                # tap-to-order instead of right-click

var hover_world := Vector2.ZERO
var preview_path: PackedVector2Array = []

# One-finger / left-button gesture in progress.
var _press_screen := Vector2.INF
var _press_moved := false
var _press_army: Army = null
var _stroking := false            # drawing a path on the strategic map
var _stroke_tail := Vector2.ZERO

# Two-finger gesture, and mouse-button panning.
var _touches := {}                # index -> screen position
var _gesture := false
var _gesture_dist := 0.0
var _gesture_mid := Vector2.ZERO
var _pan_button := -1
var _pan_moved := false

var _terrain_texture: ImageTexture
var _font: Font
var _hud := {}

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	touch = BattleView.detect_touch()
	theme = _build_theme()
	terrain = Terrain.new()
	_terrain_texture = BattleView.terrain_texture(terrain)
	_build_hud()
	_apply_display_scale()
	get_viewport().size_changed.connect(_apply_display_scale)
	_load_scenario(0)

# -------------------------------------------------------------------- display

## Render one logical pixel per CSS pixel. The canvas is sized in physical
## pixels, so on a phone with a 3x display everything would otherwise come out
## a third of the size a finger needs.
func _apply_display_scale() -> void:
	var scale := 1.0
	if OS.has_feature("web"):
		var css_width := float(JavaScriptBridge.eval("window.innerWidth", true))
		if css_width > 0.0:
			scale = float(get_window().size.x) / css_width
	else:
		scale = DisplayServer.screen_get_scale()
	scale = clampf(snappedf(scale, 0.25), 1.0, 4.0)
	if not is_equal_approx(get_window().content_scale_factor, scale):
		get_window().content_scale_factor = scale

## The part of the screen the map is fitted into: everything the HUD leaves.
func _map_area() -> Rect2:
	var top: float = _hud["top"].size.y + HUD_MARGIN * 2.0
	var bottom: float = size.y - _hud["bottom"].size.y - HUD_MARGIN * 2.0
	if not _hud["bottom"].visible:
		bottom = size.y
	return Rect2(0.0, top, size.x, maxf(bottom - top, 1.0))

func _w2s(p: Vector2) -> Vector2:
	return camera.w2s(p)

func _s2w(p: Vector2) -> Vector2:
	return camera.s2w(p)

func _fit_camera() -> void:
	camera.screen = _map_area()
	camera.fit(Rect2(Vector2.ZERO, Terrain.SIZE))

# ------------------------------------------------------------------ scenarios

func _load_scenario(index: int) -> void:
	_end_battle()
	scenario_index = index
	campaign = Scenarios.build(index, terrain)
	preview_path = PackedVector2Array()
	_cancel_pointer()
	_refresh_hud()
	_fit_camera()

func _begin_battle(player: Army, enemy: Army) -> void:
	# On a portrait screen a landscape crop is a strip across the middle, so
	# turn the field to match: same area, blocks twice the size.
	var crop: Vector2 = GameConfig.strategic["battle_crop"]
	var area := _map_area()
	if area.size.y > area.size.x:
		crop = Vector2(crop.y, crop.x)
	sim = Scenarios.start_battle(terrain, player, enemy, crop)
	mode = Mode.BATTLE
	peek_map = false
	_cancel_pointer()
	battle_view = BattleView.new()
	battle_view.insets = func() -> Vector2:
		return Vector2(_hud["top"].size.y + HUD_MARGIN, 0.0)
	battle_view.result_actions = [
		{"label": "Replay scenario", "action": func(): _load_scenario(scenario_index)},
		{"label": "Back to map", "action": _end_battle},
	]
	add_child(battle_view)
	# Under the top HUD, which keeps the scenario picker, Map and Tuning.
	move_child(battle_view, 0)
	battle_view.open(terrain, sim, touch)
	_refresh_hud()

func _end_battle() -> void:
	if battle_view != null:
		remove_child(battle_view)
		battle_view.queue_free()
		battle_view = null
	sim = null
	mode = Mode.STRATEGIC
	peek_map = false
	_refresh_hud()
	_fit_camera()

# ----------------------------------------------------------------------- loop

func _process(_delta: float) -> void:
	camera.rescreen(_map_area())
	_refresh_status()
	queue_redraw()

# ------------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.BACKGROUND, true)
	if mode == Mode.BATTLE and not peek_map:
		return                          # the BattleView draws the battle
	draw_texture_rect(_terrain_texture,
		Rect2(_w2s(Vector2.ZERO), Terrain.SIZE * camera.zoom), false)
	_draw_roads()
	_draw_strategic()

func _draw_roads() -> void:
	for road in Terrain.ROADS:
		var pts := PackedVector2Array()
		for p in road:
			pts.append(_w2s(p))
		draw_polyline(pts, ThemeColors.ROAD, maxf(1.5, 4.0 * camera.zoom))

func _draw_strategic() -> void:
	# Feature labels, so the map reads without hovering every cell.
	for f in terrain.features:
		if f["cells"] < 12:
			continue
		var at := _w2s(f["centroid"])
		draw_string(_font, at, String(f["type"]).capitalize(),
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, ThemeColors.TEXT_DIM * Color(1, 1, 1, 0.75))

	if sim != null and peek_map:
		var r := Rect2(_w2s(sim.field.position), sim.field.size * camera.zoom)
		draw_rect(r, ThemeColors.ACCENT, false, 2.0)

	# Path preview: the hover route with a mouse, the drawn route with a finger.
	if campaign.selected != null and preview_path.size() > 0:
		var pts := PackedVector2Array([_w2s(campaign.selected.pos)])
		for p in preview_path:
			pts.append(_w2s(p))
		draw_polyline(pts, ThemeColors.ACCENT * Color(1, 1, 1, 0.8), 3.0)
		draw_circle(pts[pts.size() - 1], 5.0, ThemeColors.ACCENT)

	for a in campaign.armies:
		var at := _w2s(a.pos)
		var col := ThemeColors.side(a.side)
		if a.path.size() > 0:
			var pts := PackedVector2Array([at])
			for p in a.path:
				pts.append(_w2s(p))
			draw_polyline(pts, col * Color(1, 1, 1, 0.6), 2.0)

		var r := _marker_radius()
		draw_circle(at, r, col.darkened(0.45))
		draw_arc(at, r, 0.0, TAU, 24, col, 2.0)
		# Supply as a filled arc around the marker.
		draw_arc(at, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * a.supply, 24, ThemeColors.ACCENT, 3.0)
		if campaign.selected == a:
			draw_arc(at, r + 8.0, 0.0, TAU, 28, ThemeColors.TEXT, 1.5)
		var label_y: float = r + 24.0 if a.side == GameConfig.Side.PLAYER else -(r + 12.0)
		draw_string(_font, at + Vector2(-34, label_y), "%s  %d%%" % [a.label, int(a.supply * 100.0)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

## Army markers are drawn at a fixed screen size so they stay tappable however
## far out the map is zoomed.
func _marker_radius() -> float:
	return 14.0 if touch else 11.0

# --------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	# Raw touches drive two-finger gestures. The first finger is also delivered
	# as an emulated mouse, which is what the single-pointer code below sees.
	if event is InputEventScreenTouch:
		_screen_touch(event)
		return
	if event is InputEventScreenDrag:
		_screen_drag(event)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _touches.size() > 1 or _gesture:
				return                  # a second finger has taken over
			if event.pressed:
				_pointer_down(event.position)
			else:
				_pointer_up(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_button_event(event)
		return

	if event is InputEventMouseMotion:
		if _pan_button != -1:
			# A mouse button drag pans; a click that never moved does nothing here.
			if not _pan_moved and event.position.distance_to(_press_screen) < DRAG_THRESHOLD_PX:
				return
			_pan_moved = true
			camera.pan(event.relative)
			return
		if _gesture or _touches.size() > 1:
			return
		_pointer_move(event.position)

# --- two fingers ---------------------------------------------------------

func _screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			# Whatever one finger was doing is off: this is a pinch or a pan.
			_cancel_pointer()
			_gesture = true
			var pts: Array = _touches.values()
			_gesture_dist = maxf(1.0, pts[0].distance_to(pts[1]))
			_gesture_mid = (pts[0] + pts[1]) * 0.5
	else:
		_touches.erase(event.index)
		if _touches.is_empty():
			_gesture = false

func _screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if not _gesture or _touches.size() < 2:
		return
	var pts: Array = _touches.values()
	var dist: float = maxf(1.0, pts[0].distance_to(pts[1]))
	var mid: Vector2 = (pts[0] + pts[1]) * 0.5
	camera.zoom_at(mid, dist / _gesture_dist)
	camera.pan(mid - _gesture_mid)
	_gesture_dist = dist
	_gesture_mid = mid

# --- mouse panning --------------------------------------------------------

func _pan_button_event(event: InputEventMouseButton) -> void:
	if event.pressed:
		_pan_button = event.button_index
		_pan_moved = false
		_press_screen = event.position
		return
	_pan_button = -1
	_press_screen = Vector2.INF

# --- one pointer ------------------------------------------------------------

func _pointer_down(screen: Vector2) -> void:
	_press_screen = screen
	_press_moved = false
	hover_world = _s2w(screen)

	_press_army = campaign.army_at(hover_world, _hit_radius())
	if _press_army != null and _press_army.side == GameConfig.Side.PLAYER:
		campaign.selected = _press_army
		preview_path = PackedVector2Array()

func _pointer_move(screen: Vector2) -> void:
	hover_world = _s2w(screen)

	if _press_screen == Vector2.INF:
		# Plain hover, mouse only: preview the route to the cursor.
		if touch:
			return
		if campaign.selected != null:
			preview_path = campaign.find_path(campaign.selected.pos, hover_world)
		return

	if not _press_moved and screen.distance_to(_press_screen) < DRAG_THRESHOLD_PX:
		return
	_press_moved = true

	# Strategic drag with an army selected: draw the route under the finger.
	if campaign.selected == null:
		return
	if not _stroking:
		_stroking = true
		_stroke_tail = campaign.selected.pos
		preview_path = PackedVector2Array()
	if hover_world.distance_to(_stroke_tail) >= STROKE_SAMPLE_WORLD:
		preview_path = campaign.extend_path(campaign.selected.pos, preview_path, hover_world)
		_stroke_tail = hover_world

func _pointer_up(screen: Vector2) -> void:
	if _press_screen == Vector2.INF:
		return
	var world := _s2w(screen)
	var tapped := not _press_moved

	if tapped:
		if _press_army == null and campaign.selected != null:
			campaign.selected.path = campaign.find_path(campaign.selected.pos, world)
			preview_path = PackedVector2Array()
	elif _stroking and campaign.selected != null:
		# Finish the stroke on the exact release point and make it the order.
		preview_path = campaign.extend_path(campaign.selected.pos, preview_path, world)
		campaign.selected.path = preview_path
		preview_path = PackedVector2Array()

	_press_screen = Vector2.INF
	_press_moved = false
	_press_army = null
	_stroking = false
	_refresh_hud()

func _cancel_pointer() -> void:
	_press_screen = Vector2.INF
	_press_moved = false
	_press_army = null
	_stroking = false
	_pan_button = -1
	if mode == Mode.STRATEGIC:
		preview_path = PackedVector2Array()

## Hit radius in world units for the strategic map's army markers: a
## fingertip needs about 28 px, a cursor 14.
func _hit_radius() -> float:
	return (28.0 if touch else 14.0) / camera.zoom

# ----------------------------------------------------------------------- HUD

## Sized for fingers: 44 px minimum touch targets and text that reads on a
## phone held at arm's length. The same theme serves the desktop.
func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	for kind in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = ThemeColors.PANEL_EDGE.lightened(0.10 if state == "hover" else 0.0)
			if state == "pressed":
				sb.bg_color = ThemeColors.ACCENT.darkened(0.55)
			if state == "disabled":
				sb.bg_color = ThemeColors.PANEL_EDGE.darkened(0.3)
			sb.set_corner_radius_all(6)
			sb.set_content_margin_all(0)
			sb.content_margin_left = 14
			sb.content_margin_right = 14
			sb.content_margin_top = 10
			sb.content_margin_bottom = 10
			t.set_stylebox(state, kind, sb)
		t.set_font_size("font_size", kind, 16)
		t.set_color("font_color", kind, ThemeColors.TEXT)
		t.set_color("font_disabled_color", kind, ThemeColors.TEXT_DIM)
	return t

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeColors.PANEL * Color(1, 1, 1, 0.92)
	sb.border_color = ThemeColors.PANEL_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _button(text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 44)
	b.pressed.connect(pressed)
	return b

func _label(text := "", dim := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ThemeColors.TEXT_DIM if dim else ThemeColors.TEXT)
	l.add_theme_font_size_override("font_size", 14)
	return l

func _flow() -> HFlowContainer:
	# Buttons wrap onto a second row on a narrow screen instead of clipping.
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	return f

func _build_hud() -> void:
	# Top: scenario + status on one line, controls wrapping beneath ----------
	var top := _panel()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = HUD_MARGIN
	top.offset_right = -HUD_MARGIN
	top.offset_top = HUD_MARGIN
	add_child(top)
	_hud["top"] = top
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 8)
	top.add_child(top_box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	top_box.add_child(head)

	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.custom_minimum_size = Vector2(0, 44)
	for s in Scenarios.all():
		picker.add_item(s["name"])
	picker.item_selected.connect(_load_scenario)
	head.add_child(picker)
	_hud["scenario"] = picker

	_hud["status"] = _label()
	_hud["status"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud["status"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud["status"].vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_hud["status"])

	var controls := _flow()
	top_box.add_child(controls)
	_hud["end_turn"] = _button("End Turn", _on_end_turn)
	controls.add_child(_hud["end_turn"])
	_hud["peek"] = _button("Map", _on_peek)
	controls.add_child(_hud["peek"])
	_hud["fit"] = _button("Fit", func(): _fit_camera())
	controls.add_child(_hud["fit"])
	controls.add_child(_button("Tuning", _on_tuning))

	# Bottom: what is under the cursor, and the route being drawn ------------
	var bottom := _panel()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = HUD_MARGIN
	bottom.offset_right = -HUD_MARGIN
	bottom.offset_top = -HUD_MARGIN
	bottom.offset_bottom = -HUD_MARGIN
	# Content-sized and anchored to the bottom edge: it has to grow upward or
	# its whole height lands below the screen.
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom)
	_hud["bottom"] = bottom
	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 8)
	bottom.add_child(bottom_box)

	_hud["info"] = _label()
	_hud["info"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud["info"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Always two lines tall: the map is fitted into what the HUD leaves, so a
	# panel that grew with the selection would make the view jump on every tap.
	_hud["info"].custom_minimum_size.y = 40.0
	_hud["info"].max_lines_visible = 2
	bottom_box.add_child(_hud["info"])

	_build_tuning_panel()

func _build_tuning_panel() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_right = -HUD_MARGIN
	scroll.visible = false
	add_child(scroll)

	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	box.add_child(_label("TUNING — live", true))
	for role in GameConfig.units:
		var u: Dictionary = GameConfig.units[role]
		box.add_child(_label(u["name"]))
		for key in ["health", "morale", "speed", "melee_dps", "ranged_dps", "range", "charge_burst", "turn_rate", "reform_time"]:
			if not u.has(key):
				continue
			box.add_child(_tuning_row(key, u[key], func(v): u[key] = v))

	box.add_child(_label("Combat"))
	for key in GameConfig.combat:
		box.add_child(_tuning_row(key, GameConfig.combat[key],
			func(v): GameConfig.combat[key] = v))

	box.add_child(_label("Terrain"))
	for key in GameConfig.terrain_mods:
		box.add_child(_tuning_row(key, GameConfig.terrain_mods[key],
			func(v): GameConfig.terrain_mods[key] = v))

	_hud["tuning"] = scroll

func _tuning_row(key: String, value: float, apply: Callable) -> Control:
	var row := HBoxContainer.new()
	var name := _label(key.replace("_", " "), true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 1000.0
	spin.step = 0.05
	spin.value = value
	spin.custom_minimum_size = Vector2(110, 44)
	spin.value_changed.connect(apply)
	row.add_child(spin)
	return row

# --------------------------------------------------------------- HUD updates

func _refresh_hud() -> void:
	var in_battle := mode == Mode.BATTLE
	_hud["end_turn"].visible = not in_battle
	_hud["peek"].visible = in_battle
	_hud["fit"].visible = not in_battle or peek_map
	_hud["bottom"].visible = not in_battle or peek_map
	_hud["peek"].text = "Battle" if peek_map else "Map"
	if battle_view != null:
		battle_view.visible = not peek_map

func _layout_overlays() -> void:
	# Panels that float over the map keep to the screen on a phone.
	var tuning: ScrollContainer = _hud["tuning"]
	tuning.offset_left = -minf(320.0, size.x - HUD_MARGIN * 2.0)
	tuning.offset_top = _hud["top"].size.y + HUD_MARGIN * 2.0
	tuning.offset_bottom = -(_hud["bottom"].size.y + HUD_MARGIN * 2.0)

func _refresh_status() -> void:
	_layout_overlays()
	var status: Label = _hud["status"]
	var info: Label = _hud["info"]

	if mode == Mode.BATTLE:
		status.text = "Battle — %s" % Scenarios.all()[scenario_index]["name"]
		if peek_map:
			status.text += " · map (paused)"
		info.text = _terrain_tooltip()
		return

	var spec := Scenarios.all()[scenario_index]
	status.text = "Turn %d · %s" % [campaign.turn, spec["lesson"]]
	info.text = _terrain_tooltip()

func _terrain_tooltip() -> String:
	var d := terrain.describe(hover_world)
	var text := "%s — %s" % [d["name"], d["effect"]]
	# The route being previewed, or failing that the one already ordered.
	var route := preview_path
	if route.is_empty() and mode == Mode.STRATEGIC and campaign.selected != null:
		route = campaign.selected.path
	if mode == Mode.STRATEGIC and campaign.selected != null and route.size() > 0:
		var cost := campaign.path_cost(campaign.selected.pos, route)
		text += "\n%s%d turn(s) · supply cost ≈ %d%%" % [
			"" if preview_path.size() > 0 else "Ordered route: ",
			campaign.turns_for(campaign.selected.pos, route),
			int(cost / 20.0),
		]
	elif mode == Mode.STRATEGIC and campaign.selected != null:
		text += "\n" + ("Drag from your army to draw a route, or tap a destination."
			if touch else "Click a destination, or drag to draw a route.")
	return text

# -------------------------------------------------------------------- buttons

func _on_end_turn() -> void:
	var met := campaign.end_turn()
	preview_path = PackedVector2Array()
	if met.size() == 2:
		var player: Army = met[0] if met[0].side == GameConfig.Side.PLAYER else met[1]
		var enemy: Army = met[1] if met[0].side == GameConfig.Side.PLAYER else met[0]
		_begin_battle(player, enemy)

## Hiding the view is what pauses the battle.
func _on_peek() -> void:
	peek_map = not peek_map
	_cancel_pointer()
	_refresh_hud()
	_fit_camera()

func _on_tuning() -> void:
	_hud["tuning"].visible = not _hud["tuning"].visible
