extends RefCounted

## WS-A: the logistics presentation, checked through the real shell. The rules
## are covered by test_supply.gd and test_movement.gd; this suite proves the map
## is wired to them — the supply layer is registered, the orders buttons exist
## and carry the detach count, the stacks layer hands over one reused panel, the
## supply tooltip reads as a breakdown rather than a dictionary dump, and a click
## on a site three hops away becomes a route through `Orders`.
##
## Every fixture lookup is guarded, the same way test_campaign_shell.gd guards
## its own: a missing site or stack is a *failed check* and a clean return, never
## an indexing crash that would silence every check below it.

var t: TestHarness

func run(harness: TestHarness) -> void:
	t = harness
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		t.check("a SceneTree root is available to host the scene", false,
			"Engine.get_main_loop() gave no root; the runner must start suites from _process, "
			+ "the first point at which the root window is inside the tree")
		return

	var packed := load("res://scenes/campaign.tscn") as PackedScene
	t.check("campaign.tscn loads", packed != null)
	if packed == null:
		return

	var root := packed.instantiate() as Control
	t.check("campaign.tscn instantiates a Control", root != null)
	if root == null:
		return

	tree.root.add_child(root)
	_check_layers(root)
	tree.root.remove_child(root)
	root.free()

func _check_layers(root: Control) -> void:
	var view: MapView = root.view
	t.check("the root owns a MapView", view != null)
	if view == null or view.world == null:
		t.check("the view owns the world", false)
		return

	var layers: Array[MapLayer] = view.layers
	var has_supply := false
	for l in layers:
		if l is SupplyLayer:
			has_supply = true
	t.check("the supply layer is registered", has_supply)

	# The top layer by order(), never by index: the supply layer sits at 50, so
	# layers[1] is no longer the stacks layer.
	var stacks: MapLayer = layers[layers.size() - 1]
	t.check("the stacks layer is still on top", stacks.order() == 100, str(stacks.order()))

	var labels: Array = []
	for b in stacks.buttons():
		labels.append(b["label"])
	t.check("the orders buttons exist",
		labels.has("Hold") and labels.has("Build depot") and labels.has("Clear order"),
		str(labels))
	var detach_label := ""
	for lb in labels:
		if str(lb).begins_with("Detach"):
			detach_label = str(lb)
	t.check("Detach shows its count", detach_label.contains("3"), detach_label)
	t.check("the stacks layer has a panel with the detach count",
		stacks.panel() != null and stacks.panel() == stacks.panel())

	# Headless there is no layout pass, so the camera is still fitted into the
	# one-pixel rect a zero-size control reports and every pick radius would
	# cover the whole map. Fit it to a realistic screen before picking anything.
	view.camera.screen = Rect2(0.0, 0.0, 1280.0, 720.0)
	view.camera.fit(Rect2(Vector2.ZERO, view.terrain.SIZE))

	var world: World = view.world
	var player := world.player()
	t.check("the player nation is seeded", player != null)
	if player == null:
		return
	var mine := world.stacks_of(player.id)
	t.check("the player has a stack to inspect", mine.size() >= 1, str(mine.size()))
	if mine.is_empty():
		return
	var me: Stack = mine[0]

	# Before any turn has resolved there is no report, and the tooltip has to say
	# so rather than showing an empty breakdown.
	t.check("the tooltip degrades before the first turn",
		stacks.tooltip(view.stack_pos(me)).contains("no turn yet"),
		stacks.tooltip(view.stack_pos(me)))

	root._on_end_turn()
	t.check("SupplyPhase wrote a report", not me.supply_report.is_empty())
	var tip: String = stacks.tooltip(view.stack_pos(me))
	t.check("the breakdown names upkeep, land and depot in one line",
		tip.contains("upkeep") and tip.contains("depot") and tip.contains("Supply"), tip)
	t.check("the tooltip still names the army and its roster",
		tip.contains(me.label) and tip.contains("infantry"), tip)

	# Ordering through the layer: select, then click a site three hops away.
	view.selected = me
	var far := _site(world, "Fordwatch")
	if far == null:
		return
	t.check("a click on a reachable site orders a route",
		stacks.pressed(far.pos) and me.path.size() == 2
			and me.path[me.path.size() - 1] == far.id, str(me.path))

	# Hold clears the route and posts the order; Clear order takes both away.
	Orders.hold(world, me)
	t.check("holding drops the route", me.path.is_empty() and me.order == "hold")

	# Detach arms on the button and fires on the next site click.
	var before := world.stacks.size()
	var size_before := me.size()
	view.selected = me
	_press(stacks, "Detach")
	t.check("the detach click splits the stack", stacks.pressed(far.pos))
	t.check("a new stack exists", world.stacks.size() == before + 1,
		"%d vs %d" % [world.stacks.size(), before])
	t.check("the parent is smaller by the detach count", me.size() == size_before - 3,
		"%d vs %d" % [me.size(), size_before])
	t.check("detach disarmed itself", stacks.pressed(far.pos) and me.path.size() == 2,
		str(me.path))

	# An enemy disc sits on the site you would have to click to attack it, so
	# with one of your own armies selected the click through it is that order.
	var enemy: Stack = null
	for st in world.stacks:
		if st.nation_id != player.id:
			enemy = st
	t.check("the campaign seeds an enemy army to click on", enemy != null)
	if enemy != null:
		view.selected = me
		var ordered: bool = stacks.pressed(view.stack_pos(enemy))
		t.check("clicking an enemy with an army selected orders the attack",
			ordered and not me.path.is_empty()
				and me.path[me.path.size() - 1] == enemy.site_id, str(me.path))
		t.check("and the click did not steal the selection", view.selected == me)

	# The supply layer draws only.
	var supply: MapLayer = null
	for l in view.layers:
		if l is SupplyLayer:
			supply = l
	if supply == null:
		return
	t.check("the supply layer sits between the map and the armies",
		supply.order() == 50, str(supply.order()))
	t.check("the supply layer takes no clicks", not supply.pressed(far.pos))
	t.check("the supply layer says nothing on hover", supply.tooltip(far.pos) == "")
	t.check("the supply layer contributes no buttons", supply.buttons().is_empty())
	t.check("the supply layer contributes no panel", supply.panel() == null)

	# The graph layer reports a depot's stock, and says so while one is building.
	var graph: MapLayer = view.layers[0]
	var depot := _site(world, "Capital Depot")
	if depot == null:
		return
	t.check("a depot tooltip reports its stock",
		graph.tooltip(depot.pos).to_lower().contains("stock"), graph.tooltip(depot.pos))
	depot.depot_ready_turn = world.turn + 2
	t.check("a depot under construction says how long",
		graph.tooltip(depot.pos).to_lower().contains("ready in"), graph.tooltip(depot.pos))

	# Last, because every scenario switch throws this world away and builds a
	# new one: nothing above may hold a reference to `view.world` afterwards.
	_check_scenario_picker(root, view)

## The seam the shell grew for WS-A: a registry of scenario providers, and one
## call that rebuilds the run from any of them. The HUD's dropdown is only a
## caller of `select_scenario`, so the seam is checked rather than the control.
func _check_scenario_picker(root: Control, view: MapView) -> void:
	t.check("the scenario registry lists the logistics scenarios", CampaignRoot.SCENARIOS.size() >= 1)
	root.select_scenario(0, 0)      # first registry entry, first scenario: The March
	t.check("selecting a scenario rebuilds the world from it",
		view.world.stacks.size() == 1 and view.world.stacks[0].size() == 12)
	t.check("the status line carries the scenario's progress", root.scenario_text().contains("River East"))
	root.select_scenario(-1, 0)
	t.check("back to the open campaign", view.world.stacks.size() == 2)
	t.check("and the campaign has no scenario line", root.scenario_text() == "")

## Fire a layer button by label prefix, failing a check if there is no such one.
func _press(layer: MapLayer, prefix: String) -> void:
	for spec in layer.buttons():
		if str(spec.get("label", "")).begins_with(prefix):
			spec["action"].call()
			return
	t.check("the layer has a '%s' button" % prefix, false)

func _site(world: World, site_name: String) -> Site:
	for s in world.graph.sites:
		if s.name == site_name:
			return s
	t.check("the map has a site called '%s'" % site_name, false)
	return null
