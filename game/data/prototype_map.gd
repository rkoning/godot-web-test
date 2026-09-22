class_name PrototypeMap
extends RefCounted

## The 12-region logistics prototype map (Appendix B), laid over the combat
## prototype's terrain (game/scripts/sim/terrain.gd) so battles crop real
## ground: the river runs down x≈560–620 with the bridge ("The Ford") at
## (590, 390); cliffs sit in the NE corner (x≥1060, y≤120); forests at
## (720–940, 80–240) and (160–340, 520–680); swamp at (400–540, 600–740).
##
## Empire (nation 0) holds the six regions west of the river; Warlord
## (nation 1) holds the six east of it. The ford (a ROAD edge through
## "The Ford") is the only crossing between the two territories: the edge
## "Fordwatch" → "The Ford" is the only edge in the map whose endpoints sit on
## opposite sides of x = 560, and a test holds it to that. The map's MOUNTAIN
## edge, from "Horses Ranch" to "Craghold", is an internal Warlord-side pass
## into the cliff corner and does not cross the river.
##
## Each side's backbone is a network, not a tree: eight lateral edges give both
## nations alternate routes between their regions, so losing one site to a
## raider reroutes a supply line instead of ending it, and "East Hill" — the
## eastern battle feature — is a through-site rather than a dead end. Two of the
## eight are each depot's second road, so no depot is a leaf hanging off its
## market. The tested invariant is that for every site except "The Ford",
## removing it leaves each nation's depot still able to reach one of that
## nation's own farms — that is what holds these eight edges in place.
##
## The starting armies are map data too ("stacks", below), so the shell, a test
## and the headless AI harness all seed the same world from the same source.

static func data() -> Dictionary:
	return {
		"nations": [
			{"id": 0, "name": "Empire", "color": "4a90d9", "player": true, "coin": 60},
			{"id": 1, "name": "Warlord", "color": "d9534f", "player": false, "coin": 60},
		],
		"relations": [{"a": 0, "b": 1, "state": "war"}],
		"regions": [
			{"id": 0, "name": "Capital Plain", "owner": 0, "posture": "economic"},
			{"id": 1, "name": "West Hills", "owner": 0, "posture": "military"},
			{"id": 2, "name": "Grainfields", "owner": 0, "posture": "economic"},
			{"id": 3, "name": "Millwood", "owner": 0, "posture": "economic"},
			{"id": 4, "name": "Riverside West", "owner": 0, "posture": "military"},
			{"id": 5, "name": "Ironhold", "owner": 0, "posture": "military"},
			{"id": 6, "name": "River East", "owner": 1, "posture": "military"},
			{"id": 7, "name": "Warcamp", "owner": 1, "posture": "military"},
			{"id": 8, "name": "Northwood", "owner": 1, "posture": "economic"},
			{"id": 9, "name": "Eastern Highlands", "owner": 1, "posture": "military"},
			{"id": 10, "name": "Craglands", "owner": 1, "posture": "military"},
			{"id": 11, "name": "South Warlord", "owner": 1, "posture": "economic"},
		],
		"sites": [
			# Region 0: Capital Plain
			{"id": 0, "region": 0, "kind": "market", "pos": [260, 400], "name": "Capital"},
			{"id": 1, "region": 0, "kind": "depot", "pos": [300, 420], "name": "Capital Depot"},
			{"id": 2, "region": 0, "kind": "village", "pos": [220, 440], "name": "Millbrook"},
			# Region 1: West Hills
			{"id": 3, "region": 1, "kind": "farm", "pos": [150, 120], "name": "Highfield"},
			{"id": 4, "region": 1, "kind": "village", "pos": [110, 200], "name": "Hilltown"},
			{"id": 5, "region": 1, "kind": "feature", "pos": [300, 190], "name": "West Hill"},
			# Region 2: Grainfields
			{"id": 6, "region": 2, "kind": "farm", "pos": [60, 560], "name": "Long Furrow"},
			{"id": 7, "region": 2, "kind": "farm", "pos": [100, 620], "name": "Sunfield"},
			{"id": 8, "region": 2, "kind": "node", "pos": [140, 460], "name": "Grain Exchange", "tag": "grain"},
			# Region 3: Millwood
			{"id": 9, "region": 3, "kind": "village", "pos": [200, 600], "name": "Woodhaven"},
			{"id": 10, "region": 3, "kind": "farm", "pos": [260, 640], "name": "Fern Hollow"},
			{"id": 11, "region": 3, "kind": "mine", "pos": [300, 560], "name": "Stonecrest Mine"},
			# Region 4: Riverside West
			{"id": 12, "region": 4, "kind": "village", "pos": [540, 340], "name": "Riverwatch"},
			{"id": 13, "region": 4, "kind": "village", "pos": [540, 380], "name": "Fordwatch"},
			{"id": 14, "region": 4, "kind": "farm", "pos": [540, 460], "name": "West Bank Farm"},
			{"id": 15, "region": 4, "kind": "feature", "pos": [590, 390], "name": "The Ford"},
			# Region 5: Ironhold
			{"id": 16, "region": 5, "kind": "village", "pos": [440, 700], "name": "Ironhold"},
			{"id": 17, "region": 5, "kind": "node", "pos": [460, 660], "name": "Iron Vein", "tag": "iron"},
			{"id": 18, "region": 5, "kind": "farm", "pos": [420, 740], "name": "Southwatch"},
			# Region 6: River East
			{"id": 19, "region": 6, "kind": "village", "pos": [660, 340], "name": "Reed Landing"},
			{"id": 20, "region": 6, "kind": "village", "pos": [650, 400], "name": "Fording East"},
			{"id": 21, "region": 6, "kind": "farm", "pos": [650, 460], "name": "East Bank Farm"},
			# Region 7: Warcamp
			{"id": 22, "region": 7, "kind": "market", "pos": [750, 450], "name": "Warcamp Market"},
			{"id": 23, "region": 7, "kind": "depot", "pos": [800, 470], "name": "Warcamp Depot"},
			{"id": 24, "region": 7, "kind": "village", "pos": [780, 420], "name": "Fenwick"},
			# Region 8: Northwood
			{"id": 25, "region": 8, "kind": "village", "pos": [760, 140], "name": "Woodgate"},
			{"id": 26, "region": 8, "kind": "farm", "pos": [820, 180], "name": "Forest Farm"},
			{"id": 27, "region": 8, "kind": "node", "pos": [900, 120], "name": "Horses Ranch", "tag": "horses"},
			# Region 9: Eastern Highlands
			{"id": 28, "region": 9, "kind": "feature", "pos": [940, 490], "name": "East Hill"},
			{"id": 29, "region": 9, "kind": "village", "pos": [1000, 440], "name": "Hilltop Watch"},
			{"id": 30, "region": 9, "kind": "farm", "pos": [960, 560], "name": "Ridge Farm"},
			# Region 10: Craglands
			{"id": 31, "region": 10, "kind": "village", "pos": [1000, 160], "name": "Northgate"},
			{"id": 32, "region": 10, "kind": "village", "pos": [1120, 180], "name": "Craghold"},
			{"id": 33, "region": 10, "kind": "mine", "pos": [1080, 240], "name": "Peak Mine"},
			# Region 11: South Warlord
			{"id": 34, "region": 11, "kind": "farm", "pos": [760, 600], "name": "Southfield"},
			{"id": 35, "region": 11, "kind": "farm", "pos": [700, 650], "name": "Eastmoor"},
			{"id": 36, "region": 11, "kind": "village", "pos": [820, 620], "name": "Millhaven"},
		],
		"edges": [
			# Region 0
			{"a": 0, "b": 1},
			{"a": 0, "b": 2},
			# Region 1
			{"a": 3, "b": 4},
			{"a": 4, "b": 5, "kind": "trail"},
			# Region 2
			{"a": 6, "b": 7},
			{"a": 7, "b": 8},
			# Region 3
			{"a": 9, "b": 10},
			{"a": 9, "b": 11},
			# Region 4 (river chain along the west bank, the ford crossing west leg)
			{"a": 12, "b": 13, "kind": "river"},
			{"a": 13, "b": 14, "kind": "river"},
			{"a": 13, "b": 15},
			# Region 5
			{"a": 16, "b": 17},
			{"a": 16, "b": 18},
			# Region 6 (river chain along the east bank, the ford crossing east leg)
			{"a": 19, "b": 20, "kind": "river"},
			{"a": 20, "b": 21, "kind": "river"},
			{"a": 15, "b": 20},
			# Region 7
			{"a": 22, "b": 23},
			{"a": 22, "b": 24},
			# Region 8
			{"a": 25, "b": 26},
			{"a": 26, "b": 27},
			# Region 9
			{"a": 28, "b": 29},
			{"a": 29, "b": 30},
			# Region 10
			{"a": 31, "b": 32},
			{"a": 32, "b": 33},
			# Region 11
			{"a": 34, "b": 35},
			{"a": 34, "b": 36},
			# Empire backbone (all same-nation roads)
			{"a": 2, "b": 13},
			{"a": 0, "b": 8},
			{"a": 2, "b": 9},
			{"a": 9, "b": 16},
			{"a": 3, "b": 0},
			# Warlord backbone (all same-nation roads)
			{"a": 20, "b": 22},
			{"a": 22, "b": 29},
			{"a": 22, "b": 25},
			{"a": 25, "b": 31},
			{"a": 22, "b": 34},
			# Internal Warlord-side pass into the cliff corner (not a nation
			# crossing: both endpoints are on the Warlord side of the river).
			{"a": 27, "b": 32, "kind": "mountain"},
			# Laterals: the alternate routes. Each joins two sites that are
			# already neighbours on the ground (within ~330 units) and on the
			# same side of x = 560, so none of them is a second crossing.
			{"a": 5, "b": 0, "kind": "trail"},    # West Hill → Capital
			{"a": 6, "b": 9},                     # Long Furrow → Woodhaven
			{"a": 11, "b": 16, "kind": "trail"},  # Stonecrest Mine → Ironhold
			{"a": 28, "b": 22, "kind": "trail"},  # East Hill → Warcamp Market
			{"a": 24, "b": 29},                   # Fenwick → Hilltop Watch
			{"a": 30, "b": 36},                   # Ridge Farm → Millhaven
			# Each depot's second road. Without these a depot hangs off its
			# market as a leaf, and losing the market strands it — there is no
			# alternate route to supply from, which is the thing WS-A's
			# redundancy rules exist to trade Coin for.
			{"a": 1, "b": 2},                     # Capital Depot → Millbrook
			{"a": 23, "b": 24},                   # Warcamp Depot → Fenwick
		],
		# The two field armies the campaign opens with, by site name so
		# renumbering the map cannot move one somewhere else.
		"stacks": [
			{
				"nation": 0, "site": "Capital Depot", "supply": 100,
				"regiments": [
					"infantry", "infantry", "infantry", "infantry",
					"infantry", "infantry", "infantry", "infantry",
					"cavalry", "cavalry", "archers", "archers",
				],
			},
			{
				"nation": 1, "site": "Warcamp Depot", "supply": 100,
				"regiments": [
					"infantry", "infantry", "infantry", "infantry",
					"cavalry", "cavalry",
				],
			},
		],
	}
