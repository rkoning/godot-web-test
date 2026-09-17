class_name ThemeColors
extends RefCounted

const BACKGROUND := Color("0f131c")
const PANEL := Color("1d2433")
const PANEL_EDGE := Color("2c3547")
const TEXT := Color("d6dee9")
const TEXT_DIM := Color("8894a6")
const PLAYER := Color("4a90d9")
const ENEMY := Color("d95f5f")
const ACCENT := Color("5ec8a0")
const WARN := Color("e6b45e")

const PLAIN := Color("29352b")
const FOREST := Color("1b3324")
const SWAMP := Color("343320")
const CLIFF := Color("4a4753")
const WATER := Color("16324f")
const BRIDGE := Color("6b5334")
const ROAD := Color("6d6350")

static func biome(kind: int) -> Color:
	match kind:
		Terrain.Biome.FOREST: return FOREST
		Terrain.Biome.SWAMP: return SWAMP
		Terrain.Biome.CLIFF: return CLIFF
		Terrain.Biome.WATER: return WATER
		Terrain.Biome.BRIDGE: return BRIDGE
		_: return PLAIN

static func side(s: int) -> Color:
	return PLAYER if s == GameConfig.Side.PLAYER else ENEMY
