class_name CampaignRoot
extends Control

## The campaign shell: a seeded `World`, a `MapView` over it, and the HUD.
##
## Nothing here simulates anything. End Turn hands the world to
## `TurnResolver`, the map layers read it and write order fields on it, and
## every rule lives in scripts/sim. The combat prototype (scenes/game.tscn)
## is untouched and still runs on its own.
##
## A workstream adds its map presentation by writing one `MapLayer` and
## appending it to `LAYERS` — no other file in this directory changes.

## The registered layers, in any order: each layer's own `order()` decides
## where it lands, so appending here is never a merge conflict about position.
## Preloads rather than class names (`[GraphLayer, StacksLayer]`): a global
## class name is not a constant expression, so that array cannot be a `const`.
const LAYERS: Array = [
	preload("res://scripts/ui/layers/graph_layer.gd"),
	preload("res://scripts/ui/layers/stacks_layer.gd"),
]

const HUD_MARGIN := 8.0
const PANEL_WIDTH := 300.0
const SEED := 1

var view: MapView

var _hud := {}
var _layer_buttons: Array = []       # [{"button": Button, "enabled": Callable}]
var _overlay: Control = null
var _has_panels := false             # any layer contributed a panel() at build time

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _build_theme()

	view = MapView.new()
	view.world = _seeded_world()
	var built: Array[MapLayer] = []
	for layer_script in LAYERS:
		built.append(layer_script.new())
	view.set_layers(_by_order(built))
	add_child(view)

	_build_hud()
	_build_panel_column()
	_apply_display_scale()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_display_scale)

## The layers sorted by `order()`, stably: two layers that claim the same order
## keep their registry order, so the stack is fully determined by `LAYERS` plus
## the numbers and never depends on the sort's internals.
func _by_order(built: Array[MapLayer]) -> Array[MapLayer]:
	var decorated: Array = []
	for i in built.size():
		decorated.append({"order": built[i].order(), "index": i, "layer": built[i]})
	decorated.sort_custom(func(x, y) -> bool:
		if x["order"] == y["order"]:
			return x["index"] < y["index"]
		return x["order"] < y["order"])
	var out: Array[MapLayer] = []
	for d in decorated:
		out.append(d["layer"])
	return out

func _process(_delta: float) -> void:
	# The map is fitted into what the HUD leaves, and the HUD reflows as its
	# text wraps, so the insets are re-published every frame.
	view.inset_top = _hud["top"].size.y + HUD_MARGIN * 2.0
	view.inset_bottom = _hud["bottom"].size.y + HUD_MARGIN * 2.0
	_layout_overlays()
	_refresh_status()

# ------------------------------------------------------------------ the world

## One line, deliberately. The starting armies live in the map's `"stacks"`
## array, not here: the shell, a test and the headless AI harness all build the
## same world from the same data, and a scenario is a map edit rather than a
## change to the shell.
func _seeded_world() -> World:
	return World.from_map(PrototypeMap.data(), SEED)

# -------------------------------------------------------------------- overlays

## Hide the map and put `control` in its place, full-rect. WS-C switches to the
## battle view this way. The caller keeps ownership: `clear_overlay` unparents
## the control rather than freeing it, so a view can be shown again.
func set_overlay(control: Control) -> void:
	if control == null:
		return
	clear_overlay()
	_overlay = control
	view.visible = false
	add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Behind the HUD, which was added first and must stay clickable.
	move_child(control, 0)

## Put the map back. Safe to call with no overlay showing.
func clear_overlay() -> void:
	if _overlay != null:
		if _overlay.get_parent() == self:
			remove_child(_overlay)
		_overlay = null
	view.visible = true

# -------------------------------------------------------------------- buttons

func _on_end_turn() -> void:
	TurnResolver.end_turn(view.world)
	# A phase can merge or destroy a stack, and a selection pointing at one
	# that is no longer in the world would keep drawing a ring on a ghost.
	if view.selected != null and not view.world.stacks.has(view.selected):
		view.selected = null
	view.queue_redraw()

func _on_reset() -> void:
	view.world = _seeded_world()
	view.selected = null
	view.fit()

## Tuning and the layer panel column occupy the same right-hand rect, and the
## column is added later so it would draw on top. Yield it to the tuning panel
## for as long as that is open, rather than letting "Tuning" silently cover a
## workstream's side panel.
func _on_tuning() -> void:
	var showing: bool = not _hud["tuning"].visible
	_hud["tuning"].visible = showing
	_hud["panels"].visible = _has_panels and not showing

# ------------------------------------------------------------------------ HUD

## Sized for fingers: 44 px minimum touch targets and rows that wrap instead
## of clipping, the same as the combat prototype's HUD.
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
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	return f

func _build_hud() -> void:
	# Top: the run's state, then the controls wrapping beneath ---------------
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

	_hud["status"] = _label()
	_hud["status"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(_hud["status"])

	var controls := _flow()
	top_box.add_child(controls)
	controls.add_child(_button("End Turn", _on_end_turn))
	controls.add_child(_button("Reset", _on_reset))
	controls.add_child(_button("Fit", func(): view.fit()))
	controls.add_child(_button("Tuning", _on_tuning))
	# Every layer's buttons, in layer order, so a workstream's controls appear
	# the moment its layer is registered. `enabled` is optional — most buttons
	# are always available — but a spec with no `action` is a bug in that
	# layer, and the shell says so rather than crashing the whole HUD build.
	for layer in view.layers:
		for spec in layer.buttons():
			var label := str(spec.get("label", "?"))
			if not spec.has("action"):
				push_warning("%s contributed a button '%s' with no action; skipped"
					% [layer.get_script().resource_path.get_file(), label])
				continue
			var b := _button(label, spec["action"])
			controls.add_child(b)
			_layer_buttons.append({
				"button": b,
				"enabled": spec.get("enabled", func() -> bool: return true),
			})

	# Bottom: whatever the pointer is over ----------------------------------
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

	_hud["info"] = _label("", true)
	_hud["info"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Always three lines tall: the map is fitted into what the HUD leaves, so
	# a panel that grew with the hover would make the view jump on every move.
	_hud["info"].custom_minimum_size.y = 54.0
	_hud["info"].max_lines_visible = 3
	bottom.add_child(_hud["info"])

	_build_tuning_panel()

## Every layer's side panel, stacked in a scrolling right-hand column. A layer
## that draws only on the map returns null and costs nothing; the column itself
## stays hidden until some layer wants it, so the foundation shell has no empty
## gutter. Panels are asked once, in layer order, and each layer keeps
## ownership of the instance it handed over.
func _build_panel_column() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_right = -HUD_MARGIN
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_hud["panels"] = scroll

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_hud["panel_box"] = box

	var hosted := 0
	for layer in view.layers:
		var panel := layer.panel()
		if panel == null:
			continue
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(panel)
		hosted += 1
	_has_panels = hosted > 0
	scroll.visible = _has_panels

## The `GameConfig` tables the tuning panel walks, by display name. A
## workstream that adds a `static var` dictionary to `GameConfig` appends one
## line here and gets live tuning for free. Named rather than reflected, so a
## table that gets renamed is a parse error instead of a section that silently
## stops appearing.
func _tables() -> Dictionary:
	return {
		"units": GameConfig.units,
		"combat": GameConfig.combat,
		"terrain_mods": GameConfig.terrain_mods,
		"strategic": GameConfig.strategic,
		"run": GameConfig.run,
		"sites": GameConfig.sites,
	}

## One spinner per numeric leaf of every table. Dictionaries are reference
## types, so a spinner writes straight through to the live table the rules
## read; nested tables (`units`' per-role stats) are walked one level deeper,
## and non-numeric values (names, Vector2 sizes, flags) are skipped because
## there is no sensible spinner for them.
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

	var tables := _tables()
	for table_name in tables:
		var table: Dictionary = tables[table_name]
		box.add_child(_label(table_name.replace("_", " ").capitalize()))
		for key in table:
			var value = table[key]
			if value is Dictionary:
				_add_nested_rows(box, value)
			elif _is_numeric(value):
				box.add_child(_numeric_row(table, key, str(key).replace("_", " ")))

	_hud["tuning"] = scroll

## A nested table (one unit role) labels its rows with its own name, so the
## panel reads "Infantry health" rather than six rows called "health".
func _add_nested_rows(box: VBoxContainer, table: Dictionary) -> void:
	var prefix := str(table["name"]) if table.has("name") else ""
	for key in table:
		if not _is_numeric(table[key]):
			continue
		var label := "%s %s" % [prefix, str(key).replace("_", " ")]
		box.add_child(_numeric_row(table, key, label.strip_edges()))

func _is_numeric(value) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT

## An int stays an int: `run["turns_per_era"]` and the forage counts are used
## as integers, and a spinner that turned them into floats would break the
## functions that return them.
func _numeric_row(table: Dictionary, key, label: String) -> Control:
	var was_int := typeof(table[key]) == TYPE_INT
	var apply := func(v: float) -> void:
		table[key] = int(v) if was_int else v
	return _tuning_row(label, float(table[key]), apply)

func _tuning_row(key: String, value: float, apply: Callable) -> Control:
	var row := HBoxContainer.new()
	var caption := _label(key, true)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 1000.0
	spin.step = 0.05
	spin.value = value
	spin.custom_minimum_size = Vector2(110, 44)
	spin.value_changed.connect(apply)
	row.add_child(spin)
	return row

# ----------------------------------------------------------------- HUD update

func _layout_overlays() -> void:
	var tuning: ScrollContainer = _hud["tuning"]
	tuning.offset_left = -minf(320.0, size.x - HUD_MARGIN * 2.0)
	tuning.offset_top = view.inset_top
	tuning.offset_bottom = -view.inset_bottom

	var panels: ScrollContainer = _hud["panels"]
	panels.offset_left = -minf(PANEL_WIDTH, size.x - HUD_MARGIN * 2.0)
	panels.offset_top = view.inset_top
	panels.offset_bottom = -view.inset_bottom

func _refresh_status() -> void:
	var world := view.world
	var player := world.player()
	var who := player.name if player != null else "—"
	var coin := player.coin if player != null else 0.0
	var influence := player.influence if player != null else 0.0
	_hud["status"].text = "Turn %d · Era %d of %d · %s — %d coin, %d influence" % [
		world.turn, world.era(), int(GameConfig.run["eras"]), who, int(coin), int(influence),
	]

	var text := view.tooltip_at(view.hover_world)
	if text == "":
		text = "Click a stack to select it, then an adjacent site to order it there."
		if world.events.size() > 0:
			text += "\n" + world.events[world.events.size() - 1]
	_hud["info"].text = text

	for entry in _layer_buttons:
		entry["button"].disabled = not bool(entry["enabled"].call())

# -------------------------------------------------------------------- display

## Render one logical pixel per CSS pixel, so a phone with a 3x display does
## not shrink every 44 px touch target to 15.
func _apply_display_scale() -> void:
	var window := get_window()
	if window == null:
		return
	var scale := 1.0
	if OS.has_feature("web"):
		var css_width := float(JavaScriptBridge.eval("window.innerWidth", true))
		if css_width > 0.0:
			scale = float(window.size.x) / css_width
	else:
		scale = DisplayServer.screen_get_scale()
	scale = clampf(snappedf(scale, 0.25), 1.0, 4.0)
	if not is_equal_approx(window.content_scale_factor, scale):
		window.content_scale_factor = scale
