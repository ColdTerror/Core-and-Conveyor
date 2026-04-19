extends Node

# ==========================================
# SIGNALS
# ==========================================
signal inventory_changed 
signal stats_updated 

# ==========================================
# RUNTIME STATE (THE VAULT)
# ==========================================
var global_inventory: Dictionary = {"Wood": 0, "Stone": 0}


# The max 10 slots the player wants to see on the top bar
var pinned_resources: Array[String] = ["Wood", "Stone"]

# --- TRACKING SOURCES ---d
var active_sources: Array[Node] = []

func register_source(b: Node):
	if not b in active_sources:
		active_sources.append(b)

func unregister_source(b: Node):
	if b in active_sources:
		active_sources.erase(b)

# ==========================================
# STATISTICS LEDGER
# ==========================================
# Removed current_day variable (TimeManager tracks this now)
var daily_production: Dictionary = {}
var daily_consumption: Dictionary = {}
var history_archive: Array[Dictionary] = []

# ==========================================
# CORE API: DEPOSITS & INCOME
# ==========================================
func add_resources(resource_name: String, amount: int):
	global_inventory[resource_name] = global_inventory.get(resource_name, 0) + amount
	daily_production[resource_name] = daily_production.get(resource_name, 0) + amount
	
	inventory_changed.emit()
	stats_updated.emit()

func can_afford(cost: Dictionary) -> bool:
	for resource_name in cost:
		var amount_needed = cost[resource_name]
		var amount_we_have = global_inventory.get(resource_name, 0)
		if amount_we_have < amount_needed: 
			return false
	return true

# ==========================================
# CORE API: WITHDRAWALS & EXPENSES
# ==========================================

# INSTANT 'MAGIC' PURCHASE (e.g., placing Belts/Towers)
func spend_resources(cost: Dictionary):
	# 1. Deduct from Global Numbers and update Stats
	for resource_name in cost:
		var amount = cost[resource_name]
		var current = global_inventory.get(resource_name, 0)
		
		global_inventory[resource_name] = max(0, current - amount)
		daily_consumption[resource_name] = daily_consumption.get(resource_name, 0) + amount
	
	inventory_changed.emit()
	stats_updated.emit()
	
	# 2. Physically remove items from buildings!
	_pull_items_from_sources(cost)

func _pull_items_from_sources(cost: Dictionary):
	var remaining_bill = cost.duplicate()
	
	for source in active_sources:
		if remaining_bill.is_empty(): break
		
		if source.has_method("consume_resources"):
			source.consume_resources(remaining_bill)

# PHYSICAL PURCHASE (Used when an item moves from a Building -> Belt/Bot)
func remove_resources_from_global(cost: Dictionary):
	for resource_name in cost:
		var amount = cost[resource_name]
		var current = global_inventory.get(resource_name, 0)
		
		global_inventory[resource_name] = max(0, current - amount)
		
		# Ensure physical extractions also count towards daily consumption!
		daily_consumption[resource_name] = daily_consumption.get(resource_name, 0) + amount
	
	inventory_changed.emit()
	stats_updated.emit()

func get_item_count(item_name: String) -> int:
	return global_inventory.get(item_name, 0)

# ==========================================
# ARCHIVING LOGIC (Triggered by TimeManager)
# ==========================================
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
	
	# We just emit stats_updated so the UI knows the "Today" column is now empty
	stats_updated.emit()

# ==========================================
# SAVE / LOAD SYSTEM
# ==========================================
func get_save_data() -> Dictionary:
	return {
		"daily_production": daily_production,
		"daily_consumption": daily_consumption,
		"history_archive": history_archive
	}

func load_save_data(data: Dictionary):
	daily_production = data.get("daily_production", {})
	daily_consumption = data.get("daily_consumption", {})
	history_archive.clear()
	if data.has("history_archive"):
		history_archive.assign(data["history_archive"])
	stats_updated.emit()

# Called by SaveManager AFTER all buildings have been spawned and loaded
func recalculate_global_inventory():
	global_inventory.clear()
	
	for source in active_sources:
		# Ask the building exactly what it holds right now
		if source.has_method("get_economy_assets"):
			var assets = source.get_economy_assets()
			for item_name in assets:
				global_inventory[item_name] = global_inventory.get(item_name, 0) + assets[item_name]
				
	inventory_changed.emit()
