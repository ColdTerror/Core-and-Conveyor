# ==============================================================================
# Script: Managers/building_database.gd
# Purpose: Master registry and lookup database for building PackedScenes and icons,
#          mirroring ItemDatabase. Provides single-source-of-truth access for the
#          Codex, HUD hotbar, upgrade systems, and managers.
# Dependencies: Preloaded building .tscn scenes.
# Signals: None.
# ==============================================================================
extends Node

# Master dictionary mapping building keys to a dictionary of tier levels -> PackedScene
var buildings: Dictionary = {
	"bow_tower": {
		1: preload("res://scenes/buildings & related/towers & defense/Bow Tower/bow_tower1.tscn"),
		2: preload("res://scenes/buildings & related/towers & defense/Bow Tower/bow_tower2.tscn"),
	},
	"ballista_tower": {
		1: preload("res://scenes/buildings & related/towers & defense/Ballista Tower/ballista_tower.tscn"),
	},
	"scattershot_tower": {
		1: preload("res://scenes/buildings & related/towers & defense/Scattershot Tower/scattershot_tower1.tscn"),
	},
	"sling_tower": {
		1: preload("res://scenes/buildings & related/towers & defense/Sling Tower/Sling_Tower1.tscn"),
	},
	"ammo_distributor": {
		1: preload("res://scenes/buildings & related/towers & defense/Ammo Distributor/ammo_distributor_building1.tscn"),
		2: preload("res://scenes/buildings & related/towers & defense/Ammo Distributor/ammo_distributor_building2.tscn"),
	},
	"wall": {
		1: preload("res://scenes/buildings & related/towers & defense/wall.tscn"),
	},
	"gate": {
		1: preload("res://scenes/buildings & related/towers & defense/gate_building.tscn"),
	},
	"conveyor_belt": {
		1: preload("res://scenes/buildings & related/belts & items/conveyer.tscn"),
	},
	"router_building": {
		1: preload("res://scenes/buildings & related/belts & items/router_building.tscn"),
	},
	"filter_building": {
		1: preload("res://scenes/buildings & related/belts & items/filter_building.tscn"),
	},
	"conveyor_bridge": {
		1: preload("res://scenes/buildings & related/belts & items/conveyer_bridge_building.tscn"),
	},
	"stockpile": {
		1: preload("res://scenes/buildings & related/belts & items/StockpileBuilding/stockpile_building1.tscn"),
		2: preload("res://scenes/buildings & related/belts & items/StockpileBuilding/stockpile_building2.tscn"),
	},
	"item_launcher": {
		1: preload("res://scenes/buildings & related/belts & items/item launcher&receiver/item launcher/item_launcher_building1.tscn"),
	},
	"item_receiver": {
		1: preload("res://scenes/buildings & related/belts & items/item launcher&receiver/item receiver/item_receiver_Building1.tscn"),
	},
	"core": {
		1: preload("res://scenes/buildings & related/core_building.tscn"),
	},
	"sawmill": {
		1: preload("res://scenes/buildings & related/processors/Sawmill/sawmill_building1.tscn"),
		2: preload("res://scenes/buildings & related/processors/Sawmill/sawmill_building2.tscn"),
	},
	"stonemason": {
		1: preload("res://scenes/buildings & related/processors/Stonemason/stonemason_building1.tscn"),
		2: preload("res://scenes/buildings & related/processors/Stonemason/stonemason_building2.tscn"),
	},
	"fletcher": {
		1: preload("res://scenes/buildings & related/processors/Fletcher/fletcher_building1.tscn"),
		2: preload("res://scenes/buildings & related/processors/Fletcher/fletcher_building2.tscn"),
	},
	"stone_crusher": {
		1: preload("res://scenes/buildings & related/processors/Stone Crusher/stone_crusher_building1.tscn"),
	},
	"forge": {
		1: preload("res://scenes/buildings & related/processors/Forge/forge_building1.tscn"),
	},
	"lumberjack": {
		1: preload("res://scenes/buildings & related/harvesters/Lumberjack/lumberjack_building1.tscn"),
		2: preload("res://scenes/buildings & related/harvesters/Lumberjack/lumberjack_building2.tscn"),
	},
	"stone_mine": {
		1: preload("res://scenes/buildings & related/harvesters/Mine/MineBuilding1.tscn"),
		2: preload("res://scenes/buildings & related/harvesters/Mine/MineBuilding2.tscn"),
	},
	"ore_drill": {
		1: preload("res://scenes/buildings & related/harvesters/OreDrillBuilding1.tscn"),
	},
	"bot_home": {
		1: preload("res://scenes/buildings & related/infrastructure/bot_home_building.tscn"),
	},
	"firepit": {
		1: preload("res://scenes/buildings & related/firepit_building.tscn"),
	},
	"quota_building": {
		1: preload("res://scenes/buildings & related/quota_building.tscn"),
	},
}

var _icon_cache: Dictionary = {}


## Normalizes building identifiers to handle space, capitalization, and naming variations.
static func normalize_name(raw_name: String) -> String:
	var n = raw_name.strip_edges().to_lower().replace(" ", "_")
	match n:
		"conveyor", "conveyor_belts", "belt", "belts":
			return "conveyor_belt"
		"router", "routers":
			return "router_building"
		"filter", "filters":
			return "filter_building"
		"bridge", "bridges":
			return "conveyor_bridge"
		"launcher", "launchers":
			return "item_launcher"
		"receiver", "receivers":
			return "item_receiver"
		"hut", "lumberjack_hut", "woodcutter":
			return "lumberjack"
		"mine", "quarry":
			return "stone_mine"
		"drill", "ore_extractor":
			return "ore_drill"
		"command_core", "base_core":
			return "core"
		"crusher":
			return "stone_crusher"
		"perimeter_wall", "walls":
			return "wall"
		"security_gate", "gates":
			return "gate"
		"distributor", "ammo_cannon":
			return "ammo_distributor"
		"fire_pit":
			return "firepit"
		"quota", "quota_station":
			return "quota_building"
	return n


## Returns the PackedScene for a building at a specified upgrade tier (default 1).
func get_building_scene(id_or_name: String, tier: int = 1) -> PackedScene:
	var norm = normalize_name(id_or_name)
	if buildings.has(norm):
		var tiers_dict: Dictionary = buildings[norm]
		if tiers_dict.has(tier):
			return tiers_dict[tier]
		elif tiers_dict.has(1):
			return tiers_dict[1]
	print("ERROR: BuildingDatabase doesn't know about building: ", id_or_name, " (tier ", tier, ")")
	return null


## Returns the icon Texture2D for a building scene, dynamically extracting and caching it.
func get_building_icon(id_or_name: String, tier: int = 1) -> Texture2D:
	var norm = normalize_name(id_or_name)
	var cache_key = "%s_%d" % [norm, tier]
	if _icon_cache.has(cache_key):
		return _icon_cache[cache_key]
		
	var scene = get_building_scene(norm, tier)
	if not scene:
		return null
		
	var inst = scene.instantiate()
	var tex: Texture2D = null
	
	if "icon" in inst and inst.icon != null:
		tex = inst.icon
	elif inst.has_node("Sprite2D"):
		var spr = inst.get_node("Sprite2D") as Sprite2D
		if spr and spr.texture:
			if spr.region_enabled:
				var atlas = AtlasTexture.new()
				atlas.atlas = spr.texture
				atlas.region = spr.region_rect
				tex = atlas
			else:
				tex = spr.texture
				
	inst.free()
	
	if tex:
		_icon_cache[cache_key] = tex
	return tex


## Returns an array of available tier levels for a building (e.g. [1, 2]).
func get_building_tiers(id_or_name: String) -> Array:
	var norm = normalize_name(id_or_name)
	if buildings.has(norm):
		var keys = (buildings[norm] as Dictionary).keys()
		keys.sort()
		return keys
	return []
