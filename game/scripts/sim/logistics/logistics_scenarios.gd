class_name LogisticsScenarios
extends RefCounted

## Appendix B's two logistics set-pieces as map-data variants of the prototype
## map. `world()` builds one; `status()` reads progress back out of the world's
## own state and log, so it needs no state of its own and a headless test can
## ask the same question the HUD does.

const HOLD_TURNS := 10           # The March: turns River East must be held
const MARCH_DEADLINE := 20
const SIEGE_DEADLINE := 25

## The supply level The March is lost at. It is **not** a number of this
## scenario's own: `_march_status` decides the loss from SupplyPhase's "short on
## supply" log line, and SupplyPhase emits that line when a stack crosses
## `logistics["supply_warning"]`. Tuning that one number has to move the rule and
## the words together, so both read it from here.
static func hold_above() -> float:
	return float(GameConfig.logistics["supply_warning"])

## The level The Siege calls "starving". Same trick as `hold_above()`: the word
## has to mean what the rule does, and what the marcher actually does at this
## level is split, so it reads `marcher_split_below` rather than repeating 40.
static func siege_starved() -> float:
	return float(GameConfig.logistics["marcher_split_below"])

static func all() -> Array[Dictionary]:
	return [
		{
			"name": "The March",
			"lesson": "Take River East and hold it %d turns without any stack dropping under %d supply. Split to forage and garrison; one stack cannot eat there that long." % [HOLD_TURNS, int(hold_above())],
		},
		{
			"name": "The Siege",
			"lesson": "A 14-stack sits on your frontier depot. Do not fight it: cut its road home with a raider, let it starve and split, then take the pieces.",
		},
	]

static func world(index: int, seed := 1) -> World:
	var data := PrototypeMap.data()
	match index:
		0:
			data["stacks"] = [_stack(0, "Capital Depot", 8, 2, 2)]
		1:
			# By name, not by index: renumbering the map must not promote some
			# other site to the frontier depot the whole scenario is about.
			var riverwatch := _site_data(data, "Riverwatch")
			if riverwatch.is_empty():
				push_error("The Siege expects a site named 'Riverwatch'; this map has none")
				return World.from_map(data, seed)
			riverwatch["kind"] = "depot"
			riverwatch["name"] = "Riverwatch Depot"
			data["stacks"] = [_stack(0, "Capital Depot", 6, 2, 0), _stack(1, "Riverwatch Depot", 10, 2, 2)]
	var w := World.from_map(data, seed)
	if index == 1:
		w.nation(1).weights["scripted"] = "marcher"
	return w

## The live entry for a named site in raw map data, or {} — the caller mutates
## what comes back, so this returns the dictionary itself and not a copy.
static func _site_data(data: Dictionary, site_name: String) -> Dictionary:
	for s in data.get("sites", []):
		if str(s.get("name", "")) == site_name:
			return s
	return {}

static func _stack(nation: int, site: String, inf: int, cav: int, arc: int) -> Dictionary:
	var roster: Array = []
	for i in inf:
		roster.append("infantry")
	for i in cav:
		roster.append("cavalry")
	for i in arc:
		roster.append("archers")
	return {"nation": nation, "site": site, "supply": 100, "regiments": roster}

## {text, won, lost} for one scenario, read fresh from the world every call.
##
## Pure and stateless: it mutates nothing and it does **not** latch. A scenario
## that was won on turn 12 and thrown away on turn 13 reports the turn 13
## answer, so a caller that wants "was this ever won" — the HUD, a test loop —
## keeps that flag itself.
static func status(index: int, w: World) -> Dictionary:
	match index:
		0:
			return _march_status(w)
		1:
			return _siege_status(w)
	return {"text": "", "won": false, "lost": false}

static func _march_status(w: World) -> Dictionary:
	var player := w.player()
	var region := _region_named(w, "River East")
	if region == null:
		return _misconfigured("River East")
	var threshold := int(hold_above())
	var captured := _last_event_turn(w, "River East %s %s" % [OccupationPhase.NOW_HELD, player.name])
	if region.owner != player.id or captured < 0:
		var late := w.turn > MARCH_DEADLINE
		return {"text": "River East is not yours yet (turn %d of %d)." % [w.turn, MARCH_DEADLINE], "won": false, "lost": late}
	var held := w.turn - captured
	# Two ways to be hungry, because the log alone misses one. SupplyPhase writes
	# its line on the *crossing*, so a detachment born under the threshold — it
	# inherits its parent's level — never crosses and never gets a line. The
	# reading of the stacks themselves catches that; the log catches a stack that
	# dipped and was fed again, or starved away entirely, since the capture.
	# `>=`, not `>`: a stack that dips on the very turn the region flips is still
	# a stack that went hungry holding it.
	var hungry := _last_event_turn(w, "%s " % player.name, SupplyPhase.SHORT_ON_SUPPLY) >= captured
	if not hungry:
		for s in w.stacks:
			if s.nation_id == player.id and s.supply < hold_above():
				hungry = true
				break
	if hungry:
		return {"text": "A stack fell under %d supply while holding. Lost." % threshold, "won": false, "lost": true}
	if held >= HOLD_TURNS:
		return {"text": "River East held %d turns above %d supply. Won." % [held, threshold], "won": true, "lost": false}
	return {"text": "River East held %d of %d turns; keep every stack above %d." % [held, HOLD_TURNS, threshold], "won": false, "lost": w.turn > MARCH_DEADLINE}

static func _siege_status(w: World) -> Dictionary:
	var player := w.player()
	var capital := _region_named(w, "Capital Plain")
	if capital == null:
		return _misconfigured("Capital Plain")
	if capital.owner != player.id:
		return {"text": "The capital fell. Lost.", "won": false, "lost": true}
	var west: Array = []
	for s in w.stacks:
		if s.nation_id != player.id and w.graph.region_of(s.site_id).owner == player.id:
			west.append(s)
	if west.is_empty():
		# An empty field is only a win if the siege did the emptying. A marcher
		# that simply walked home proves nothing; the lesson is the strangle.
		if _enemy_was_bled(w):
			return {"text": "Starved off your land. Won.", "won": true, "lost": false}
		return {"text": "No enemy stands on your land, but none of them starved for it.", "won": false, "lost": w.turn > SIEGE_DEADLINE}
	var biggest: Stack = west[0]
	for s in west:
		if s.size() > biggest.size():
			biggest = s
	var starving := biggest.supply < siege_starved()
	var text := "%s: %d regiments at %d%% supply%s." % [
		biggest.label, biggest.size(), int(round(biggest.supply)), " — starving" if starving else ""]
	if west.size() > 1:
		text += " It has split into %d." % west.size()
	# WS-C turns "take the pieces" into battles; until then the strangle is the lesson.
	return {"text": text, "won": false, "lost": w.turn > SIEGE_DEADLINE}

## True once hunger has actually cost a non-player nation regiments. Stack labels
## all begin with their nation's name, and SupplyPhase writes both lines.
##
## Deliberately the weaker of the two readings: "some non-player nation was bled"
## rather than "the nation that was besieging you was bled". Which nations were
## on your land on which turn is not recoverable from world state alone, and the
## only caller already knows the field is empty *now* — so a win is "nobody
## hostile is left standing here, and somebody hungry paid for that". On a
## two-nation map, which is every map this scenario runs on, the two readings
## are the same sentence.
static func _enemy_was_bled(w: World) -> bool:
	var player := w.player()
	for n in w.nations:
		if player != null and n.id == player.id:
			continue
		var prefix := "%s " % n.name
		for line in w.events:
			if not line.contains(prefix):
				continue
			if line.contains(SupplyPhase.DESERTION) or line.contains(SupplyPhase.DISSOLVED):
				return true
	return false

## A scenario asking for a region its map does not have is a broken scenario,
## not a lost game — but it must not read as "still going" either.
static func _misconfigured(region_name: String) -> Dictionary:
	return {"text": "scenario misconfigured: no region named '%s'" % region_name, "won": false, "lost": true}

static func _region_named(w: World, name: String) -> Region:
	for r in w.graph.regions:
		if r.name == name:
			return r
	push_error("scenario expects a region named '%s'; this map has none" % name)
	return null

## The turn of the latest log line containing both needles, or -1.
static func _last_event_turn(w: World, needle: String, also := "") -> int:
	var found := -1
	for line in w.events:
		if line.contains(needle) and (also == "" or line.contains(also)):
			var head: String = line.substr(1, line.find(" ") - 1)
			found = int(head)
	return found
