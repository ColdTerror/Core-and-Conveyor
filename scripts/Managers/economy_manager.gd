# ==============================================================================
# Script: Managers/economy_manager.gd
# Purpose: Global manager that acts as the vault for resource inventory, registers/tracks secure/unsecure buildings, logs item production/consumption metrics, and archives daily stats.
# Dependencies: Requires standard Godot Node parent, coordinates with TimeManager and SaveManager.
# Signals:
#   - inventory_changed: Emitted when global resources increase or decrease.
#   - stats_updated: Emitted when daily ledger values are updated.
# ==============================================================================
extends Node

# SIGNALS
signal inventory_changed 
signal stats_updated 

# RUNTIME STATE (THE VAULT)
var global_inventory: Dictionary = {"Wood": 0, "Stone": 0}

# The max 10 slots the player wants to see on the top bar
var pinned_resources: Array[String] = ["Wood", "Stone"]

# --- TRACKING SOURCES ---
var secured_sources: Array[Node] = []
var unsecured_sources: Array[Node] = []

# STATISTICS LEDGER
# Removed current_day variable (TimeManager tracks this now)
var daily_production: Dictionary = {}
var daily_consumption: Dictionary = {}
var history_archive: Array[Dictionary] = []



## Registers building node instances as resource sources.
func register_source(b: Node, is_secured: bool = true, skip_ghost_check: bool = false):
	if b.is_ghost and not skip_ghost_check: return
	
	if is_secured and not b in secured_sources:
		secured_sources.append(b)
	elif not is_secured and not b in unsecured_sources:
		unsecured_sources.append(b)
		
	if b.has_signal("inventory_changed") and not b.inventory_changed.is_connected(_on_source_inventory_changed):
		b.inventory_changed.connect(_on_source_inventory_changed)



## Unregisters building node instances from active resource sources.
func unregister_source(b: Node):
	secured_sources.erase(b)
	unsecured_sources.erase(b)
	if b.has_signal("inventory_changed") and b.inventory_changed.is_connected(_on_source_inventory_changed):
		b.inventory_changed.disconnect(_on_source_inventory_changed)



func _on_source_inventory_changed():
	inventory_changed.emit()



## Logs item production metrics, triggered when items are harvested or processed.
func log_item_produced(resource_name: String, amount: int = 1):
	daily_production[resource_name] = daily_production.get(resource_name, 0) + amount
	stats_updated.emit()


## Logs item consumption metrics, triggered when furnaces or upgrades consume items.
func log_item_consumed(resource_name: String, amount: int = 1):
	daily_consumption[resource_name] = daily_consumption.get(resource_name, 0) + amount
	stats_updated.emit()



## Adds physical items to the global secure vault inventory.
func add_resources(resource_name: String, amount: int):
	global_inventory[resource_name] = global_inventory.get(resource_name, 0) + amount
	inventory_changed.emit()


## Removes physical items from secure inventory, usually when bots take items from storage.
func remove_resources_from_global(cost: Dictionary):
	for resource_name in cost:
		var amount = cost[resource_name]
		var current = global_inventory.get(resource_name, 0)
		global_inventory[resource_name] = max(0, current - amount)
	
	inventory_changed.emit()


## Spends secure inventory resources on building placement or active technology upgrades.
func spend_resources(cost: Dictionary):
	for resource_name in cost:
		var amount = cost[resource_name]
		var current = global_inventory.get(resource_name, 0)
		global_inventory[resource_name] = max(0, current - amount)
		
		# Magic purchases immediately destroy the item, so we log consumption!
		log_item_consumed(resource_name, amount)
	
	inventory_changed.emit()
	_pull_items_from_sources(cost)


## Validates whether global secure inventory can cover a specified purchase cost.
func can_afford(cost: Dictionary) -> bool:
	for resource_name in cost:
		var amount_needed = cost[resource_name]
		var amount_we_have = global_inventory.get(resource_name, 0)
		if amount_we_have < amount_needed: 
			return false
	return true


## Consumes resources from secure physical sources to settle pending building costs.
func _pull_items_from_sources(cost: Dictionary):
	var remaining_bill = cost.duplicate()
	
	for source in secured_sources:
		if remaining_bill.is_empty(): break
		
		if source.has_method("consume_resources"):
			source.consume_resources(remaining_bill)



## Queries current secure inventory count for a specific resource type.
func get_item_count(item_name: String) -> int:
	return global_inventory.get(item_name, 0)


## Compiles a total map of resources currently stored in unsecure storage.
func get_unsecured_inventory() -> Dictionary:
	var in_transit = {}
	for source in unsecured_sources:
		if source.has_method("get_economy_assets"):
			var assets = source.get_economy_assets()
			for item_name in assets.keys():
				in_transit[item_name] = in_transit.get(item_name, 0) + assets[item_name]
	return in_transit



## Archives today's production/consumption ledger metrics and resets them for a new day.
func archive_daily_stats(day_number: int):
	var archive_entry = {
		"day": day_number,
		"produced": daily_production.duplicate(),
		"consumed": daily_consumption.duplicate()
	}
	history_archive.append(archive_entry)
	
	if history_archive.size() > 30:
		history_archive.pop_front()
		
	daily_production.clear()
	daily_consumption.clear()
	
	stats_updated.emit()



## Packs production metrics, statistics history archives, and pinned resources into a dictionary for saves.
func get_save_data() -> Dictionary:
	return {
		"daily_production": daily_production,
		"daily_consumption": daily_consumption,
		"history_archive": history_archive,
		"pinned_resources": pinned_resources
	}


## Unpacks saved statistics data, daily history logs, and pinned resources.
func load_save_data(data: Dictionary):
	daily_production = data.get("daily_production", {})
	daily_consumption = data.get("daily_consumption", {})
	history_archive.clear()
	if data.has("history_archive"):
		history_archive.assign(data["history_archive"])
	if data.has("pinned_resources"):
		pinned_resources.clear()
		for item in data["pinned_resources"]:
			pinned_resources.append(str(item))
	stats_updated.emit()



## Iterates through all registered secured buildings to recalculate total secure inventory.
func recalculate_global_inventory():
	global_inventory.clear()
	
	for source in secured_sources:
		if source.has_method("get_economy_assets"):
			var assets = source.get_economy_assets()
			for item_name in assets:
				global_inventory[item_name] = global_inventory.get(item_name, 0) + assets[item_name]
				
	inventory_changed.emit()
