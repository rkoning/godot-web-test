extends Control

## Combat prototype shell: one terrain dataset, two zooms.
##
## Strategic zoom is turn-based and is where position is chosen; battle zoom is
## real time and is where that choice pays off. All simulation lives in
## scripts/sim — this file is presentation and input only.

const DT := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 8

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

var selection: Array[Block] = []
var pending_order := ""           # "move" / "attack" set by the order buttons
var hover_world := Vector2.ZERO
var preview_path: PackedVector2Array = []
var drag_from := Vector2.INF
var drag_to := Vector2.INF
var dragging_block: Block = null  # pre-battle arrangement

var _terrain_texture: ImageTexture
var _font: Font
var _hud := {}

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	terrain = Terrain.new()
	_terrain_texture = _build_terrain_texture()
	_build_hud()
	_load_scenario(0)

# ------------------------------------------------------------------ scenarios

func _load_scenario(index: int) -> void:
	scenario_index = index
	campaign = Scenarios.build(index, terrain)
	sim = null
	mode = Mode.STRATEGIC
	peek_map = false
	selection.clear()
	preview_path = PackedVector2Array()
	_hud["result"].visible = false
	_refresh_hud()

func _begin_battle(player: Army, enemy: Army) -> void:
	sim = Scenarios.start_battle(terrain, player, enemy)
	mode = Mode.BATTLE
	paused = false
	selection.clear()
	_accum = 0.0
	_refresh_hud()

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
	_refresh_status()
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		paused = not paused
		_refresh_hud()

# --------------------------------------------------------------------- camera

## The world rectangle currently on screen.
func _view_rect() -> Rect2:
	if mode == Mode.STRATEGIC or peek_map or sim == null:
		return Rect2(Vector2.ZERO, Terrain.SIZE)
	return sim.field

## Letterboxed fit of the world rect into the control, so the map never skews.
func _view_transform() -> Transform2D:
	var view := _view_rect()
	var zoom: float = minf(size.x / view.size.x, size.y / view.size.y)
	var offset: Vector2 = (size - view.size * zoom) * 0.5 - view.position * zoom
	return Transform2D(0.0, Vector2(zoom, zoom), 0.0, offset)

func _w2s(p: Vector2) -> Vector2:
	return _view_transform() * p

func _s2w(p: Vector2) -> Vector2:
	return _view_transform().affine_inverse() * p

func _zoom() -> float:
	return _view_transform().get_scale().x

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
	var view := _view_rect()
	var xf := _view_transform()

	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.BACKGROUND, true)

	var dest := Rect2(xf * view.position, view.size * _zoom())
	var tex_size := _terrain_texture.get_size()
	var src := Rect2(
		view.position / Terrain.SIZE * tex_size,
		view.size / Terrain.SIZE * tex_size,
	)
	draw_texture_rect_region(_terrain_texture, dest, src)

	_draw_roads()
	if mode == Mode.STRATEGIC or peek_map:
		_draw_strategic()
	if sim != null and not peek_map and mode != Mode.STRATEGIC:
		_draw_battle()

func _draw_roads() -> void:
	for road in Terrain.ROADS:
		var pts := PackedVector2Array()
		for p in road:
			pts.append(_w2s(p))
		draw_polyline(pts, ThemeColors.ROAD, maxf(1.5, 4.0 * _zoom()))

func _draw_strategic() -> void:
	# Feature labels, so the map reads without hovering every cell.
	for f in terrain.features:
		if f["cells"] < 12:
			continue
		var at := _w2s(f["centroid"])
		draw_string(_font, at, String(f["type"]).capitalize(),
			HORIZONTAL_ALIGNMENT_CENTER, -1, 11, ThemeColors.TEXT_DIM * Color(1, 1, 1, 0.75))

	if sim != null and peek_map:
		var r := Rect2(_w2s(sim.field.position), sim.field.size * _zoom())
		draw_rect(r, ThemeColors.ACCENT, false, 2.0)

	# Path preview for the selected army.
	if campaign.selected != null and preview_path.size() > 0:
		var pts := PackedVector2Array([_w2s(campaign.selected.pos)])
		for p in preview_path:
			pts.append(_w2s(p))
		draw_polyline(pts, ThemeColors.ACCENT * Color(1, 1, 1, 0.7), 2.0)

	for a in campaign.armies:
		var at := _w2s(a.pos)
		var col := ThemeColors.side(a.side)
		if a.path.size() > 0:
			var pts := PackedVector2Array([at])
			for p in a.path:
				pts.append(_w2s(p))
			draw_polyline(pts, col * Color(1, 1, 1, 0.5), 1.5)

		draw_circle(at, 11.0, col.darkened(0.45))
		draw_arc(at, 11.0, 0.0, TAU, 24, col, 2.0)
		# Supply as a filled arc around the marker.
		draw_arc(at, 15.0, -PI / 2.0, -PI / 2.0 + TAU * a.supply, 24, ThemeColors.ACCENT, 3.0)
		if campaign.selected == a:
			draw_arc(at, 19.0, 0.0, TAU, 28, ThemeColors.TEXT, 1.5)
		draw_string(_font, at + Vector2(-26, 32), "%s  %d%%" % [a.label, int(a.supply * 100.0)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

func _draw_battle() -> void:
	var z := _zoom()

	if drag_from != Vector2.INF and drag_to != Vector2.INF:
		var r := Rect2(drag_from, drag_to - drag_from).abs()
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
	if event is InputEventMouseMotion:
		hover_world = _s2w(event.position)
		if dragging_block != null:
			dragging_block.pos = _clamp_to_field(hover_world, dragging_block)
		elif drag_from != Vector2.INF:
			drag_to = event.position
		elif mode == Mode.STRATEGIC and campaign.selected != null:
			preview_path = campaign.find_path(campaign.selected.pos, hover_world)
		return

	if event is InputEventMouseButton:
		if mode == Mode.STRATEGIC or peek_map:
			_strategic_click(event)
		elif mode != Mode.RESULT or sim != null:
			_battle_click(event)

func _strategic_click(event: InputEventMouseButton) -> void:
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or peek_map:
		return
	var world := _s2w(event.position)
	var army := campaign.army_at(world)
	if army != null and army.side == GameConfig.Side.PLAYER:
		campaign.selected = army
		preview_path = PackedVector2Array()
		return
	if campaign.selected != null:
		campaign.selected.path = campaign.find_path(campaign.selected.pos, world)

func _battle_click(event: InputEventMouseButton) -> void:
	var world := _s2w(event.position)

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _block_at(world, GameConfig.Side.PLAYER)
			# Before the clock starts the defender may drag blocks into place.
			if hit != null and sim != null and not sim.started and sim.player_is_defender:
				dragging_block = hit
				selection = [hit] as Array[Block]
				return
			if pending_order != "":
				_apply_pending(world)
				return
			if hit != null:
				selection = [hit] as Array[Block]
			else:
				drag_from = event.position
				drag_to = event.position
		else:
			dragging_block = null
			if drag_from != Vector2.INF:
				_box_select()
				drag_from = Vector2.INF
				drag_to = Vector2.INF
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_at(world)

## Right-click, or a click after pressing Move/Attack: attack an enemy under the
## cursor, otherwise move there.
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

func _box_select() -> void:
	var rect := Rect2(drag_from, drag_to - drag_from).abs()
	if rect.size.length() < 6.0:
		selection.clear()
		return
	var picked: Array[Block] = []
	for b in sim.blocks:
		if b.alive() and b.side == GameConfig.Side.PLAYER and rect.has_point(_w2s(b.pos)):
			picked.append(b)
	selection = picked

func _block_at(world: Vector2, side: int) -> Block:
	if sim == null:
		return null
	var best: Block = null
	var best_d := INF
	for b in sim.blocks:
		if not b.alive() or b.side != side:
			continue
		if side != GameConfig.Side.PLAYER and not sim.visible_to(b, GameConfig.Side.PLAYER):
			continue
		var d: float = b.pos.distance_to(world)
		if d < maxf(b.size().x, 18.0) and d < best_d:
			best_d = d
			best = b
	return best

func _clamp_to_field(world: Vector2, b: Block) -> Vector2:
	var margin := b.size() * 0.5
	var r := Rect2(sim.field.position + margin, sim.field.size - margin * 2.0)
	var p := world.clamp(r.position, r.end)
	return b.pos if sim.terrain.is_blocked(p, b.role) else p

# ----------------------------------------------------------------------- HUD

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
	b.pressed.connect(pressed)
	return b

func _label(text := "", dim := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ThemeColors.TEXT_DIM if dim else ThemeColors.TEXT)
	l.add_theme_font_size_override("font_size", 12)
	return l

func _build_hud() -> void:
	# Top bar -----------------------------------------------------------------
	var top := _panel()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 10
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)

	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for s in Scenarios.all():
		picker.add_item(s["name"])
	picker.item_selected.connect(_load_scenario)
	row.add_child(picker)
	_hud["scenario"] = picker

	_hud["status"] = _label()
	_hud["status"].custom_minimum_size.x = 360
	row.add_child(_hud["status"])

	row.add_child(_spacer())
	_hud["end_turn"] = _button("End Turn", _on_end_turn)
	row.add_child(_hud["end_turn"])
	_hud["begin"] = _button("Begin battle", _on_begin)
	row.add_child(_hud["begin"])
	_hud["pause"] = _button("Pause", _on_pause)
	row.add_child(_hud["pause"])
	_hud["speed"] = _button("1×", _on_speed)
	row.add_child(_hud["speed"])
	_hud["peek"] = _button("Map", _on_peek)
	row.add_child(_hud["peek"])
	row.add_child(_button("Tuning", _on_tuning))

	# Info panel (hover terrain / selection) ----------------------------------
	var info := _panel()
	info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info.offset_left = 10
	info.offset_top = -120
	info.offset_bottom = -10
	info.custom_minimum_size = Vector2(340, 0)
	add_child(info)
	_hud["info"] = _label()
	_hud["info"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud["info"].custom_minimum_size.x = 320
	info.add_child(_hud["info"])
	_hud["info_panel"] = info

	# Order bar ---------------------------------------------------------------
	var orders := _panel()
	orders.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	orders.offset_bottom = -10
	orders.offset_top = -56
	add_child(orders)
	var obox := HBoxContainer.new()
	obox.add_theme_constant_override("separation", 6)
	orders.add_child(obox)
	obox.add_child(_button("Move", func(): pending_order = "move"; _refresh_hud()))
	obox.add_child(_button("Attack", func(): pending_order = "attack"; _refresh_hud()))
	obox.add_child(_button("Hold", func(): _for_selection(sim.order_hold)))
	obox.add_child(_button("Withdraw", func(): _for_selection(sim.order_withdraw)))
	obox.add_child(_button("Retreat all", func(): sim.retreat_all(GameConfig.Side.PLAYER)))
	_hud["orders"] = orders

	# Event log ---------------------------------------------------------------
	var log_panel := _panel()
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_right = -10
	log_panel.offset_top = 70
	log_panel.custom_minimum_size = Vector2(280, 0)
	add_child(log_panel)
	_hud["log"] = _label("", true)
	log_panel.add_child(_hud["log"])
	_hud["log_panel"] = log_panel

	_build_result_panel()
	_build_tuning_panel()

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _for_selection(fn: Callable) -> void:
	for b in selection:
		if b.alive():
			fn.call(b)

func _build_result_panel() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var panel := _panel()
	panel.custom_minimum_size = Vector2(460, 0)
	wrap.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := _label("Battle over")
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	_hud["result_title"] = title

	var body := _label("", true)
	body.custom_minimum_size.x = 440
	box.add_child(body)
	_hud["result_body"] = body

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	buttons.add_child(_button("Replay scenario", func(): _load_scenario(scenario_index)))
	buttons.add_child(_button("Back to map", func():
		mode = Mode.STRATEGIC
		sim = null
		_hud["result"].visible = false
		_refresh_hud()))

	wrap.visible = false
	_hud["result"] = wrap

func _build_tuning_panel() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_left = -300
	scroll.offset_right = -10
	scroll.offset_top = 70
	scroll.offset_bottom = -140
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
	name.custom_minimum_size.x = 170
	row.add_child(name)
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 1000.0
	spin.step = 0.05
	spin.value = value
	spin.custom_minimum_size.x = 90
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
	_hud["log_panel"].visible = in_battle
	_hud["pause"].text = "Resume" if paused else "Pause"
	_hud["speed"].text = "%d×" % int(speed)
	_hud["peek"].text = "Battle" if peek_map else "Map"

func _refresh_status() -> void:
	var status: Label = _hud["status"]
	var info: Label = _hud["info"]

	if mode == Mode.STRATEGIC:
		var spec := Scenarios.all()[scenario_index]
		status.text = "Turn %d   ·   %s" % [campaign.turn, spec["lesson"]]
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
		status.text = "%0.1fs left   ·   %d blocks vs %d" % [
			left,
			sim.side_blocks(GameConfig.Side.PLAYER, true).size(),
			sim.side_blocks(GameConfig.Side.ENEMY, true).size(),
		]
	info.text = _selection_tooltip() if not selection.is_empty() else _terrain_tooltip()
	_hud["log"].text = "\n".join(Array(sim.events).slice(maxi(0, sim.events.size() - 10)))

func _terrain_tooltip() -> String:
	var d := terrain.describe(hover_world)
	var text := "%s\n%s" % [d["name"], d["effect"]]
	if mode == Mode.STRATEGIC and campaign.selected != null and preview_path.size() > 0:
		var cost := campaign.path_cost(campaign.selected.pos, preview_path)
		text += "\n\n%d turn(s) away   ·   supply cost ≈ %d%%" % [
			campaign.turns_for(campaign.selected.pos, preview_path),
			int(cost / 20.0),
		]
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
		lines.append("%s  %d hp  %d morale  · %s  · %s" % [
			b.stats()["name"], int(b.health), int(b.morale), state,
			terrain.describe(b.pos)["name"],
		])
	if pending_order != "":
		lines.append("\nClick a %s target." % pending_order)
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
	_refresh_hud()

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
