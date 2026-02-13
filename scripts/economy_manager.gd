# EconomyManager.gd
extends Node

# Global resources
var wood: int = 100 
var stone: int = 0

signal resources_changed

# --- NEW: TRACKING SOURCES ---
# A list of all buildings (Stockpiles, Harvesters) that hold items
var active_sources: Array[Building] = []

func register_source(b: Building):
	if not b in active_sources:
		active_sources.append(b)

func unregister_source(b: Building):
	if b in active_sources:
		active_sources.erase(b)
# -----------------------------

func add_resources(resource_name: String, amount: int):
	match resource_name:
		"Wood": wood += amount
		"Stone": stone += amount
	resources_changed.emit()

func can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		var amount_needed = cost[resource]
		match resource:
			"Wood": if wood < amount_needed: return false
			"Stone": if stone < amount_needed: return false
	return true

# --- UPDATED: SPEND LOGIC ---
func spend_resources(cost: Dictionary):
	# 1. Deduct from Global Numbers
	for resource in cost:
		var amount = cost[resource]
		match resource:
			"Wood": wood -= amount
			"Stone": stone -= amount
	
	resources_changed.emit()
	
	# 2. Physically remove items from buildings
	_pull_items_from_sources(cost)

func _pull_items_from_sources(cost: Dictionary):
	# We clone the cost so we can modify it as we pay
	var remaining_bill = cost.duplicate()
	
	for source in active_sources:
		# If the bill is paid, stop looking
		if remaining_bill.is_empty(): break
		
		# Ask the building to pay what it can
		# This modifies 'remaining_bill' directly
		if source.has_method("consume_resources"):
			source.consume_resources(remaining_bill)

# ----------------------------

# --- NEW HELPER ---
# Used when an item moves from a Building -> Belt.
# We treat belt items as "In Transit" (not spendable), so we just lower the number.
func remove_resources_from_global(cost: Dictionary):
	for resource in cost:
		var amount = cost[resource]
		match resource:
			"Wood": wood = max(0, wood - amount)
			"Stone": stone = max(0, stone - amount)
	
	resources_changed.emit()
