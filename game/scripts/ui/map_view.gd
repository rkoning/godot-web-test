class_name MapView
extends Control

## The campaign map: a camera over the `World`, the terrain underneath it, and
## a stack of `MapLayer`s that draw everything else.
##
## Presentation and input only — the rules are in scripts/sim. The view owns
## the things every layer needs (camera, world, hover point, selection) and
## nothing a layer could own itself.
##
## Input, mouse only for now (touch parity is a later phase):
##   left click                 asked to each layer top-down, first to consume wins
##   wheel                      zoom about the cursor
##   right / middle drag        pan

const ZOOM_STEP := 1.15
const DRAG_THRESHOLD_PX := 10.0

var world: World
var terrain: Terrain
var camera := MapCamera.new()
var selected: Stack = null
var layers: Array[MapLayer] = []

## Where the pointer last was, in world units. `Vector2.INF` means "nowhere":
## before the first mouse motion there is no hover, and (0, 0) is a real corner
## of the map, so it cannot stand in for one.
var hover_world := Vector2.INF
var font: Font

## The HUD claims the top and bottom of the control; the map is fitted into
## what is left. `CampaignRoot` keeps these up to date.
var inset_top := 0.0
var inset_bottom := 0.0

var _terrain_texture: ImageTexture
var _press_screen := Vector2.INF
var _press_moved := false
var _pan_button := -1
var _pan_moved := false

func _ready() -> void:
	font = ThemeDB.fallback_font
	# Anchors *and* offsets: `set_anchors_preset` alone keeps the rect the
	# control already has, which for a node built in code is zero by zero.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if terrain == null:
		terrain = Terrain.new()
	_terrain_texture = _build_terrain_texture()
	fit()

func _process(_delta: float) -> void:
	# The HUD reflows as text wraps, so the map area is re-read every frame
	# rather than only on resize.
	camera.rescreen(map_area())
	queue_redraw()

## Register the layers, in draw order: first drawn is furthest back.
func set_layers(list: Array[MapLayer]) -> void:
	layers = list
	for layer in layers:
		layer.view = self

## The part of the control the map is fitted into: everything the HUD leaves.
func map_area() -> Rect2:
	var top := inset_top
	var bottom: float = maxf(size.y - inset_bottom, top + 1.0)
	return Rect2(0.0, top, maxf(size.x, 1.0), bottom - top)

## The terrain's extent is read off the instance, not the class: WS-J turns
## `COLS`/`ROWS`/`SIZE` into instance members of a `Terrain` loaded from data
## files, and every read here has to keep working when it does.
func fit() -> void:
	if terrain == null:
		terrain = Terrain.new()
	camera.screen = map_area()
	camera.fit(Rect2(Vector2.ZERO, terrain.SIZE))

func w2s(p: Vector2) -> Vector2:
	return camera.w2s(p)

func s2w(p: Vector2) -> Vector2:
	return camera.s2w(p)

# ------------------------------------------------------------------- picking

## Hit radii are in screen pixels, so a site stays as easy to click zoomed out
## as zoomed in — the glyphs are drawn at a fixed screen size too.
##
## The zoom is clamped well outside anything the camera reaches in play
## (roughly 0.3–5 for this terrain on any screen). Before the first layout pass
## the camera has been fitted into a one-pixel rect, and an unclamped division
## there would make the pick radius thousands of world units wide — every click
## would land on something.
func _world_radius(screen_radius: float) -> float:
	return screen_radius / clampf(camera.zoom, 0.2, 8.0)

## The site nearest a world point within `radius` screen pixels, or null.
## `Vector2.INF` (no hover yet) picks nothing rather than everything.
func site_at(world_pos: Vector2, radius := 18.0) -> Site:
	if world == null or not world_pos.is_finite():
		return null
	var limit := _world_radius(radius)
	var best: Site = null
	var best_d := INF
	for s in world.graph.sites:
		var d: float = s.pos.distance_to(world_pos)
		if d <= limit and d < best_d:
			best_d = d
			best = s
	return best

## The stack nearest a world point within `radius` screen pixels, or null.
func stack_at(world_pos: Vector2, radius := 24.0) -> Stack:
	if world == null or not world_pos.is_finite():
		return null
	var limit := _world_radius(radius)
	var best: Stack = null
	var best_d := INF
	for s in world.stacks:
		var d: float = stack_pos(s).distance_to(world_pos)
		if d <= limit and d < best_d:
			best_d = d
			best = s
	return best

## Where a stack's marker sits: its site, lifted clear of any stack sharing it.
## Drawing and picking both go through this so they cannot disagree.
func stack_pos(s: Stack) -> Vector2:
	if world == null or s.site_id < 0:
		return Vector2.ZERO
	var at: Vector2 = world.graph.site(s.site_id).pos
	var index := 0
	for other in world.stacks_at(s.site_id):
		if other == s:
			break
		index += 1
	return at + Vector2(0.0, -18.0 * float(index))

# ------------------------------------------------------------------- tooltips

## The hover text for a world point: the top layer that has something to say.
func tooltip_at(world_pos: Vector2) -> String:
	for i in range(layers.size() - 1, -1, -1):
		var text: String = layers[i].tooltip(world_pos)
		if text != "":
			return text
	return ""

# -------------------------------------------------------------------- drawing

## The terrain is rasterised once into a texture, the same way the combat
## prototype does it, so the campaign map and a battle show one dataset.
func _build_terrain_texture() -> ImageTexture:
	var w := terrain.COLS * 4
	var h := terrain.ROWS * 4
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var at := Vector2(
				(float(x) + 0.5) / float(w) * terrain.SIZE.x,
				(float(y) + 0.5) / float(h) * terrain.SIZE.y,
			)
			var base := ThemeColors.biome(terrain.biome_at(at))
			# Height lifts the ground a little, and banding every other step
			# gives hills readable contours instead of a wash.
			var steps: float = terrain.height_at(at) / terrain.HEIGHT_STEP
			var lift: float = clampf(steps / 9.0, 0.0, 1.0)
			var band: float = 0.025 if int(steps) % 2 == 1 else 0.0
			img.set_pixel(x, y, base.lightened(lift * 0.13 + band))
	return ImageTexture.create_from_image(img)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.BACKGROUND, true)
	if _terrain_texture != null:
		draw_texture_rect(_terrain_texture,
			Rect2(w2s(Vector2.ZERO), terrain.SIZE * camera.zoom), false)
	for layer in layers:
		layer.draw(self)

# ---------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera.zoom_at(event.position, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera.zoom_at(event.position, 1.0 / ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_screen = event.position
				_press_moved = false
			else:
				_pointer_up(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_button_event(event)
		return

	if event is InputEventMouseMotion:
		hover_world = s2w(event.position)
		if _pan_button != -1:
			if not _pan_moved and event.position.distance_to(_press_screen) < DRAG_THRESHOLD_PX:
				return
			_pan_moved = true
			camera.pan(event.relative)
			return
		if _press_screen != Vector2.INF \
				and event.position.distance_to(_press_screen) >= DRAG_THRESHOLD_PX:
			_press_moved = true

func _pan_button_event(event: InputEventMouseButton) -> void:
	if event.pressed:
		_pan_button = event.button_index
		_pan_moved = false
		_press_screen = event.position
		return
	_pan_button = -1
	_press_screen = Vector2.INF

## A click that did not turn into a drag goes to the layers, top one first.
func _pointer_up(screen: Vector2) -> void:
	var tapped := _press_screen != Vector2.INF and not _press_moved
	_press_screen = Vector2.INF
	_press_moved = false
	if not tapped:
		return
	var at := s2w(screen)
	hover_world = at
	for i in range(layers.size() - 1, -1, -1):
		if layers[i].pressed(at):
			return
