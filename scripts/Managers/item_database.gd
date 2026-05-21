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
	"Plank": preload("res://resources/items/refined_resources/plank.tres"),
	"Stone Brick": preload("res://resources/items/refined_resources/stone_brick.tres"),
}



## Searches and returns the preloaded ItemResource instance matching the text name.
func get_item(name: String) -> ItemResource:
	if items.has(name):
		return items[name]
	else:
		print("ERROR: ItemDatabase doesn't know about: ", name)
		return null
