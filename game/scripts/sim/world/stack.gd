class_name Stack
extends RefCounted

## A campaign army: regiments standing on one site. For the 90 seconds of a
## battle it becomes the combat prototype's Army (WS-C bridges the two).

var id := -1
var nation_id := -1
var site_id := -1
var regiments: Array[int] = []    # GameConfig.Role per regiment
var supply := 100.0               # 0..100 (Appendix B scale)
var leader_id := -1               # Character id (WS-G), -1 = none
var quality := 1.0                # leader multiplier; WS-G replaces the stub
var path: Array[int] = []         # site ids still to walk (WS-A)
var order := ""                   # "" | "hold" | "escort" | "raid" (WS-A/B/D)
var order_target := -1            # site, route or edge id the order refers to
var hold_separate := false
var label := ""
var moved_this_turn := false
var supply_report := {}           # written by SupplyPhase (WS-A), read by UI and AI

func size() -> int:
	return regiments.size()

## Counts regiments, not composition: a cavalry regiment weighs the same as
## infantry. WS-C and WS-D weight roles in their own layer if they need to —
## this number exists so the shell and the auto-resolve ratio have one cheap,
## agreed measure of "how big is that army".
func strength() -> float:
	return float(size()) * quality * GameConfig.supply_multiplier(supply / 100.0)
