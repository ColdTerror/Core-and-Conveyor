# EconomyManager.gd
extends Node

# --- DYNAMIC INVENTORY ---
# We use a Dictionary to track everything by its string name.
# You can define your starting resources here.
var global_inventory: Dictionary = {
	"Wood": 0,
	"Stone": 0
	
}

signal resources_changed

# --- TRACKING SOURCES ---
var active_sources: Array[Building] = []

func register_source(b: Building):
	if not b in active_sources:
		active_sources.append(b)

func unregister_source(b: Building):
	if b in active_sources:
		active_sources.erase(b)
# -----------------------------

func add_resources(resource_name: String, amount: int):
	# .get(name, 0) safely returns 0 if the item doesn't exist yet, 
	# preventing crashes when you add a brand new item like "Planks"
	global_inventory[resource_name] = global_inventory.get(resource_name, 0) + amount
	resources_changed.emit()

func can_afford(cost: Dictionary) -> bool:
	for resource_name in cost:
		var amount_needed = cost[resource_name]
		var amount_we_have = global_inventory.get(resource_name, 0)
		
		if amount_we_have < amount_needed: 
			return false
			
	return true

#Instant 'magic' purchase
func spend_resources(cost: Dictionary):
	# 1. Deduct from Global Numbers
	for resource_name in cost:
		var amount = cost[resource_name]
		var current = global_inventory.get(resource_name, 0)
		
		# max(0, ...) ensures we never accidentally go into negative numbers
		global_inventory[resource_name] = max(0, current - amount)
	
	resources_changed.emit()
	
	# 2. Physically remove items from buildings
	_pull_items_from_sources(cost)

func _pull_items_from_sources(cost: Dictionary):
	var remaining_bill = cost.duplicate()
	
	for source in active_sources:
		if remaining_bill.is_empty(): break
		
		if source.has_method("consume_resources"):
			source.consume_resources(remaining_bill)

# Used when an item moves from a Building -> Belt.
#Physical Purchase
func remove_resources_from_global(cost: Dictionary):
	for resource_name in cost:
		var amount = cost[resource_name]
		var current = global_inventory.get(resource_name, 0)
		
		global_inventory[resource_name] = max(0, current - amount)
	
	resources_changed.emit()
