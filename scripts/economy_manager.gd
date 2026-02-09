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
func remove_resources(resources: Dictionary):
	if resources.is_empty(): return
	

	for resource_name in resources:
		var amount = resources[resource_name]
		
		print_debug(str(amount) + str(resource_name.display_name))
		
		match resource_name.display_name:
			"Wood": 
				wood = max(0, wood - amount) # Prevent negative numbers
			"Stone": 
				stone = max(0, stone - amount)
				
	resources_changed.emit()
	print("Lost resources! Remaining | Wood: %d | Stone: %d" % [wood, stone])
