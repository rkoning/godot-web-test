class_name BattleView
extends Control

## The real-time battle screen, as a component: it owns a `BattleSim`, steps
## it, draws it, takes orders by mouse or finger, and ends on a result panel
## whose buttons belong to the host. The combat prototype hosts one as a
## child; the campaign hosts one through `CampaignRoot.set_overlay`.
##
## Hidden is paused: the sim only steps while the view is visible in the tree,
## so a host that peeks at its map just hides this.

const DT := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 8
const DRAG_THRESHOLD_PX := 10.0
const HUD_MARGIN := 8.0
const WIDE_SCREEN := 760.0

var terrain: Terrain
var sim: BattleSim
var touch := false
var insets := Callable()
var result_actions: Array[Dictionary] = []

var paused := false
var speed := 1.0
var _accum := 0.0
var camera := MapCamera.new()

var selection: Array[Block] = []
var hover_block: Block = null
var _ack := {}
var hover_world := Vector2.ZERO

var _press_screen := Vector2.INF
var _press_moved := false
var _press_block: Block = null
var _box_to := Vector2.INF
var dragging_block: Block = null
var _stroke: PackedVector2Array = []   # world points of the stroke being drawn
var _stroke_kind := ""                 # "" | "route" | "line"
var _stroke_lead: Block = null         # the block a route is drawn from
var _preview_key := []                 # what _preview was computed for
var _preview: Variant = null           # cached route / formation preview of the stroke

var _touches := {}
var _gesture := false
var _gesture_dist := 0.0
var _gesture_mid := Vector2.ZERO
var _pan_button := -1
var _pan_moved := false

var _font: Font
var _hud := {}

static var _textures := {}           # Terrain -> ImageTexture

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_hud()

func _notification(what: int) -> void:
	# Hidden mid-stroke (a peek, an overlay): drop the press so the clock
	# does not stay slowed and no stale stroke survives.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_cancel_pointer()
	# Focus lost mid-press (a release outside the window never arrives): the
	# same, so the battle cannot be left slowed.
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_pointer()

## Must be called after this view is in the tree (add_child first).
func open(p_terrain: Terrain, p_sim: BattleSim, p_touch: bool) -> void:
	assert(is_inside_tree(), "BattleView.open() needs the view in the tree: add_child first")
	terrain = p_terrain
	sim = p_sim
	touch = p_touch
	paused = false
	_accum = 0.0
	selection.clear()
	hover_block = null
	_cancel_pointer()
	_hud["result"].visible = false
	_refresh_hud()
	fit()

func result_shown() -> bool:
	return _hud["result"].visible

## The rasterised terrain, shared by every view of the same Terrain.
static func terrain_texture(t: Terrain) -> ImageTexture:
	if not _textures.has(t):
		_textures[t] = _rasterise(t)
	return _textures[t]

static func detect_touch() -> bool:
	if OS.has_feature("web"):
		var forced := NetConfig._query_param("input")
		if forced == "touch":
			return true
		if forced == "mouse":
			return false
	return DisplayServer.is_touchscreen_available()

func _insets() -> Vector2:
	return insets.call() if insets.is_valid() else Vector2.ZERO

func _map_area() -> Rect2:
	var cover := _insets()
	var top: float = cover.x + _hud["top"].size.y + HUD_MARGIN * 2.0
	var bottom: float = size.y - cover.y - _hud["bottom"].size.y - HUD_MARGIN * 2.0
	return Rect2(0.0, top, size.x, maxf(bottom - top, 1.0))

func fit() -> void:
	camera.screen = _map_area()
	if sim != null:
		camera.fit(sim.field.grow(16.0))

func _w2s(p: Vector2) -> Vector2:
	return camera.w2s(p)

func _s2w(p: Vector2) -> Vector2:
	return camera.s2w(p)

func _process(delta: float) -> void:
	if sim == null:
		return
	if is_visible_in_tree() and sim.started and not sim.finished and not paused:
		_accum += delta * speed * _time_scale()
		var steps := 0
		while _accum >= DT and steps < MAX_STEPS_PER_FRAME:
			sim.step(DT)
			_accum -= DT
			steps += 1
	if sim.finished and not _hud["result"].visible:
		_show_result()
	_layout()
	camera.rescreen(_map_area())
	_refresh_status()
	queue_redraw()

## The battle runs slow while a stroke is being drawn, so the player can draw
## without the fight running away from them.
func _time_scale() -> float:
	if _stroke_kind != "" and _press_moved:
		return float(GameConfig.combat["draw_time_scale"])
	return 1.0

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		paused = not paused
		_refresh_hud()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.BACKGROUND, true)
	if sim == null:
		return
	draw_texture_rect(terrain_texture(terrain), Rect2(_w2s(Vector2.ZERO), Terrain.SIZE * camera.zoom), false)
	for road in Terrain.ROADS:
		var pts := PackedVector2Array()
		for p in road:
			pts.append(_w2s(p))
		draw_polyline(pts, ThemeColors.ROAD, maxf(1.5, 4.0 * camera.zoom))
	_draw_field_edge()
	_draw_battle()

# ------------------------------------------------------------------- drawing

## The terrain is rasterised once into a texture; both zooms sample the same
## image, which is what keeps the two views honest about being one dataset.
static func _rasterise(terrain: Terrain) -> ImageTexture:
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

func _draw_battle() -> void:
	var z := camera.zoom

	if _box_to != Vector2.INF and _press_screen != Vector2.INF:
		var r := Rect2(_press_screen, _box_to - _press_screen).abs()
		draw_rect(r, ThemeColors.ACCENT * Color(1, 1, 1, 0.12), true)
		draw_rect(r, ThemeColors.ACCENT, false, 1.0)

	_draw_ranges()
	for b in sim.blocks:
		if not b.alive() or not sim.visible_to(b, GameConfig.Side.PLAYER):
			continue
		_draw_block(b, z)

	_draw_orders()
	_draw_stroke()
	_draw_combat()
	_draw_tags()
	_draw_ack()

## Every visible archer's reach, drawn under the blocks: a faint ring in its
## side's colour, firmer and lightly filled while it is selected. It is the
## flat-ground reach; shooting downhill carries a little further.
func _draw_ranges() -> void:
	for b in sim.blocks:
		if not b.alive() or b.routing or b.stats()["ranged_dps"] <= 0.0:
			continue
		if not sim.visible_to(b, GameConfig.Side.PLAYER):
			continue
		var at := _w2s(b.pos)
		var radius := sim.shooting_range(b) * camera.zoom
		var col := ThemeColors.side(b.side)
		if selection.has(b):
			draw_circle(at, radius, col * Color(1, 1, 1, 0.06))
			draw_arc(at, radius, 0.0, TAU, 96, col * Color(1, 1, 1, 0.6), 1.5)
		else:
			draw_arc(at, radius, 0.0, TAU, 96, col * Color(1, 1, 1, 0.22), 1.0)

## A block is drawn in its own frame: local +x is the way it faces, so the
## long side (the front) runs along local y.
func _draw_block(b: Block, z: float) -> void:
	if b.reforming():
		_draw_reform(b, z)
		return
	var d: float = b.depth()
	var w: float = b.frontage()
	var body_rect := Rect2(Vector2(-d * 0.5, -w * 0.5), Vector2(d, w))
	var col := ThemeColors.side(b.side)
	var engaged := sim.is_engaged(b)
	var pulse: float = 0.5 + 0.5 * sin(sim.time * 12.0)
	var routing_flash: bool = b.routing and fmod(sim.time, 0.4) < 0.2

	draw_set_transform(_w2s(b.pos), b.facing, Vector2(z, z))

	# Selection first, so the block sits on top of its ring.
	if selection.has(b):
		draw_rect(body_rect.grow(5.0), ThemeColors.ACCENT * Color(1, 1, 1, 0.35), false, 6.0)
		draw_rect(body_rect.grow(3.0), ThemeColors.TEXT, false, 1.5)
	elif b == hover_block:
		draw_rect(body_rect.grow(3.0), ThemeColors.TEXT * Color(1, 1, 1, 0.6), false, 1.2)

	var body := col.darkened(0.55)
	if b.routing:
		body = (ThemeColors.WARN if routing_flash else col).darkened(0.35)
	draw_rect(body_rect, body, true)

	# Health fills the block along its front.
	var hf: float = clampf(b.health / b.max_health, 0.0, 1.0)
	draw_rect(Rect2(body_rect.position, Vector2(d, w * hf)), col, true)

	# Just took a hit: a flash that fades over a third of a second.
	if b.hit_flash > 0.0:
		draw_rect(body_rect, Color(1, 1, 1, 0.7 * b.hit_flash / 0.3), true)

	# Morale is the outline: a shaky block has a thin edge. Fighting turns it hot.
	var mf: float = clampf(b.morale / b.max_morale, 0.0, 1.0)
	var edge := col.lightened(0.35)
	if engaged:
		edge = ThemeColors.WARN.lerp(Color.WHITE, pulse * 0.5)
	draw_rect(body_rect, edge, false, 0.6 + 2.4 * mf)

	# The front edge is the long side: bright, and accent-coloured when braced.
	var front_col := ThemeColors.ACCENT if b.braced else col.lightened(0.6)
	draw_line(Vector2(d * 0.5, -w * 0.5), Vector2(d * 0.5, w * 0.5), front_col,
		3.0 if b.braced else 1.8)
	draw_colored_polygon(PackedVector2Array([
		Vector2(d * 0.5, -3.0), Vector2(d * 0.5 + 3.5, 0.0), Vector2(d * 0.5, 3.0),
	]), front_col)

	_draw_role_mark(b.stats()["mark"], col.lightened(0.6))

	if b.order == Block.OrderType.WITHDRAW:
		draw_rect(body_rect.grow(2.0), ThemeColors.WARN, false, 1.0)

	draw_set_transform_matrix(Transform2D.IDENTITY)

## A reform, drawn: the ranks open into loose marks, the cluster wheels from
## its old facing to the new one (ease in-out), and closes up again; a ring
## counts the time down. The sim's facing only flips at the end.
func _draw_reform(b: Block, z: float) -> void:
	var total := maxf(float(b.stats()["reform_time"]), 0.01)
	var t := clampf(1.0 - b.reform_left / total, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var angle := lerp_angle(b.reform_from, sim.reform_facing(b), eased)
	var loose := sin(t * PI) * 4.0
	var d: float = b.depth()
	var w: float = b.frontage()
	var col := ThemeColors.side(b.side)
	var ranks := 3
	var files := 6
	draw_set_transform(_w2s(b.pos), angle, Vector2(z, z))
	for r in ranks:
		for f in files:
			var base := Vector2((float(r) + 0.5) / float(ranks) * d - d * 0.5,
				(float(f) + 0.5) / float(files) * w - w * 0.5)
			var jitter := Vector2(sin(float(b.id * 13 + r * 7 + f * 3)),
				cos(float(b.id * 5 + r * 11 + f * 17))) * loose
			draw_rect(Rect2(base + jitter - Vector2(1.5, 1.5), Vector2(3, 3)), col.lightened(0.3), true)
	draw_line(Vector2(d * 0.5 + loose, -w * 0.5), Vector2(d * 0.5 + loose, w * 0.5),
		col.lightened(0.6) * Color(1, 1, 1, 0.5), 1.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var at := _w2s(b.pos)
	var radius := (maxf(d, w) * 0.5 + 6.0) * z
	draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * t, 32, ThemeColors.ACCENT, 2.0)
	if selection.has(b):
		draw_arc(at, radius + 4.0, 0.0, TAU, 32, ThemeColors.TEXT, 1.5)

## Where every one of the player's blocks is going or who it is after, not
## just the selected ones: a move is a dashed accent line to a ring, an attack
## is a red arrow to a bracketed target.
func _draw_orders() -> void:
	for b in sim.blocks:
		if not b.alive() or b.side != GameConfig.Side.PLAYER or b.routing:
			continue
		var from := _w2s(b.pos)
		if b.order == Block.OrderType.MOVE:
			# What is left of the route, dashed; a route drawn onto an enemy
			# ends in a red arrow to it instead of a ring.
			var col := ThemeColors.ACCENT * Color(1, 1, 1, 0.85)
			var prev := from
			var points: PackedVector2Array = b.route if not b.route.is_empty() else PackedVector2Array([b.order_point])
			for p in points:
				var at := _w2s(p)
				_draw_dashes(prev, at, col, 2.0, 0.0)
				prev = at
			var aim := sim.block_by_id(b.route_target_id)
			if aim != null and aim.alive() and sim.visible_to(aim, GameConfig.Side.PLAYER):
				var red := ThemeColors.ENEMY.lightened(0.25)
				_draw_arrow(prev, _w2s(aim.pos), red, 2.0, 9.0)
				_draw_brackets(_screen_bounds(aim).grow(4.0), red)
			else:
				draw_circle(prev, 6.0, ThemeColors.ACCENT * Color(1, 1, 1, 0.25))
				draw_arc(prev, 6.0, 0.0, TAU, 20, col, 1.5)
		elif b.order == Block.OrderType.ATTACK:
			var t := sim.block_by_id(b.target_id)
			if t == null or not t.alive() or not sim.visible_to(t, GameConfig.Side.PLAYER):
				continue
			var col := ThemeColors.ENEMY.lightened(0.25)
			if not sim.is_engaged(b):
				_draw_arrow(from, _w2s(t.pos), col, 2.0, 9.0)
			_draw_brackets(_screen_bounds(t).grow(4.0 + 2.0 * (0.5 + 0.5 * sin(sim.time * 6.0))), col)
		elif b.order == Block.OrderType.SHOOT:
			# A Shoot order: a thin dotted sight line to the chosen target —
			# accent while it is out of reach and the block is closing, the
			# enemy colour once it is in reach and being shot.
			var t := sim.block_by_id(b.target_id)
			if t == null or not t.alive() or not sim.visible_to(t, GameConfig.Side.PLAYER):
				continue
			var reach := sim.in_reach(b, t)
			var col := ThemeColors.ENEMY.lightened(0.35) if reach else ThemeColors.ACCENT
			_draw_dashes(from, _w2s(t.pos), col * Color(1, 1, 1, 0.8), 1.5, sim.time * 20.0)
			_draw_brackets(_screen_bounds(t).grow(3.0), col)

## The stroke being drawn, as it will be walked; an enemy under the tip gets
## brackets (attack at the end); a formation stroke shows ghost slots.
func _draw_stroke() -> void:
	if _stroke_kind == "" or not _press_moved or _stroke.size() < 2:
		return
	var col := ThemeColors.ACCENT
	if _stroke_kind == "route" and _stroke_lead != null:
		var walk: PackedVector2Array = _stroke_preview()
		var pts := PackedVector2Array([_w2s(_stroke_lead.pos)])
		for p in walk:
			pts.append(_w2s(p))
		if pts.size() >= 2:
			draw_polyline(pts, col, 3.0)
		var foe := _block_at(_stroke[_stroke.size() - 1], GameConfig.Side.ENEMY)
		if foe != null:
			_draw_brackets(_screen_bounds(foe).grow(6.0), ThemeColors.ENEMY.lightened(0.25))
	elif _stroke_kind == "line":
		var raw := PackedVector2Array()
		for p in _stroke:
			raw.append(_w2s(p))
		draw_polyline(raw, col * Color(1, 1, 1, 0.8), 2.0)
		for s in _stroke_preview():
			var b: Block = s["block"]
			var d := b.depth()
			var w := b.frontage()
			draw_set_transform(_w2s(s["pos"]), s["facing"], Vector2(camera.zoom, camera.zoom))
			draw_rect(Rect2(Vector2(-d * 0.5, -w * 0.5), Vector2(d, w)), col * Color(1, 1, 1, 0.5), false, 1.5)
			draw_line(Vector2(d * 0.5, -w * 0.5), Vector2(d * 0.5, w * 0.5), col, 2.0)
			draw_set_transform_matrix(Transform2D.IDENTITY)

## The cleaned route (route strokes) or formation slots (line strokes) for the
## stroke so far. Cleaning can run an A* per sample, so it is only redone when
## the stroke, its kind, its lead (or where the lead stands, to the unit) or
## the selection changes, not every frame.
func _stroke_preview() -> Variant:
	var ids := []
	for b in selection:
		ids.append(b.id)
	var lead_at := _stroke_lead.pos.round() if _stroke_lead != null else Vector2.INF
	var key := [_stroke_kind, _stroke_lead, lead_at, _stroke.size(), ids]
	if key != _preview_key:
		_preview_key = key
		if _stroke_kind == "route":
			_preview = sim.clean_route(_stroke_lead, _walk_stroke())
		else:
			_preview = sim.formation_slots(_live_selection(), _stroke)
	return _preview

## Where the fighting is: a spinning clash between every pair of engaged
## blocks, and dashes streaming from archers to whoever they are shooting.
func _draw_combat() -> void:
	var seen := {}
	for a in sim.blocks:
		if not a.alive() or not sim.visible_to(a, GameConfig.Side.PLAYER):
			continue
		for b in sim.contacts_of(a):
			if not b.alive() or not sim.visible_to(b, GameConfig.Side.PLAYER):
				continue
			var key := "%d-%d" % [mini(a.id, b.id), maxi(a.id, b.id)]
			if seen.has(key):
				continue
			seen[key] = true
			_draw_clash(_w2s((a.pos + b.pos) * 0.5))
	for a in sim.blocks:
		if not a.alive() or a.shooting_id < 0 or not sim.visible_to(a, GameConfig.Side.PLAYER):
			continue
		var t := sim.block_by_id(a.shooting_id)
		if t == null or not t.alive():
			continue
		_draw_dashes(_w2s(a.pos), _w2s(t.pos), ThemeColors.side(a.side) * Color(1, 1, 1, 0.8),
			1.5, sim.time * 2.5)

func _draw_clash(c: Vector2) -> void:
	var pulse: float = 0.5 + 0.5 * sin(sim.time * 12.0)
	var r: float = 6.0 + 3.0 * pulse
	for i in 4:
		var dir := Vector2.RIGHT.rotated(sim.time * 4.0 + float(i) * PI / 4.0) * r
		draw_line(c - dir, c + dir, ThemeColors.WARN, 2.0)
	draw_circle(c, 2.5 + 1.5 * pulse, Color.WHITE)

## A word over each of the player's blocks that is doing something, and over
## an enemy that is running. Fighting is already shown by the clash between
## the two blocks, so the tag goes on the player's side only. Tags that would
## sit on top of each other stack upward instead.
func _draw_tags() -> void:
	var z := camera.zoom
	var placed: Array[Rect2] = []
	for b in sim.blocks:
		if not b.alive() or not sim.visible_to(b, GameConfig.Side.PLAYER):
			continue
		var tag := _block_tag(b)
		if tag == "":
			continue
		var col := ThemeColors.TEXT
		if b.routing or sim.is_engaged(b):
			col = ThemeColors.WARN
		elif b.braced:
			col = ThemeColors.ACCENT
		var lift: float = maxf(b.frontage(), b.depth()) * 0.5 * z + 7.0
		var p := _w2s(b.pos) + Vector2(0.0, -lift)
		var tw: float = _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var box := Rect2(p.x - tw * 0.5 - 3.0, p.y - 11.0, tw + 6.0, 14.0)
		var bumped := true
		while bumped:
			bumped = false
			for other in placed:
				if other.intersects(box):
					box.position.y -= 15.0
					bumped = true
					break
		placed.append(box)
		draw_rect(box, Color(0, 0, 0, 0.6), true)
		draw_string(_font, Vector2(box.position.x + 3.0, box.end.y - 3.0), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

func _block_tag(b: Block) -> String:
	if b.routing:
		return "ROUTING"
	if b.side != GameConfig.Side.PLAYER:
		return ""
	if b.reforming():
		return "REFORMING"
	if sim.is_engaged(b):
		return "FIGHTING"
	if b.braced:
		return "BRACED"
	match b.order:
		Block.OrderType.WITHDRAW: return "WITHDRAWING"
		Block.OrderType.ATTACK: return "ATTACKING"
		Block.OrderType.SHOOT:
			var t := sim.block_by_id(b.target_id)
			return "SHOOTING" if t != null and sim.in_reach(b, t) else "CLOSING IN"
		Block.OrderType.MOVE: return "MOVING"
		Block.OrderType.HOLD: return "HOLDING"
	return ""

## A ring that ripples out from where the last order landed, so a tap is
## visibly acknowledged even before the block starts moving.
func _draw_ack() -> void:
	if _ack.is_empty():
		return
	var age: float = _now() - _ack["at"]
	if age > 0.5:
		_ack = {}
		return
	var f := age / 0.5
	draw_arc(_w2s(_ack["pos"]), 8.0 + 22.0 * f, 0.0, TAU, 24,
		ThemeColors.TEXT * Color(1, 1, 1, 1.0 - f), 2.5)

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _screen_bounds(b: Block) -> Rect2:
	var pts := b.corners()
	var r := Rect2(_w2s(pts[0]), Vector2.ZERO)
	for i in range(1, pts.size()):
		r = r.expand(_w2s(pts[i]))
	return r

func _draw_dashes(from: Vector2, to: Vector2, col: Color, width: float, phase: float) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var period := 12.0
	var offset: float = fmod(phase * period, period)
	var s: float = offset - period
	while s < length:
		var a: float = clampf(s, 0.0, length)
		var e: float = clampf(s + period * 0.5, 0.0, length)
		if e > a:
			draw_line(from + dir * a, from + dir * e, col, width)
		s += period

func _draw_arrow(from: Vector2, to: Vector2, col: Color, width: float, head: float) -> void:
	if from.distance_to(to) < head:
		return
	var dir := (to - from).normalized()
	var tip := to - dir * 6.0
	draw_line(from, tip - dir * head * 0.5, col, width)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - dir * head + dir.orthogonal() * head * 0.5,
		tip - dir * head - dir.orthogonal() * head * 0.5,
	]), col)

## Four corner brackets: a target reticle around a rect.
func _draw_brackets(r: Rect2, col: Color) -> void:
	var arm: float = minf(8.0, minf(r.size.x, r.size.y) * 0.4)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx: float = 1.0 if corner.x == r.position.x else -1.0
		var sy: float = 1.0 if corner.y == r.position.y else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0.0), col, 2.0)
		draw_line(corner, corner + Vector2(0.0, arm * sy), col, 2.0)

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
			if event.pressed and event.double_click and _charge_at(event.position):
				return                  # the first click already shot; this one charges
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
		if event.double_tap and _touches.size() == 1:
			_charge_at(event.position)
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
		# A pan press shares _press_screen with the left pointer: whatever the
		# left button was doing (a stroke, a box, a drag) is off.
		if _press_screen != Vector2.INF and _pan_button == -1:
			_cancel_pointer()
		_pan_button = event.button_index
		_pan_moved = false
		_press_screen = event.position
		return
	var was_click := _pan_button == MOUSE_BUTTON_RIGHT and not _pan_moved
	_pan_button = -1
	if was_click and sim != null:
		_issue_at(_s2w(event.position))
	_press_screen = Vector2.INF

# --- one pointer ------------------------------------------------------------

func _pointer_down(screen: Vector2) -> void:
	_press_screen = screen
	_press_moved = false
	hover_world = _s2w(screen)
	# Never inherit a stroke or box from a press that ended some other way.
	_clear_stroke()
	_box_to = Vector2.INF

	if sim == null:
		return
	_press_block = _block_at(hover_world, GameConfig.Side.PLAYER)
	# Before the clock starts the defender may drag blocks into place.
	if _press_block != null and not sim.started and sim.player_is_defender:
		dragging_block = _press_block
		selection = [_press_block] as Array[Block]
	if not sim.started:
		return
	# Once the clock runs a drag is a drawing: from your block it is that
	# block's route, anywhere else with a selection it is their formation line.
	if _press_block != null:
		_stroke_kind = "route"
		_stroke_lead = _press_block
	elif not selection.is_empty():
		_stroke_kind = "line"
	_stroke = PackedVector2Array([hover_world])

func _pointer_move(screen: Vector2) -> void:
	hover_world = _s2w(screen)

	if _press_screen == Vector2.INF:
		# Plain hover, mouse only: show what a click on the battlefield would pick.
		if touch:
			return
		if sim == null:
			return
		_update_hover()
		return

	if not _press_moved and screen.distance_to(_press_screen) < DRAG_THRESHOLD_PX:
		return
	_press_moved = true

	if dragging_block != null:
		dragging_block.pos = _clamp_to_field(hover_world, dragging_block)
		return

	if sim == null:
		return
	if _stroke_kind != "":
		if _stroke.is_empty() or hover_world.distance_to(_stroke[_stroke.size() - 1]) >= 4.0 / camera.zoom:
			_stroke.append(hover_world)
		return
	_box_to = screen

## What is under the mouse, and a cursor that says what a click would do.
func _update_hover() -> void:
	hover_block = _block_at(hover_world, GameConfig.Side.PLAYER)
	var shape := Control.CURSOR_ARROW
	if hover_block != null:
		shape = Control.CURSOR_POINTING_HAND
	elif not selection.is_empty():
		var foe := _block_at(hover_world, GameConfig.Side.ENEMY)
		if foe != null:
			hover_block = foe
			shape = Control.CURSOR_CROSS
	mouse_default_cursor_shape = shape

func _pointer_up(screen: Vector2) -> void:
	if _press_screen == Vector2.INF:
		return
	var world := _s2w(screen)
	var tapped := not _press_moved

	if dragging_block != null:
		dragging_block = null
	elif sim != null:
		if _stroke_kind != "" and _press_moved:
			_finish_stroke(world, screen)
		elif _box_to != Vector2.INF:
			_box_select(Rect2(_press_screen, _box_to - _press_screen).abs())
		elif tapped:
			_battle_tap(world)

	_press_screen = Vector2.INF
	_press_moved = false
	_press_block = null
	_box_to = Vector2.INF
	_clear_stroke()
	_refresh_hud()

func _cancel_pointer() -> void:
	_press_screen = Vector2.INF
	_press_moved = false
	_press_block = null
	_box_to = Vector2.INF
	_clear_stroke()
	dragging_block = null
	_pan_button = -1

## A released stroke becomes orders. Shorter than 20 px: a tap. A route
## released back on its own block: nothing. A route ends on an enemy → attack it; on
## ground → face the way the stroke was heading. A line forms the selection.
func _finish_stroke(world: Vector2, screen: Vector2) -> void:
	if _press_screen.distance_to(screen) < 20.0 and _stroke_length_px() < 20.0:
		# Too short to be a drawing: a shaky tap, so treat it as one.
		_battle_tap(world)
		return
	_stroke.append(world)
	if _stroke_kind == "route":
		if _stroke_lead == null or not _stroke_lead.alive():
			return
		if _block_at(world, GameConfig.Side.PLAYER) == _stroke_lead:
			return
		if not selection.has(_stroke_lead):
			selection = [_stroke_lead] as Array[Block]
		var foe := _block_at(world, GameConfig.Side.ENEMY)
		var heading := NAN
		if foe == null:
			var tail := _stroke[maxi(0, _stroke.size() - 6)]
			if tail.distance_to(world) > 1.0:
				heading = (world - tail).angle()
		sim.order_group_route(_live_selection(), _stroke_lead, _walk_stroke(), heading, foe)
		_acknowledge(foe.pos if foe != null else world)
	elif _stroke_kind == "line":
		sim.order_formation(_live_selection(), _stroke)
		_acknowledge(world)

## The route stroke as the lead should walk it: its first points still on the
## lead's body or its hit pad (where the finger or pointer came down, up to a
## finger's width off the block) are dropped, the last point always kept, so a
## press behind or beside the block never turns it round first.
func _walk_stroke() -> PackedVector2Array:
	if _stroke_lead == null or _stroke.is_empty():
		return _stroke
	var pad := _hit_pad()
	var first := 0
	while first < _stroke.size() - 1 and _stroke_lead.distance_to_point(_stroke[first]) <= pad:
		first += 1
	return _stroke.slice(first)

func _clear_stroke() -> void:
	_stroke = PackedVector2Array()
	_stroke_kind = ""
	_stroke_lead = null
	_preview_key = []
	_preview = null

func _stroke_length_px() -> float:
	var total := 0.0
	for i in range(1, _stroke.size()):
		total += _w2s(_stroke[i - 1]).distance_to(_w2s(_stroke[i]))
	return total

func _live_selection() -> Array[Block]:
	var group: Array[Block] = []
	for b in selection:
		if b.alive():
			group.append(b)
	return group

## A tap on the battlefield. Your own block selects it. With something
## selected, an enemy is attacked whichever pointer you use; open ground is a
## move with a finger (there is no right button) and a deselect with a mouse,
## which keeps the right-click RTS convention for orders.
func _battle_tap(world: Vector2) -> void:
	var friend := _block_at(world, GameConfig.Side.PLAYER)
	if friend != null:
		# A finger has no empty-ground deselect that isn't also an order, so
		# tapping a selected block again lets the whole selection go.
		if touch and selection.has(friend):
			selection.clear()
			_refresh_hud()
			return
		selection = [friend] as Array[Block]
		_refresh_hud()
		return
	if not selection.is_empty():
		var foe := _block_at(world, GameConfig.Side.ENEMY)
		if foe != null or touch:
			_issue_at(world)
			return
	selection.clear()
	_refresh_hud()

## An enemy under the point: archers shoot it from range, everyone else
## attacks it (with `melee`, archers charge in too). Open ground: move there.
func _issue_at(world: Vector2, melee := false) -> void:
	var foe := _block_at(world, GameConfig.Side.ENEMY)
	for b in selection:
		if not b.alive():
			continue
		if foe == null:
			sim.order_move(b, world)
		elif melee:
			sim.order_attack(b, foe)
		else:
			sim.order_shoot(b, foe)          # a block with no bow attacks instead
	_acknowledge(foe.pos if foe != null else world)
	_refresh_hud()

## A double click or double tap on an enemy: the whole selection closes and
## fights it hand to hand, archers included. False when there is no enemy
## under the point or nothing selected, so the press is handled as usual.
func _charge_at(screen: Vector2) -> bool:
	if sim == null or selection.is_empty():
		return false
	var world := _s2w(screen)
	if _block_at(world, GameConfig.Side.ENEMY) == null:
		return false
	_cancel_pointer()
	_issue_at(world, true)
	return true

func _acknowledge(world: Vector2) -> void:
	_ack = {"pos": world, "at": _now()}

func _box_select(rect: Rect2) -> void:
	var picked: Array[Block] = []
	for b in sim.blocks:
		if b.alive() and b.side == GameConfig.Side.PLAYER and rect.has_point(_w2s(b.pos)):
			picked.append(b)
	selection = picked

## How far outside a block's body a tap still counts, in world units.
func _hit_pad() -> float:
	return (24.0 if touch else 10.0) / camera.zoom

## The block under a point: anywhere on its body counts, plus a pad around
## it, and the nearest wins when the pads overlap.
func _block_at(world: Vector2, side: int) -> Block:
	if sim == null:
		return null
	var best: Block = null
	var best_d := INF
	var pad := _hit_pad()
	for b in sim.blocks:
		if not b.alive() or b.side != side:
			continue
		if side != GameConfig.Side.PLAYER and not sim.visible_to(b, GameConfig.Side.PLAYER):
			continue
		var d: float = b.distance_to_point(world)
		if d <= pad and d < best_d:
			best_d = d
			best = b
	return best

func _clamp_to_field(world: Vector2, b: Block) -> Vector2:
	var margin := b.size() * 0.5
	var r := Rect2(sim.field.position + margin, sim.field.size - margin * 2.0)
	var p := world.clamp(r.position, r.end)
	return b.pos if sim.terrain.is_blocked(p, b.role) else p

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

func _for_selection(fn: Callable) -> void:
	for b in selection:
		if b.alive():
			fn.call(b)

func _select_all() -> void:
	if sim == null:
		return
	selection = sim.side_blocks(GameConfig.Side.PLAYER, true)
	_refresh_hud()

func _selection_tooltip() -> String:
	var lines: PackedStringArray = []
	var alive: Array[Block] = []
	for b in selection:
		if b.alive():
			alive.append(b)
	if alive.size() == 1:
		var b := alive[0]
		lines.append("%s  %d hp  %d morale · %s · %s" % [
			b.stats()["name"], int(b.health), int(b.morale), _block_state(b),
			terrain.describe(b.pos)["name"],
		])
	elif alive.size() > 1:
		var fighting := 0
		var shaken := 0
		for b in alive:
			if sim.is_engaged(b):
				fighting += 1
			if b.routing:
				shaken += 1
		var text := "%d blocks selected" % alive.size()
		if fighting > 0:
			text += " · %d fighting" % fighting
		if shaken > 0:
			text += " · %d routing" % shaken
		lines.append(text)
	if touch:
		lines.append("Drag from a block to draw its route; drag across the ground to form a line; tap an enemy to attack (archers shoot it), double-tap to charge in.")
	else:
		lines.append("Drag from a block to draw its route, drag on ground to form a line, click an enemy to attack (archers shoot it), double-click to charge in, right-click to move.")
	return "\n".join(lines)

func _block_state(b: Block) -> String:
	if b.routing:
		return "ROUTING"
	if b.reforming():
		return "reforming (%.1fs)" % b.reform_left
	if sim.is_engaged(b):
		var foes: PackedStringArray = []
		var worst := "front"
		for f in sim.contacts_of(b):
			foes.append(f.stats()["name"].to_lower())
			var arc: String = sim.arc_of(b, f.pos)
			if arc == "rear" or (arc == "flank" and worst == "front"):
				worst = arc
		var text := "FIGHTING enemy %s" % ", ".join(foes)
		if worst != "front":
			text += " — hit in the %s!" % worst
		match sim.push_state(b):
			1: text += " — pushing"
			-1: text += " — giving ground"
		return text
	if b.order == Block.OrderType.WITHDRAW:
		return "withdrawing"
	if b.braced:
		return "braced"
	if b.order == Block.OrderType.ATTACK:
		var t := sim.block_by_id(b.target_id)
		return "attacking" if t == null else "attacking enemy %s" % t.stats()["name"].to_lower()
	if b.order == Block.OrderType.SHOOT:
		var t := sim.block_by_id(b.target_id)
		if t == null:
			return "shooting"
		var foe_name: String = t.stats()["name"].to_lower()
		return ("shooting at enemy %s" if sim.in_reach(b, t) else "moving into range of enemy %s") % foe_name
	if b.order == Block.OrderType.MOVE:
		return "moving"
	return "holding"

# ----------------------------------------------------------------------- HUD

func _build_hud() -> void:
	var top := _panel()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
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
	_hud["begin"] = _button("Begin battle", _on_begin)
	controls.add_child(_hud["begin"])
	_hud["pause"] = _button("Pause", _on_pause)
	controls.add_child(_hud["pause"])
	_hud["speed"] = _button("1×", _on_speed)
	controls.add_child(_hud["speed"])
	controls.add_child(_button("Fit", fit))

	var bottom := _panel()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom)
	_hud["bottom"] = bottom
	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 8)
	bottom.add_child(bottom_box)
	_hud["info"] = _label()
	_hud["info"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud["info"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud["info"].custom_minimum_size.y = 40.0
	_hud["info"].max_lines_visible = 2
	bottom_box.add_child(_hud["info"])
	var orders := _flow()
	bottom_box.add_child(orders)
	orders.add_child(_button("Hold", func(): _for_selection(sim.order_hold)))
	orders.add_child(_button("Withdraw", func(): _for_selection(sim.order_withdraw)))
	orders.add_child(_button("Select all", _select_all))
	orders.add_child(_button("Retreat all", func(): sim.retreat_all(GameConfig.Side.PLAYER)))
	_hud["orders"] = orders

	var log_panel := _panel()
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.custom_minimum_size = Vector2(280, 0)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_panel)
	_hud["log"] = _label("", true)
	_hud["log"].add_theme_font_size_override("font_size", 12)
	_hud["log"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(_hud["log"])
	_hud["log_panel"] = log_panel

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
	_hud["result_buttons"] = buttons
	wrap.visible = false
	_hud["result"] = wrap

## Panels sit inside whatever the host's own HUD covers.
func _layout() -> void:
	var cover := _insets()
	var top: PanelContainer = _hud["top"]
	top.offset_left = HUD_MARGIN
	top.offset_right = -HUD_MARGIN
	top.offset_top = cover.x + HUD_MARGIN
	var bottom: PanelContainer = _hud["bottom"]
	bottom.offset_left = HUD_MARGIN
	bottom.offset_right = -HUD_MARGIN
	bottom.offset_top = -(cover.y + HUD_MARGIN)
	bottom.offset_bottom = -(cover.y + HUD_MARGIN)
	var log_panel: PanelContainer = _hud["log_panel"]
	log_panel.offset_right = -HUD_MARGIN
	log_panel.offset_top = cover.x + top.size.y + HUD_MARGIN * 2.0
	_hud["result_panel"].custom_minimum_size.x = minf(460.0, size.x - 24.0)

func _refresh_hud() -> void:
	var live := sim != null
	_hud["begin"].visible = live and not sim.started
	_hud["pause"].visible = live and sim.started and not sim.finished
	_hud["speed"].visible = live and sim.started and not sim.finished
	_hud["orders"].visible = live and sim.started and not sim.finished
	_hud["log_panel"].visible = live and size.x >= WIDE_SCREEN
	_hud["pause"].text = "Resume" if paused else "Pause"
	_hud["speed"].text = "%d×" % int(speed)

func _refresh_status() -> void:
	var status: Label = _hud["status"]
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
		if _time_scale() < 1.0:
			status.text += " · DRAWING — slowed"
	var d := terrain.describe(hover_world)
	_hud["info"].text = _selection_tooltip() if not selection.is_empty() \
		else "%s — %s" % [d["name"], d["effect"]]
	_hud["log"].text = "\n".join(Array(sim.events).slice(maxi(0, sim.events.size() - 8)))

func _on_begin() -> void:
	sim.started = true
	_refresh_hud()

func _on_pause() -> void:
	paused = not paused
	_refresh_hud()

func _on_speed() -> void:
	speed = 1.0 if speed >= 2.0 else 2.0
	_refresh_hud()

func _show_result() -> void:
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
	var buttons: HFlowContainer = _hud["result_buttons"]
	for c in buttons.get_children():
		buttons.remove_child(c)
		c.queue_free()
	for a in result_actions:
		buttons.add_child(_button(str(a["label"]), a["action"]))
	_hud["result"].visible = true
	_refresh_hud()
