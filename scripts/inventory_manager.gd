extends Node

# Global variables accessible from any script
var wood: int = 0
var stone: int = 0

# A helper function to add resources and print a status update
func add_resources(resource_name: String, amount: int):
	match resource_name:
		"Forest":
			wood += amount
		"Stone":
			stone += amount
	
	print_debug("Inventory Updated | Wood: ", wood, " | Stone: ", stone)
