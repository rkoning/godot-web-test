class_name StacksLayer
extends MapLayer

## Armies on the map: one disc per stack, the orders a player gives them, and
## the supply breakdown behind each one.
##
## No rule lives here. Every order goes through `Orders` — the one door the UI,
## the scripted enemies and the planner all use — and every number in the
## tooltip is read back off the report `SupplyPhase` wrote. This layer decides
## what a click means and what a hover says, nothing else.

const DISC := 12.0                  # marker radius, screen pixels

## The detach panel, built once and handed to `CampaignRoot` on every rebuild:
## the contract asks for the same instance each call, and a fresh `Control` per
## call would leak a node per rebuild.
var _panel: VBoxContainer = null
var _count: SpinBox = null

## Armed by the Detach button: the next site click splits the stack instead of
## marching it. It never survives a change of selection — see `pressed` and
## `draw`, which both disarm it — so a click armed for one army can never fire
## on another.
var _detaching := false

## The top of the stack, and it stays there: armies are what the player clicks,
## so no overlay may draw over them or take a click before them.
func order() -> int:
	return 100

## The selected stack, when it is one of the player's and still in the world.
## Everything on this layer that writes state goes through it, so a stack that
## was merged away or destroyed by a phase cannot be ordered about.
func _player_stack() -> Stack:
	var s := view.selected
	if s == null or view.world == null or view.world.player() == null:
		return null
	if s.nation_id != view.world.player().id or not view.world.stacks.has(s):
		return null
	return s

func _detach_count() -> int:
	return int(_count.value) if _count != null else 3

## Buttons are built once, so the label carries the count the panel started
## with; the panel is the live control, and the count it reads at click time is
## the one that is used.
func buttons() -> Array[Dictionary]:
	var has := func() -> bool:
		return _player_stack() != null
	var has_order := func() -> bool:
		var s := _player_stack()
		return s != null and (not s.path.is_empty() or s.order == "hold")
	var can_build := func() -> bool:
		var s := _player_stack()
		if s == null:
			return false
		return Orders.can_build_depot(view.world, view.world.player(),
			view.world.graph.site(s.site_id)) == ""
	var can_detach := func() -> bool:
		var s := _player_stack()
		return s != null and s.size() > 1
	var hold := func() -> void:
		var s := _player_stack()
		if s != null:
			Orders.hold(view.world, s)
	var arm_detach := func() -> void:
		_detaching = not _detaching
	var build := func() -> void:
		var s := _player_stack()
		if s != null:
			Orders.build_depot(view.world, view.world.player(), view.world.graph.site(s.site_id))
	var clear := func() -> void:
		var s := _player_stack()
		if s != null:
			Orders.clear(view.world, s)
			_detaching = false
	return [
		{"label": "Hold", "action": hold, "enabled": has},
		{"label": "Detach %d" % _detach_count(), "action": arm_detach, "enabled": can_detach},
		{"label": "Build depot", "action": build, "enabled": can_build},
		{"label": "Clear order", "action": clear, "enabled": has_order},
	]

## How many regiments a Detach splits off. A spinner rather than a fixed number:
## a screening detachment and a garrison are the same order with a different
## count, and the player picks it before arming the click.
func panel() -> Control:
	if _panel == null:
		_panel = VBoxContainer.new()
		var title := Label.new()
		title.text = "Detach: regiments to split off"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel.add_child(title)
		_count = SpinBox.new()
		_count.min_value = 1
		_count.max_value = 15
		_count.value = 3
		_count.custom_minimum_size = Vector2(110, 44)
		# The column stretches its children; a spinner as wide as the panel puts
		# its arrows an inch from its digits.
		_count.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_panel.add_child(_count)
	return _panel

# -------------------------------------------------------------------- drawing

func draw(canvas: CanvasItem) -> void:
	if view.world == null:
		return
	# The shell clears the selection when a phase eats the selected stack, so
	# an armed detach is disarmed here rather than waiting for a click that
	# would then fire on whatever was selected next.
	if _player_stack() == null:
		_detaching = false
	for s in view.world.stacks:
		_draw_path(canvas, s)
	for s in view.world.stacks:
		_draw_stack(canvas, s)

func _draw_stack(canvas: CanvasItem, s: Stack) -> void:
	var at := view.w2s(view.stack_pos(s))
	var col := view.world.nation(s.nation_id).color
	canvas.draw_circle(at, DISC, col.darkened(0.35))
	canvas.draw_arc(at, DISC, 0.0, TAU, 24, col.lightened(0.35), 2.0)
	if view.selected == s:
		canvas.draw_arc(at, DISC + 5.0, 0.0, TAU, 28, ThemeColors.TEXT, 1.5)
	canvas.draw_string(view.font, at + Vector2(DISC + 5.0, 4.0),
		"%d rgt · %d%%" % [s.size(), int(round(s.supply))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lightened(0.5))

## The pending route: dashed, because it has not happened yet.
func _draw_path(canvas: CanvasItem, s: Stack) -> void:
	if s.path.is_empty():
		return
	var col := view.world.nation(s.nation_id).color * Color(1, 1, 1, 0.8)
	var from := view.w2s(view.stack_pos(s))
	for sid in s.path:
		var to := view.w2s(view.world.graph.site(sid).pos)
		MapLayer.dashes(canvas, from, to, col, 2.5, 12.0, 0.5)
		canvas.draw_arc(to, 5.0, 0.0, TAU, 16, col, 1.5)
		from = to

# ---------------------------------------------------------------------- input

## A click on a stack selects it. A click on a site with one of your own stacks
## selected sends it there — anywhere `Pathing` can reach, not only next door,
## because a campaign order is a destination and the route is the rules' job.
## With Detach armed the same click splits the stack instead, once.
##
## An enemy stack is the exception: armies sit on sites, so an enemy disc covers
## the site a player would have to click to attack it. With one of your own
## armies selected, clicking an enemy is that attack order — the ordinary move to
## the site it stands on, which `Movement` stops on arrival and WS-C resolves.
func pressed(world_pos: Vector2) -> bool:
	if view.world == null:
		return false
	var hit := view.stack_at(world_pos)
	if hit != null:
		var attacker := _player_stack()
		if attacker != null and view.world.hostile(hit.nation_id, attacker.nation_id):
			_detaching = false
			return Orders.move(view.world, attacker, hit.site_id)
		# Clicking the selected stack again deselects it. Either way the
		# selection changed, so an armed detach is dropped rather than carried
		# over to an army it was never aimed at.
		view.selected = null if view.selected == hit else hit
		_detaching = false
		return true

	var s := _player_stack()
	if s == null:
		return false
	var site := view.site_at(world_pos)
	if site == null:
		return false
	if _detaching:
		var split := Orders.detach(view.world, s, mini(_detach_count(), s.size() - 1), site.id, true)
		if split == null:
			# A refused split must not cost the player the arming: `Orders`
			# turned the click down, so the button is still armed and the next
			# site click is the one that detaches.
			return false
		_detaching = false
		return true
	if site.id == s.site_id:
		return false
	return Orders.move(view.world, s, site.id)

# ------------------------------------------------------------------- tooltips

## The breakdown in two lines a player can read at a glance: who this is, and
## where its food came from this turn. Before the first turn resolves there is
## no report, and it says so rather than showing an empty ledger.
func tooltip(world_pos: Vector2) -> String:
	if view.world == null:
		return ""
	var s := view.stack_at(world_pos)
	if s == null:
		return ""
	var lines: PackedStringArray = ["%s — %s%s" % [s.label, _roster(s), _destination(s)]]
	var r := s.supply_report
	if r.is_empty():
		lines.append("Supply %d%% · no turn yet" % int(round(s.supply)))
		return "\n".join(lines)
	var delta := float(r["delta"])
	var line := "Supply %d%% %s %+.1f · upkeep %d · land %d" % [
		int(round(s.supply)), "▲" if delta >= 0.0 else "▼", delta,
		int(round(r["upkeep"])), int(round(r["local"]))]
	if int(r["depot_id"]) >= 0:
		line += " · depot %d (%d hops from %s)" % [
			int(round(r["delivered"])), int(r["hops"]),
			view.world.graph.site(int(r["depot_id"])).name]
	else:
		line += " · no depot in reach"
	if float(r["shortfall"]) > 0.0:
		line += " · short %d" % int(round(r["shortfall"]))
	lines.append(line)
	if r["foraging"]:
		lines.append("Foraging %s — it is being pillaged"
			% view.world.graph.site(s.site_id).name)
	return "\n".join(lines)

func _roster(s: Stack) -> String:
	var counts := {}
	for r in s.regiments:
		counts[r] = int(counts.get(r, 0)) + 1
	var parts: PackedStringArray = []
	for role in GameConfig.Role.values():
		if counts.has(role):
			parts.append("%d %s" % [counts[role], str(GameConfig.unit(role)["name"]).to_lower()])
	return ", ".join(parts) if parts.size() > 0 else "empty"

func _destination(s: Stack) -> String:
	if s.path.is_empty():
		return ""
	return " · ordered to %s" % view.world.graph.site(s.path[s.path.size() - 1]).name
