# ==============================================================================
# Script: Managers/item_database.gd
# Purpose: Acts as a master database/lookup dictionary for ItemResource instances (Wood, Stone, Plank, Arrows, Stone Bricks) by name.
# Dependencies: Preloaded ItemResource files.
# Signals: None.
# ==============================================================================
extends Node

# A master dictionary connecting the text name to the actual file!
var items: Dictionary = {
	"Wood": preload("res://resources/items/raw_resources/wood.tres"),
	"Stone": preload("res://resources/items/raw_resources/stone.tres"),
	"Wooden Arrow": preload("res://resources/items/ammo/wooden_arrow.tres"),
	"Stone Arrow": preload("res://resources/items/ammo/stone_arrow.tres"),
	"Ballista Bolt": preload("res://resources/items/ammo/ballista_bolt.tres"),
	"Boulder": preload("res://resources/items/ammo/boulder_ammo.tres"),
	"Pebble": preload("res://resources/items/ammo/pebble_ammo.tres"),
	"Plank": preload("res://resources/items/refined_resources/plank.tres"),
	"Stone Brick": preload("res://resources/items/refined_resources/stone_brick.tres"),
}


## Normalizes item names to handle singular/plural variations cleanly.
static func normalize_name(item_name: String) -> String:
	var n = item_name.strip_edges()
	if n == "Planks": return "Plank"
	if n == "Stone Bricks": return "Stone Brick"
	if n == "Wooden Arrows": return "Wooden Arrow"
	if n == "Stone Arrows": return "Stone Arrow"
	if n == "Ballista Bolts": return "Ballista Bolt"
	if n == "Boulders": return "Boulder"
	if n == "Pebbles": return "Pebble"
	return n


## Compares two item names after normalizing singular/plural variations.
static func are_names_equal(name1: String, name2: String) -> bool:
	if name1 == name2: return true
	return normalize_name(name1) == normalize_name(name2)


## Searches and returns the preloaded ItemResource instance matching the text name.
func get_item(name: String) -> ItemResource:
	var norm = normalize_name(name)
	if items.has(norm):
		return items[norm]
	elif items.has(name):
		return items[name]
	else:
		print("ERROR: ItemDatabase doesn't know about: ", name)
		return null
