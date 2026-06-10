# ==============================================================================
# Script: Building Classes/bot_home_building.gd
# Purpose: Special building representing a worker bot's home charging stand.
# Dependencies: Inherits Building.
# ==============================================================================
extends Building
class_name BotHomeBuilding



func _ready():
	super()
	building_name = "Bot Home"
	is_solid_obstacle = false



## Returns the worker bot associated with this charging stand.
func get_bot() -> Node2D:
	if not is_inside_tree(): return null
	for bot in get_tree().get_nodes_in_group("Bots"):
		if bot != null and is_instance_valid(bot) and not bot.is_queued_for_deletion():
			if "home_tile" in bot and bot.home_tile == grid_origin:
				return bot
	return null



## Returns a custom detail text for the building menu.
func get_inventory_info() -> Dictionary:
	return {}
