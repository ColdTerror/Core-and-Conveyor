# EconomyManager.gd
extends Node

# Global resources
var wood: int = 100 # Give some starting resources for testing!
var stone: int = 0

signal resources_changed # Connect your UI to this later

# 1. Helper to add resources (Harvesting)
func add_resources(resource_name: String, amount: int):
	match resource_name:
		"Wood": wood += amount
		"Stone": stone += amount
	
	resources_changed.emit()
	print("Inventory Updated | Wood: %d | Stone: %d" % [wood, stone])

# 2. Check if we have enough (Prediction)
# Expects a dictionary like: {"Wood": 10, "Stone": 5}
func can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		var amount_needed = cost[resource]
		
		match resource:
			"Wood":
				if wood < amount_needed: return false
			"Stone":
				if stone < amount_needed: return false
				
	return true

# 3. Deduct resources (Building)
func spend_resources(cost: Dictionary):
	for resource in cost:
		var amount = cost[resource]
		match resource:
			"Wood": wood -= amount
			"Stone": stone -= amount
			
	resources_changed.emit()
	print("Spent resources. Remaining | Wood: %d | Stone: %d" % [wood, stone])
	
#4. NEW: Loss of resources (Building Destruction)
func remove_resources(assets: Dictionary):

	# 'assets' is now guaranteed to be { "Wood": 10, "Stone": 5 }
	# The keys are STRINGS. Do NOT use .display_name here.
	
	for resource_name in assets:
		var amount = assets[resource_name]
		
		match resource_name:
			"Wood": 
				wood = max(0, wood - amount)
			"Stone": 
				stone = max(0, stone - amount)
				
	resources_changed.emit()
	print("Lost resources! Remaining | Wood: %d | Stone: %d" % [wood, stone])
