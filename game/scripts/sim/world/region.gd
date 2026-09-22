class_name Region
extends RefCounted

## A container for ownership, posture and 3–6 sites. Nothing is produced here;
## see Site. WS-F adds culture, faith and unrest fields.

enum Posture { MILITARY, ECONOMIC, SOCIAL }

var id := -1
var name := ""
var owner := -1                   # nation id, -1 = unowned / wild
var posture := Posture.ECONOMIC
var sites: Array[int] = []
var polygon: PackedVector2Array = PackedVector2Array()   # optional authored outline (WS-J); empty = derive a hull
