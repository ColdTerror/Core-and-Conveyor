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

# Master dictionary of building construction and upgrade costs.
# Single source of truth for all building build and upgrade prices.
var building_costs: Dictionary = {
	"bow_tower": {
		1: { "build": { "Wood": 25, "Stone": 25 }, "upgrade": { "Wood": 50, "Stone": 25, "Planks": 25 } },
		2: { "build": {}, "upgrade": {} }
	},
	"stockpile": {
		1: { "build": { "Wood": 20, "Stone": 10 }, "upgrade": { "Wood": 40, "Stone": 20, "Planks": 15 } },
		2: { "build": {}, "upgrade": {} }
	},
	"fletcher": {
		1: { "build": { "Wood": 25, "Stone": 25 }, "upgrade": { "Wood": 50, "Stone": 50, "Planks": 25 } },
		2: { "build": {}, "upgrade": {} }
	},
	"sawmill": {
		1: { "build": { "Wood": 30, "Stone": 15 }, "upgrade": { "Wood": 60, "Stone": 30, "Planks": 20 } },
		2: { "build": {}, "upgrade": {} }
	},
	"stonemason": {
		1: { "build": { "Wood": 25, "Stone": 30 }, "upgrade": { "Wood": 50, "Stone": 60, "Stone Bricks": 20 } },
		2: { "build": {}, "upgrade": {} }
	},
	"lumberjack": {
		1: { "build": { "Wood": 15, "Stone": 10 }, "upgrade": { "Wood": 30, "Stone": 20, "Planks": 15 } },
		2: { "build": {}, "upgrade": {} }
	},
	"stone_mine": {
		1: { "build": { "Wood": 20, "Stone": 15 }, "upgrade": { "Wood": 40, "Stone": 30, "Planks": 20 } },
		2: { "build": {}, "upgrade": {} }
	},
	"ammo_distributor": {
		1: { "build": { "Planks": 15, "Stone Bricks": 15 }, "upgrade": { "Planks": 30, "Stone Bricks": 30 } },
		2: { "build": {}, "upgrade": {} }
	},
	"ballista_tower": {
		1: { "build": { "Planks": 30, "Stone Bricks": 30 }, "upgrade": {} }
	},
	"scattershot_tower": {
		1: { "build": { "Planks": 20, "Stone": 25 }, "upgrade": {} }
	},
	"sling_tower": {
		1: { "build": { "Wood": 15, "Stone": 15 }, "upgrade": {} }
	},
	"wall": {
		1: { "build": { "Wood": 2, "Stone": 2 }, "upgrade": {} }
	},
	"gate": {
		1: { "build": { "Wood": 10, "Stone": 10 }, "upgrade": {} }
	},
	"conveyor_belt": {
		1: { "build": { "Wood": 1 }, "upgrade": {} }
	},
	"router_building": {
		1: { "build": { "Wood": 5, "Stone": 5 }, "upgrade": {} }
	},
	"filter_building": {
		1: { "build": { "Wood": 10, "Stone": 10 }, "upgrade": {} }
	},
	"conveyor_bridge": {
		1: { "build": { "Wood": 10, "Stone": 10 }, "upgrade": {} }
	},
	"item_launcher": {
		1: { "build": { "Wood": 25, "Stone": 25 }, "upgrade": {} }
	},
	"item_receiver": {
		1: { "build": { "Wood": 25, "Stone": 25 }, "upgrade": {} }
	},
	"stone_crusher": {
		1: { "build": { "Wood": 20, "Stone": 25 }, "upgrade": {} }
	},
	"forge": {
		1: { "build": { "Wood": 30, "Stone": 40, "Planks": 20, "Stone Bricks": 20 }, "upgrade": {} }
	},
	"ore_drill": {
		1: { "build": { "Wood": 30, "Stone": 30 }, "upgrade": {} }
	},
	"bot_home": {
		1: { "build": { "Wood": 25, "Stone": 25 }, "upgrade": {} }
	},
	"firepit": {
		1: { "build": { "Wood": 20, "Stone": 20 }, "upgrade": {} }
	},
	"quota_building": {
		1: { "build": { "Wood": 50, "Stone": 50 }, "upgrade": {} }
	},
	"core": {
		1: { "build": {}, "upgrade": {} }
	}
}

var _icon_cache: Dictionary = {}


## Normalizes building identifiers to handle space, capitalization, and naming variations.
static func normalize_name(raw_name: String) -> String:
	var n = raw_name.strip_edges().to_lower().replace(" ", "_")
	if n.ends_with("_1") or n.ends_with("_2") or n.ends_with("_3"):
		n = n.substr(0, n.length() - 2)
	elif n.length() > 1 and n[n.length() - 1] in ["1", "2", "3"]:
		n = n.substr(0, n.length() - 1)
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


## Returns the build cost dictionary for a specified building and tier (default tier 1).
func get_build_cost(id_or_name: String, tier: int = 1) -> Dictionary:
	var norm = normalize_name(id_or_name)
	if building_costs.has(norm):
		var tier_dict: Dictionary = building_costs[norm]
		if tier_dict.has(tier) and tier_dict[tier].has("build"):
			return tier_dict[tier]["build"].duplicate()
		elif tier_dict.has(1) and tier_dict[1].has("build"):
			return tier_dict[1]["build"].duplicate()
	return {}


## Returns the upgrade cost dictionary for a specified building and tier (default tier 1).
func get_upgrade_cost(id_or_name: String, tier: int = 1) -> Dictionary:
	var norm = normalize_name(id_or_name)
	if building_costs.has(norm):
		var tier_dict: Dictionary = building_costs[norm]
		if tier_dict.has(tier) and tier_dict[tier].has("upgrade"):
			return tier_dict[tier]["upgrade"].duplicate()
	return {}


## Formats a cost dictionary into a human-readable string (e.g. "25 Wood, 10 Stone").
func get_cost_string(cost_dict: Dictionary) -> String:
	if cost_dict.is_empty():
		return "Free"
	var parts: Array[String] = []
	for item_name in cost_dict:
		parts.append("%d %s" % [cost_dict[item_name], item_name])
	return ", ".join(parts)


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
