class_name MapCamera
extends RefCounted

## A pan-and-zoom view of the world, in logical screen pixels.
##
## Both zooms render through this: the strategic map fits the whole terrain,
## the battle fits its crop, and on a phone the player pinches in from there.
## `screen` is the part of the control the view is fitted into, so the HUD can
## claim the top and bottom without the map hiding behind it.

var centre := Vector2.ZERO
var zoom := 1.0
var screen := Rect2(0, 0, 1, 1)
var bounds := Rect2(0, 0, 1, 1)     # world rect the view may not leave

var _fit_zoom := 1.0
const MAX_ZOOM_IN := 6.0             # relative to the fitted zoom

## Fit `rect` into the screen area and make it the view's boundary.
func fit(rect: Rect2) -> void:
	bounds = rect
	_fit_zoom = minf(screen.size.x / rect.size.x, screen.size.y / rect.size.y)
	zoom = _fit_zoom
	centre = rect.get_center()
	_clamp()

## Re-fit after the screen area changed, keeping whatever the player zoomed to.
func rescreen(new_screen: Rect2) -> void:
	if new_screen == screen:
		return
	var was_fitted := is_equal_approx(zoom, _fit_zoom)
	screen = new_screen
	_fit_zoom = minf(screen.size.x / bounds.size.x, screen.size.y / bounds.size.y)
	if was_fitted:
		zoom = _fit_zoom
	_clamp()

func transform() -> Transform2D:
	return Transform2D(0.0, Vector2(zoom, zoom), 0.0, screen.get_center() - centre * zoom)

func w2s(p: Vector2) -> Vector2:
	return transform() * p

func s2w(p: Vector2) -> Vector2:
	return transform().affine_inverse() * p

## Zoom by `factor` about a screen point, so what is under the finger stays put.
func zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := s2w(screen_point)
	zoom = clampf(zoom * factor, _fit_zoom, _fit_zoom * MAX_ZOOM_IN)
	var after := s2w(screen_point)
	centre += before - after
	_clamp()

func pan(screen_delta: Vector2) -> void:
	centre -= screen_delta / zoom
	_clamp()

func is_fitted() -> bool:
	return is_equal_approx(zoom, _fit_zoom)

## Keep the boundary on screen: centred while it is smaller than the view,
## otherwise the view may not slide past its edge.
func _clamp() -> void:
	var half := screen.size / zoom * 0.5
	for axis in 2:
		if bounds.size[axis] <= half[axis] * 2.0:
			centre[axis] = bounds.position[axis] + bounds.size[axis] * 0.5
		else:
			centre[axis] = clampf(centre[axis],
				bounds.position[axis] + half[axis], bounds.end[axis] - half[axis])
