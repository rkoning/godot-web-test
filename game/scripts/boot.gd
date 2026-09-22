extends Control

## The menu the build opens on: the combat prototype, or the campaign.
##
## Two playable scenes now share one export, and the export is the deliverable,
## so the choice has to be in the build rather than in `project.godot`. On the
## web `?scene=combat` or `?scene=campaign` skips this menu, which is what the
## CI preview links and a bookmark use.

const COMBAT_SCENE := "res://scenes/game.tscn"
const CAMPAIGN_SCENE := "res://scenes/campaign.tscn"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var wanted := _wanted_scene()
	if wanted != "":
		# Deferred: changing scenes from inside _ready frees the node we are in.
		get_tree().change_scene_to_file.call_deferred(wanted)
		return
	_build_menu()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), ThemeColors.BACKGROUND, true)

## `?scene=combat|campaign` in a browser, otherwise nothing: the menu shows.
func _wanted_scene() -> String:
	if not OS.has_feature("web"):
		return ""
	match _query_param("scene"):
		"combat": return COMBAT_SCENE
		"campaign": return CAMPAIGN_SCENE
	return ""

## A copy of NetConfig._query_param rather than a call to it: the menu must not
## drag the multiplayer demo's config into the campaign build's dependencies.
static func _query_param(key: String) -> String:
	var search: String = str(JavaScriptBridge.eval("window.location.search", true))
	if search.is_empty() or search == "<null>":
		return ""
	for pair in search.trim_prefix("?").split("&", false):
		var bits := pair.split("=", true, 1)
		if bits.size() == 2 and bits[0] == key:
			return bits[1].uri_decode()
	return ""

# ----------------------------------------------------------------------- menu

func _build_menu() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 260.0
	centre.add_child(box)

	var title := Label.new()
	title.text = "Logistics Roguelike"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", ThemeColors.TEXT)
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	box.add_child(_button("Combat prototype", COMBAT_SCENE))
	box.add_child(_button("Campaign", CAMPAIGN_SCENE))

func _button(text: String, path: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(240, 44)
	b.pressed.connect(func(): get_tree().change_scene_to_file(path))
	return b
