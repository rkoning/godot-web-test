extends RefCounted

## Phase 0: the campaign shell. A smoke test, not a rules test — the rules are
## covered by test_world.gd. This one proves the presentation layer holds
## together: the scene instantiates headlessly, the layer registry produces the
## layers `CampaignRoot.LAYERS` lists in `order()` order, the seeded world is
## the one the map data describes, picking finds a site, a layer answers a
## hover, the battle-view overlay seam works, and End Turn drives TurnResolver
## rather than doing anything itself.
##
## Every fixture lookup is guarded. A missing site or stack is a *failed check*
## and a clean return, never an indexing crash: a suite that dies on line 40
## reports nothing about the other forty things it was going to check.

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
	t.check("boot.tscn loads", load("res://scenes/boot.tscn") != null)
	if packed == null:
		return

	var root := packed.instantiate() as Control
	t.check("campaign.tscn instantiates a Control", root != null)
	if root == null:
		return

	tree.root.add_child(root)
	_check_shell(root)
	tree.root.remove_child(root)
	root.free()

func _check_shell(root: Control) -> void:
	var view: MapView = root.view
	t.check("the root owns a MapView", view != null)
	if view == null:
		return
	t.check("the view owns the world", view.world != null)
	if view.world == null:
		return
	t.check("the world starts on turn 1", view.world.turn == 1, str(view.world.turn))
	t.check("every layer in LAYERS is registered",
		view.layers.size() == CampaignRoot.LAYERS.size(), str(view.layers.size()))
	# `>= 2`, never `== 2`. This file is a shared Phase 0 file, so the first
	# workstream to register its own layer must not have to edit it — and must
	# not silently skip the forty checks below by tripping an early return.
	t.check("at least the two foundation layers are registered",
		view.layers.size() >= 2, str(view.layers.size()))
	if view.layers.size() < 2:
		return
	for layer in view.layers:
		t.check("layer knows its view", layer.view == view)

	# The stack is ordered by each layer's own order(), not by its position in
	# LAYERS, so a workstream can append its layer anywhere in that array.
	var orders: Array[int] = []
	for layer in view.layers:
		orders.append(layer.order())
	var ascending := orders.duplicate()
	ascending.sort()
	t.check("layers are stacked by order()", orders == ascending, str(orders))
	t.check("the stacks layer is on top and claims 100",
		view.layers[view.layers.size() - 1].order() == 100, str(orders))
	t.check("no layer contributes a side panel yet",
		view.layers.all(func(l): return l.panel() == null))

	var world: World = view.world
	var player := world.player()
	t.check("the player nation is seeded", player != null)
	if player == null:
		return

	var mine := world.stacks_of(player.id)
	t.check("one player stack", mine.size() == 1, str(mine.size()))
	var enemy := world.stacks.filter(func(s): return s.nation_id != player.id)
	t.check("one enemy stack", enemy.size() == 1, str(enemy.size()))
	if mine.size() != 1 or enemy.size() != 1:
		return
	t.check("the player stack is 12 regiments", mine[0].size() == 12, str(mine[0].size()))
	t.check("the enemy stack is 6 regiments", enemy[0].size() == 6, str(enemy[0].size()))

	var home := _site_named(world, "Capital Depot")
	var camp := _site_named(world, "Warcamp Depot")
	t.check("the map has both depot sites", home != null and camp != null)
	if home == null or camp == null:
		return
	t.check("the player stack stands on the Capital Depot", mine[0].site_id == home.id)
	t.check("the enemy stack stands on the Warcamp Depot", enemy[0].site_id == camp.id)

	# The shell seeds nothing itself: a world built straight from the map data
	# has the same two armies. If this drifts, the shell has grown a scenario.
	_check_seed_comes_from_map_data(world, player.id)

	# Headless there is no layout pass, so the camera stays fitted into the
	# one-pixel rect `map_area()` reports for a zero-size control, and every
	# pick radius would then cover the whole map. Fit it to a realistic screen
	# so picking is exercised at a real zoom. The camera is driven directly
	# rather than through `view.size`: assigning the size of a control with
	# non-equal opposite anchors warns, because a layout pass would override it.
	view.camera.screen = Rect2(0.0, 0.0, 1280.0, 720.0)
	view.camera.fit(Rect2(Vector2.ZERO, view.terrain.SIZE))
	t.check("the camera fits the terrain into the view",
		view.camera.zoom > 0.5 and view.camera.zoom < 2.0, str(view.camera.zoom))

	# Picking and hover, the two queries every layer is built on.
	t.check("site_at finds a site at its own position", view.site_at(home.pos) == home)
	t.check("stack_at finds the stack on that site", view.stack_at(view.stack_pos(mine[0])) == mine[0])
	t.check("nothing is hovered before the pointer has moved", view.hover_world == Vector2.INF)
	t.check("site_at picks nothing for a non-finite point", view.site_at(Vector2.INF) == null)
	t.check("stack_at picks nothing for a non-finite point", view.stack_at(Vector2.INF) == null)
	var graph: MapLayer = view.layers[0]
	t.check("the graph layer describes a site on hover", graph.tooltip(home.pos) != "",
		graph.tooltip(home.pos))
	t.check("the graph layer says nothing about empty ground",
		graph.tooltip(Vector2(-4000.0, -4000.0)) == "")
	t.check("the view asks the layers for a tooltip", view.tooltip_at(home.pos) != "")

	# Every layer button is callable and reports its own enabled state.
	# `enabled` is optional in the contract and defaults to always-enabled, the
	# same default `CampaignRoot` applies, so it is only type-checked when the
	# layer actually supplied one — a layer that omits it is well formed.
	for layer in view.layers:
		for spec in layer.buttons():
			var label := str(spec.get("label", "?"))
			t.check("button '%s' has an action" % label, spec.get("action") is Callable)
			if spec.has("enabled"):
				t.check("button '%s' enabled is a Callable" % label, spec["enabled"] is Callable)
			var enabled: Callable = spec.get("enabled", func() -> bool: return true)
			t.check("button '%s' answers enabled()" % label,
				typeof(enabled.call()) == TYPE_BOOL)

	# StacksLayer.pressed is the one place the UI writes simulation state, so
	# it is checked both ways: an adjacent site becomes the order, a
	# non-adjacent one is refused and leaves the existing order alone.
	# The top layer by `order()`, not index 1: once a workstream registers a
	# layer in the 10–90 band, `layers[1]` is that layer and this test would
	# drive the wrong object. `StacksLayer` is the one that claims 100.
	var stacks: MapLayer = view.layers[view.layers.size() - 1]
	view.selected = null
	t.check("clicking a stack selects it", stacks.pressed(view.stack_pos(mine[0])))
	t.check("the clicked stack is the selection", view.selected == mine[0])

	var adjacent := world.graph.neighbors(mine[0].site_id)
	t.check("the player's site has a neighbour to be ordered to", not adjacent.is_empty())
	var far := _unconnected_site(world, mine[0].site_id)
	t.check("the map has a site no edge joins to the player's", far != null)
	if adjacent.is_empty() or far == null:
		return
	var near := world.graph.site(adjacent[0])
	t.check("clicking an adjacent site is consumed as an order", stacks.pressed(near.pos))
	t.check("the order is that site", mine[0].path == ([near.id] as Array[int]), str(mine[0].path))
	t.check("clicking a non-adjacent site is not an order", not stacks.pressed(far.pos))
	t.check("the refused click left the order alone",
		mine[0].path == ([near.id] as Array[int]), str(mine[0].path))
	t.check("the stack is still selected after a refused click", view.selected == mine[0])

	# The battle-view seam: WS-C swaps the map out for its own full-rect view
	# and puts it back, without CampaignRoot knowing what a battle is.
	var overlay := Control.new()
	root.set_overlay(overlay)
	t.check("set_overlay hides the map", not view.visible)
	t.check("set_overlay hosts the control", overlay.get_parent() == root)
	root.clear_overlay()
	t.check("clear_overlay shows the map again", view.visible)
	t.check("clear_overlay hands the control back", overlay.get_parent() == null)
	root.clear_overlay()
	t.check("clear_overlay is safe with no overlay showing", view.visible)
	overlay.free()

	# End Turn is the resolver, not a local increment.
	root._on_end_turn()
	t.check("End Turn advances the turn", world.turn == 2, str(world.turn))
	root._on_end_turn()
	t.check("End Turn keeps advancing", world.turn == 3, str(world.turn))

	# Reset rebuilds the world from the same seed.
	root._on_reset()
	t.check("Reset returns to turn 1", view.world.turn == 1)
	t.check("Reset re-seeds both stacks", view.world.stacks.size() == 2)

## The shell's world and a world built directly from `PrototypeMap.data()` must
## agree: same nations, same sites, same rosters. The starting armies are map
## data, and this is the check that keeps them there.
func _check_seed_comes_from_map_data(shell: World, player_id: int) -> void:
	var direct := World.from_map(PrototypeMap.data(), CampaignRoot.SEED)
	t.check("a world built straight from map data has the same two stacks",
		direct.stacks.size() == shell.stacks.size(),
		"%d vs %d" % [direct.stacks.size(), shell.stacks.size()])
	if direct.stacks.size() != shell.stacks.size():
		return
	var mismatches: PackedStringArray = []
	for i in shell.stacks.size():
		var a: Stack = shell.stacks[i]
		var b: Stack = direct.stacks[i]
		if a.nation_id != b.nation_id or a.site_id != b.site_id or a.regiments != b.regiments:
			mismatches.append("stack %d" % i)
	t.check("every seeded stack matches the map's own", mismatches.is_empty(),
		", ".join(mismatches))
	t.check("the map data names the player's army",
		direct.stacks_of(player_id).size() == 1, str(direct.stacks_of(player_id).size()))

## The site furthest from `from_id` that no edge joins it to: a click there is a
## destination the stack cannot legally be ordered to. Sites with a stack on
## them are skipped — a click there selects that stack, which is consumed for a
## different and perfectly correct reason, and would not test the refusal.
func _unconnected_site(world: World, from_id: int) -> Site:
	var from := world.graph.site(from_id)
	var best: Site = null
	var best_d := -1.0
	for s in world.graph.sites:
		if s.id == from_id or world.graph.edge_between(from_id, s.id) != null:
			continue
		if not world.stacks_at(s.id).is_empty():
			continue
		var d: float = s.pos.distance_to(from.pos)
		if d > best_d:
			best_d = d
			best = s
	return best

func _site_named(world: World, site_name: String) -> Site:
	for s in world.graph.sites:
		if s.name == site_name:
			return s
	return null
