extends Control

## Combat prototype shell: one terrain dataset, two zooms, mouse or finger.
##
## Strategic zoom is turn-based and is where position is chosen; battle zoom is
## real time and is where that choice pays off. All simulation lives in
## scripts/sim — this file is presentation and input only.
##
## Input model, the same on both zooms:
##   one finger / left button   tap to select or order, drag to draw or box-select
##   two fingers                pinch to zoom, drag to pan
##   wheel, right/middle drag   zoom and pan with a mouse
##   right click                explicit order (mouse only; a finger taps instead)

const DT := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 8
const DRAG_THRESHOLD_PX := 10.0
const STROKE_SAMPLE_WORLD := 22.0     # how far a finger travels between path samples
const HUD_MARGIN := 8.0
const WIDE_SCREEN := 760.0            # logical px above which the event log gets a corner

enum Mode { STRATEGIC, BATTLE, RESULT }

var terrain: Terrain
var campaign: Campaign
var sim: BattleSim
var scenario_index := 0

var mode := Mode.STRATEGIC
var peek_map := false             # zoomed out to the strategic view mid-battle
var paused := false
var speed := 1.0
var _accum := 0.0

var camera := MapCamera.new()
var touch := false                # tap-to-order instead of right-click

var selection: Array[Block] = []
var pending_order := ""           # "move" / "attack" armed by the order buttons
var hover_world := Vector2.ZERO
var preview_path: PackedVector2Array = []

# One-finger / left-button gesture in progress.
var _press_screen := Vector2.INF
var _press_moved := false
var _press_army: Army = null
var _press_block: Block = null
var _stroking := false            # drawing a path on the strategic map
var _stroke_tail := Vector2.ZERO
var _box_to := Vector2.INF        # battle box-select corner
var dragging_block: Block = null  # pre-battle arrangement

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
	touch = _detect_touch()
	theme = _build_theme()
	terrain = Terrain.new()
	_terrain_texture = _build_terrain_texture()
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

func _detect_touch() -> bool:
	if OS.has_feature("web"):
		# ?input=touch or ?input=mouse forces it, for testing either path anywhere.
		var forced := NetConfig._query_param("input")
		if forced == "touch":
			return true
		if forced == "mouse":
			return false
	return DisplayServer.is_touchscreen_available()

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
	if mode == Mode.STRATEGIC or peek_map or sim == null:
		camera.fit(Rect2(Vector2.ZERO, Terrain.SIZE))
	else:
		# A little room around the field so blocks on its edge are not on
		# the edge of the screen too.
		camera.fit(sim.field.grow(16.0))

# ------------------------------------------------------------------ scenarios

func _load_scenario(index: int) -> void:
	scenario_index = index
	campaign = Scenarios.build(index, terrain)
	sim = null
	mode = Mode.STRATEGIC
	peek_map = false
	selection.clear()
	preview_path = PackedVector2Array()
	_cancel_pointer()
	_hud["result"].visible = false
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
	paused = false
	selection.clear()
	_accum = 0.0
	_cancel_pointer()
	_refresh_hud()
	_fit_camera()

# ----------------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if mode == Mode.BATTLE and sim != null and sim.started and not sim.finished \
			and not paused and not peek_map:
		_accum += delta * speed
		var steps := 0
		while _accum >= DT and steps < MAX_STEPS_PER_FRAME:
			sim.step(DT)
			_accum -= DT
			steps += 1
		if sim.finished:
			_show_result()
	camera.rescreen(_map_area())
	_refresh_status()
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		paused = not paused
		_refresh_hud()

# ------------------------------------------------------------------- drawing

## The terrain is rasterised once into a texture; both zooms sample the same
## image, which is what keeps the two views honest about being one dataset.
func _build_terrain_texture() -> ImageTexture:
	var w := Terrain.COLS * 4
	var h := Terrain.ROWS * 4
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var world := Vector2(
				(float(x) + 0.5) / float(w) * Terrain.SIZE.x,
				(float(y) + 0.5) / float(h) * Terrain.SIZE.y,
			)
			var base := ThemeColors.biome(terrain.biome_at(world))
			# Height lifts the ground a little, and banding every other step
			# gives hills readable contours instead of a wash.
			var steps: float = terrain.height_at(world) / Terrain.HEIGHT_STEP
			var lift: float = clampf(steps / 9.0, 0.0, 1.0)
			var band: float = 0.025 if int(steps) % 2 == 1 else 0.0
			img.set_pixel(x, y, base.lightened(lift * 0.13 + band))
	return ImageTexture.create_from_image(img)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.BACKGROUND, true)
	draw_texture_rect(_terrain_texture,
		Rect2(_w2s(Vector2.ZERO), Terrain.SIZE * camera.zoom), false)
	_draw_roads()

	var battle_view := sim != null and not peek_map and mode != Mode.STRATEGIC
	if battle_view:
		_draw_field_edge()
		_draw_battle()
	else:
		_draw_strategic()

func _draw_roads() -> void:
	for road in Terrain.ROADS:
		var pts := PackedVector2Array()
		for p in road:
			pts.append(_w2s(p))
		draw_polyline(pts, ThemeColors.ROAD, maxf(1.5, 4.0 * camera.zoom))

## Everything outside the battle field is dimmed, so a player who has panned
## or zoomed can always see where the fight actually is.
func _draw_field_edge() -> void:
	var f := Rect2(_w2s(sim.field.position), sim.field.size * camera.zoom)
	var shade := Color(0, 0, 0, 0.45)
	draw_rect(Rect2(0, 0, size.x, f.position.y), shade, true)
	draw_rect(Rect2(0, f.end.y, size.x, size.y - f.end.y), shade, true)
	draw_rect(Rect2(0, f.position.y, f.position.x, f.size.y), shade, true)
	draw_rect(Rect2(f.end.x, f.position.y, size.x - f.end.x, f.size.y), shade, true)
	draw_rect(f, ThemeColors.TEXT_DIM * Color(1, 1, 1, 0.5), false, 1.0)

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

func _draw_battle() -> void:
	var z := camera.zoom

	if _box_to != Vector2.INF and _press_screen != Vector2.INF:
		var r := Rect2(_press_screen, _box_to - _press_screen).abs()
		draw_rect(r, ThemeColors.ACCENT * Color(1, 1, 1, 0.12), true)
		draw_rect(r, ThemeColors.ACCENT, false, 1.0)

	for b in sim.blocks:
		if not b.alive() or not sim.visible_to(b, GameConfig.Side.PLAYER):
			continue
		_draw_block(b, z)

	# Order lines for what is selected.
	for b in selection:
		if not b.alive():
			continue
		var target: Vector2 = Vector2.INF
		if b.order == Block.OrderType.MOVE:
			target = b.order_point
		elif b.order == Block.OrderType.ATTACK:
			var t := sim.block_by_id(b.target_id)
			if t != null:
				target = t.pos
		if target != Vector2.INF:
			draw_line(_w2s(b.pos), _w2s(target), ThemeColors.ACCENT * Color(1, 1, 1, 0.5), 1.0)

func _draw_block(b: Block, z: float) -> void:
	var s: Vector2 = b.size()
	var col := ThemeColors.side(b.side)
	var routing_flash: bool = b.routing and fmod(sim.time, 0.4) < 0.2

	draw_set_transform(_w2s(b.pos), b.facing, Vector2(z, z))

	var body := col.darkened(0.55)
	if b.routing:
		body = (ThemeColors.WARN if routing_flash else col).darkened(0.35)
	draw_rect(Rect2(-s * 0.5, s), body, true)

	# Health fills the block from the bottom up.
	var hf: float = clampf(b.health / b.max_health, 0.0, 1.0)
	draw_rect(
		Rect2(Vector2(-s.x * 0.5, s.y * 0.5 - s.y * hf), Vector2(s.x, s.y * hf)),
		col, true)

	# Morale is the outline: a shaky block has a thin edge.
	var mf: float = clampf(b.morale / b.max_morale, 0.0, 1.0)
	draw_rect(Rect2(-s * 0.5, s), col.lightened(0.35), false, 0.6 + 2.4 * mf)

	if b.braced:
		draw_line(Vector2(s.x * 0.5, -s.y * 0.5), Vector2(s.x * 0.5, s.y * 0.5),
			ThemeColors.ACCENT, 2.5)

	# Facing notch on the front edge.
	draw_colored_polygon(PackedVector2Array([
		Vector2(s.x * 0.5, -2.0), Vector2(s.x * 0.5 + 4.0, 0.0), Vector2(s.x * 0.5, 2.0),
	]), col.lightened(0.5))

	_draw_role_mark(b.stats()["mark"], col.lightened(0.6))

	if selection.has(b):
		draw_rect(Rect2(-s * 0.5 - Vector2(3, 3), s + Vector2(6, 6)),
			ThemeColors.TEXT, false, 1.0)
	if b.order == Block.OrderType.WITHDRAW:
		draw_rect(Rect2(-s * 0.5 - Vector2(2, 2), s + Vector2(4, 4)),
			ThemeColors.WARN, false, 1.0)

	draw_set_transform_matrix(Transform2D.IDENTITY)

## Role marks are drawn rather than typed: the fallback font has no glyphs for
## swords or horses, and a missing glyph renders as an empty box.
func _draw_role_mark(mark: String, col: Color) -> void:
	match mark:
		"infantry":
			draw_line(Vector2(-3, -3), Vector2(3, 3), col, 1.0)
			draw_line(Vector2(-3, 3), Vector2(3, -3), col, 1.0)
		"cavalry":
			draw_colored_polygon(PackedVector2Array([
				Vector2(-3, -3), Vector2(4, 0), Vector2(-3, 3),
			]), col)
		"archers":
			draw_arc(Vector2(-1, 0), 4.0, -PI / 2.2, PI / 2.2, 10, col, 1.0)
			draw_line(Vector2(-2, 0), Vector2(4, 0), col, 1.0)

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
			# A mouse button drag pans; a right click that never moved is an order.
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
	var was_click := _pan_button == MOUSE_BUTTON_RIGHT and not _pan_moved
	_pan_button = -1
	if was_click and _in_battle_control():
		_issue_at(_s2w(event.position))
	_press_screen = Vector2.INF

# --- one pointer ------------------------------------------------------------

func _in_battle_control() -> bool:
	return sim != null and mode != Mode.STRATEGIC and not peek_map

func _pointer_down(screen: Vector2) -> void:
	_press_screen = screen
	_press_moved = false
	hover_world = _s2w(screen)

	if not _in_battle_control():
		_press_army = campaign.army_at(hover_world, _hit_radius())
		_press_block = null
		if _press_army != null and _press_army.side == GameConfig.Side.PLAYER:
			campaign.selected = _press_army
			preview_path = PackedVector2Array()
		return

	_press_army = null
	_press_block = _block_at(hover_world, GameConfig.Side.PLAYER)
	# Before the clock starts the defender may drag blocks into place.
	if _press_block != null and not sim.started and sim.player_is_defender:
		dragging_block = _press_block
		selection = [_press_block] as Array[Block]

func _pointer_move(screen: Vector2) -> void:
	hover_world = _s2w(screen)

	if _press_screen == Vector2.INF:
		# Plain hover, mouse only: preview the route to the cursor.
		if not _in_battle_control() and campaign.selected != null and not touch:
			preview_path = campaign.find_path(campaign.selected.pos, hover_world)
		return

	if not _press_moved and screen.distance_to(_press_screen) < DRAG_THRESHOLD_PX:
		return
	_press_moved = true

	if dragging_block != null:
		dragging_block.pos = _clamp_to_field(hover_world, dragging_block)
		return

	if _in_battle_control():
		if _press_block == null:
			_box_to = screen
		return

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

	if dragging_block != null:
		dragging_block = null
	elif _in_battle_control():
		if _box_to != Vector2.INF:
			_box_select(Rect2(_press_screen, _box_to - _press_screen).abs())
		elif tapped:
			_battle_tap(world)
	elif tapped:
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
	_press_block = null
	_stroking = false
	_box_to = Vector2.INF
	_refresh_hud()

func _cancel_pointer() -> void:
	_press_screen = Vector2.INF
	_press_moved = false
	_press_army = null
	_press_block = null
	_stroking = false
	_box_to = Vector2.INF
	dragging_block = null
	_pan_button = -1
	if mode == Mode.STRATEGIC:
		preview_path = PackedVector2Array()

## A tap on the battlefield. With a finger there is no right button, so a tap
## with something selected is the order: an enemy means attack, ground means
## move. A mouse keeps the RTS convention and orders with the right button.
func _battle_tap(world: Vector2) -> void:
	if pending_order != "":
		_apply_pending(world)
		return
	var friend := _block_at(world, GameConfig.Side.PLAYER)
	if friend != null:
		selection = [friend] as Array[Block]
		return
	if touch and not selection.is_empty():
		_issue_at(world)
		return
	if not touch:
		selection.clear()

## Attack an enemy under the point, otherwise move there.
func _issue_at(world: Vector2) -> void:
	var foe := _block_at(world, GameConfig.Side.ENEMY)
	for b in selection:
		if not b.alive():
			continue
		if foe != null:
			sim.order_attack(b, foe)
		else:
			sim.order_move(b, world)
	pending_order = ""
	_refresh_hud()

func _apply_pending(world: Vector2) -> void:
	if pending_order == "attack":
		var foe := _block_at(world, GameConfig.Side.ENEMY)
		if foe != null:
			for b in selection:
				sim.order_attack(b, foe)
	else:
		for b in selection:
			sim.order_move(b, world)
	pending_order = ""
	_refresh_hud()

func _box_select(rect: Rect2) -> void:
	var picked: Array[Block] = []
	for b in sim.blocks:
		if b.alive() and b.side == GameConfig.Side.PLAYER and rect.has_point(_w2s(b.pos)):
			picked.append(b)
	selection = picked

## Hit radius in world units: a fingertip needs about 28 px, a cursor 14.
func _hit_radius() -> float:
	return (28.0 if touch else 14.0) / camera.zoom

func _block_at(world: Vector2, side: int) -> Block:
	if sim == null:
		return null
	var best: Block = null
	var best_d := INF
	var reach := _hit_radius()
	for b in sim.blocks:
		if not b.alive() or b.side != side:
			continue
		if side != GameConfig.Side.PLAYER and not sim.visible_to(b, GameConfig.Side.PLAYER):
			continue
		var d: float = b.pos.distance_to(world)
		if d < maxf(b.size().x, reach) and d < best_d:
			best_d = d
			best = b
	return best

func _clamp_to_field(world: Vector2, b: Block) -> Vector2:
	var margin := b.size() * 0.5
	var r := Rect2(sim.field.position + margin, sim.field.size - margin * 2.0)
	var p := world.clamp(r.position, r.end)
	return b.pos if sim.terrain.is_blocked(p, b.role) else p

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
	_hud["begin"] = _button("Begin battle", _on_begin)
	controls.add_child(_hud["begin"])
	_hud["pause"] = _button("Pause", _on_pause)
	controls.add_child(_hud["pause"])
	_hud["speed"] = _button("1×", _on_speed)
	controls.add_child(_hud["speed"])
	_hud["peek"] = _button("Map", _on_peek)
	controls.add_child(_hud["peek"])
	_hud["fit"] = _button("Fit", func(): _fit_camera())
	controls.add_child(_hud["fit"])
	controls.add_child(_button("Tuning", _on_tuning))

	# Bottom: info, then the order bar --------------------------------------
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
	bottom_box.add_child(_hud["info"])

	var orders := _flow()
	bottom_box.add_child(orders)
	orders.add_child(_button("Move", func(): pending_order = "move"; _refresh_hud()))
	orders.add_child(_button("Attack", func(): pending_order = "attack"; _refresh_hud()))
	orders.add_child(_button("Hold", func(): _for_selection(sim.order_hold)))
	orders.add_child(_button("Withdraw", func(): _for_selection(sim.order_withdraw)))
	orders.add_child(_button("Select all", _select_all))
	orders.add_child(_button("Retreat all", func(): sim.retreat_all(GameConfig.Side.PLAYER)))
	_hud["orders"] = orders

	# Event log, in a corner when there is a corner to spare ----------------
	var log_panel := _panel()
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_right = -HUD_MARGIN
	log_panel.custom_minimum_size = Vector2(280, 0)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_panel)
	_hud["log"] = _label("", true)
	_hud["log"].add_theme_font_size_override("font_size", 12)
	_hud["log"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(_hud["log"])
	_hud["log_panel"] = log_panel

	_build_result_panel()
	_build_tuning_panel()

func _for_selection(fn: Callable) -> void:
	for b in selection:
		if b.alive():
			fn.call(b)

func _select_all() -> void:
	if sim == null:
		return
	selection = sim.side_blocks(GameConfig.Side.PLAYER, true)
	_refresh_hud()

func _build_result_panel() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var panel := _panel()
	wrap.add_child(panel)
	_hud["result_panel"] = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := _label("Battle over")
	title.add_theme_font_size_override("font_size", 19)
	box.add_child(title)
	_hud["result_title"] = title

	var body := _label("", true)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	_hud["result_body"] = body

	var buttons := _flow()
	box.add_child(buttons)
	buttons.add_child(_button("Replay scenario", func(): _load_scenario(scenario_index)))
	buttons.add_child(_button("Back to map", func():
		mode = Mode.STRATEGIC
		sim = null
		_hud["result"].visible = false
		_refresh_hud()
		_fit_camera()))

	wrap.visible = false
	_hud["result"] = wrap

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
		for key in ["health", "morale", "speed", "melee_dps", "ranged_dps", "range", "charge_burst"]:
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
	var in_battle := mode != Mode.STRATEGIC and sim != null
	_hud["end_turn"].visible = mode == Mode.STRATEGIC
	_hud["begin"].visible = in_battle and not sim.started
	_hud["pause"].visible = in_battle and sim.started
	_hud["speed"].visible = in_battle and sim.started
	_hud["peek"].visible = in_battle
	_hud["orders"].visible = in_battle and sim.started and not sim.finished and not peek_map
	_hud["log_panel"].visible = in_battle and size.x >= WIDE_SCREEN
	_hud["pause"].text = "Resume" if paused else "Pause"
	_hud["speed"].text = "%d×" % int(speed)
	_hud["peek"].text = "Battle" if peek_map else "Map"

func _layout_overlays() -> void:
	# Panels that float over the map keep to the screen on a phone.
	var log_panel: PanelContainer = _hud["log_panel"]
	log_panel.offset_top = _hud["top"].size.y + HUD_MARGIN * 2.0
	var tuning: ScrollContainer = _hud["tuning"]
	tuning.offset_left = -minf(320.0, size.x - HUD_MARGIN * 2.0)
	tuning.offset_top = _hud["top"].size.y + HUD_MARGIN * 2.0
	tuning.offset_bottom = -(_hud["bottom"].size.y + HUD_MARGIN * 2.0)
	_hud["result_panel"].custom_minimum_size.x = minf(460.0, size.x - 24.0)

func _refresh_status() -> void:
	_layout_overlays()
	var status: Label = _hud["status"]
	var info: Label = _hud["info"]

	if mode == Mode.STRATEGIC:
		var spec := Scenarios.all()[scenario_index]
		status.text = "Turn %d · %s" % [campaign.turn, spec["lesson"]]
		info.text = _terrain_tooltip()
		return

	if sim == null:
		return

	var left: float = maxf(0.0, GameConfig.combat["battle_seconds"] - sim.time)
	if sim.finished:
		status.text = "Battle over after %0.0fs — %s" % [sim.time, sim.result["reason"]]
	elif not sim.started:
		status.text = "You are the defender — drag blocks to arrange, then Begin."
	else:
		status.text = "%0.1fs left · %d blocks vs %d" % [
			left,
			sim.side_blocks(GameConfig.Side.PLAYER, true).size(),
			sim.side_blocks(GameConfig.Side.ENEMY, true).size(),
		]
	info.text = _selection_tooltip() if not selection.is_empty() else _terrain_tooltip()
	_hud["log"].text = "\n".join(Array(sim.events).slice(maxi(0, sim.events.size() - 8)))

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

func _selection_tooltip() -> String:
	var lines: PackedStringArray = []
	for b in selection:
		if not b.alive():
			continue
		var state := "holding"
		if b.routing:
			state = "ROUTING"
		elif b.order == Block.OrderType.WITHDRAW:
			state = "withdrawing"
		elif b.braced:
			state = "braced"
		elif b.order == Block.OrderType.ATTACK:
			state = "attacking"
		elif b.order == Block.OrderType.MOVE:
			state = "moving"
		lines.append("%s  %d hp  %d morale · %s · %s" % [
			b.stats()["name"], int(b.health), int(b.morale), state,
			terrain.describe(b.pos)["name"],
		])
	if pending_order != "":
		lines.append("Tap a %s target." % pending_order)
	elif touch:
		lines.append("Tap an enemy to attack, tap ground to move.")
	return "\n".join(lines)

# -------------------------------------------------------------------- buttons

func _on_end_turn() -> void:
	var met := campaign.end_turn()
	preview_path = PackedVector2Array()
	if met.size() == 2:
		var player: Army = met[0] if met[0].side == GameConfig.Side.PLAYER else met[1]
		var enemy: Army = met[1] if met[0].side == GameConfig.Side.PLAYER else met[0]
		_begin_battle(player, enemy)

func _on_begin() -> void:
	sim.started = true
	_refresh_hud()

func _on_pause() -> void:
	paused = not paused
	_refresh_hud()

func _on_speed() -> void:
	speed = 1.0 if speed >= 2.0 else 2.0
	_refresh_hud()

func _on_peek() -> void:
	peek_map = not peek_map
	_cancel_pointer()
	_refresh_hud()
	_fit_camera()

func _on_tuning() -> void:
	_hud["tuning"].visible = not _hud["tuning"].visible

func _show_result() -> void:
	mode = Mode.RESULT
	var r := sim.result
	var holder := "nobody"
	if r["holder"] == GameConfig.Side.PLAYER:
		holder = "you"
	elif r["holder"] == GameConfig.Side.ENEMY:
		holder = "the enemy"

	_hud["result_title"].text = "Battle over — %s" % r["reason"]
	var lines: PackedStringArray = [
		"%s holds the field (%s) after %0.0fs." % [holder, r["feature"], r["seconds"]],
		"Losses — you %d, enemy %d.\n" % [
			r["losses"][GameConfig.Side.PLAYER], r["losses"][GameConfig.Side.ENEMY],
		],
	]
	for row in r["rows"]:
		lines.append("%s %-9s %3d/%3d hp   %s" % [
			"you " if row["side"] == GameConfig.Side.PLAYER else "foe ",
			row["name"], int(row["health"]), int(row["max_health"]), row["fate"],
		])
	_hud["result_body"].text = "\n".join(lines)
	_hud["result"].visible = true
	_refresh_hud()
