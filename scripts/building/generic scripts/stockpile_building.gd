extends Building
class_name StockpileBuilding

@export var generic_item_scene: PackedScene
@export var work_interval: float = 1.0 # Speed of output


# --- NEW: INVENTORY MODES ---
@export var max_mixed_capacity: int = 25
@export var max_dedicated_capacity: int = 100

var is_dedicated_mode: bool = false
var dedicated_item_name: String = "" # Remembers what item it locked onto
# ----------------------------

var inventory: Dictionary = {}  # ItemResource → amount
var work_timer: float = 0.0

# FILTER STATE
var selected_output_name: String = "" # "" means output nothing
var available_types: Array = [] # Cache of types we have seen (for cycling)

var level_ref: Node2D

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance
	
func _ready():
	super() # Run building class ready as well
	building_name = "Stockpile"
	size = Vector2i(4, 4)
	health = max_health
	EconomyManager.register_source(self)

func _exit_tree():
	# Unregister Self
	EconomyManager.unregister_source(self)

#--- TICK LOOP ---
func building_tick(delta: float) -> void:
	# Only output if we have a valid selection
	if selected_output_name != "":
		work_timer -= delta
		if work_timer <= 0:
			work_timer = work_interval
			_try_output_item()

# --- UI INTERACTION ---
func cycle_output_mode():
	# 1. Refresh available types from current inventory
	for item in inventory.keys():
		var n = item.display_name
		if not n in available_types:
			available_types.append(n)
	
	if available_types.is_empty(): 
		selected_output_name = ""
		return

	# 2. Cycle Logic
	if selected_output_name == "":
		selected_output_name = available_types[0]
	else:
		var idx = available_types.find(selected_output_name)
		if idx == -1 or idx + 1 >= available_types.size():
			selected_output_name = "" # Reset to OFF
		else:
			selected_output_name = available_types[idx + 1]
			
	print("Stockpile Output set to: ", selected_output_name if selected_output_name != "" else "OFF")

# =================================================================
# NEW: OUTPUT LOGIC (Node-Based)
# =================================================================
func _try_output_item():
	if not level_ref: return
	var manager = level_ref.building_manager

	# Loop through all tiles we occupy
	for my_tile in occupied_tiles:
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			# Don't output into ourself
			if occupied_tiles.has(target_pos): continue
			
			# Check BuildingManager for neighbors
			if manager.occupied_tiles.has(target_pos):
				var neighbor = manager.occupied_tiles[target_pos]
				
				# Is it a Conveyor?
				if neighbor is ConveyorBuilding:
					# Only output if the belt is pointing exactly AWAY from us
					if neighbor.direction == offset:
						# Try to spawn. This function returns TRUE if successful
						if _spawn_item_into_conveyor(neighbor):
							return # Success! Stop trying other belts this tick.

func _spawn_item_into_conveyor(conveyor: ConveyorBuilding) -> bool:
	# --- MOVED FROM _try_output_item ---
	# 1. Check if we actually have the selected item
	var item_res = _find_item_by_name(selected_output_name)
	if not item_res or inventory.get(item_res, 0) <= 0:
		return false # Inventory empty for this type
	# -----------------------------------
	
	if not generic_item_scene: return false
	
	# 2. Create the Visual Node
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	new_item_node.item_data = item_res
	
	new_item_node.global_position = global_position 
	
	if new_item_node.has_method("_ready"): new_item_node._ready() 
	
	# 3. Try to hand it to the Conveyor
	if conveyor.accept_item_node(new_item_node):
		
		# A. Inventory Logic
		inventory[item_res] -= 1
		if inventory[item_res] <= 0:
			inventory.erase(item_res)
			_prune_available_types()
			
		# B. Economy Logic
		EconomyManager.remove_resources_from_global({ item_res.display_name: 1 })
		
		inventory_changed.emit()
		return true # Success!
	else:
		new_item_node.queue_free()
		return false # Failed, try next conveyor

# =================================================================

# --------------------------------------------------
# ITEM INTERFACE (called by Item / Conveyor systems)
# --------------------------------------------------

func can_accept_item(item: ItemResource) -> bool:
	var current_total = get_total_items()
	
	if is_dedicated_mode:
		if current_total == 0 and dedicated_item_name == "":
			return true  # Will lock on accept
		# Now also check against the name even if empty but name is set
		if dedicated_item_name != "" and item.display_name != dedicated_item_name:
			return false
			
		# Reject if it doesn't match the dedicated type, or if we hit 100
		if item.display_name != dedicated_item_name: return false
		if current_total >= max_dedicated_capacity: return false
		return true
		
	else: # Mixed Mode
		# Accept anything, as long as total is under 50
		if current_total >= max_mixed_capacity: return false
		return true

func accept_item(item: ItemResource) -> bool:
	if not can_accept_item(item):
		return false
		
	# --- NEW: Lock the dedicated mode to this item if we are empty! ---
	if is_dedicated_mode and get_total_items() == 0:
		dedicated_item_name = item.display_name
	# ------------------------------------------------------------------
		
	if not item.display_name in available_types:
		available_types.append(item.display_name)

	inventory[item] = inventory.get(item, 0) + 1
	
	# NEW: Update Global Economy
	EconomyManager.add_resources(item.display_name, 1)
	
	# Emit inventory changed signal for ui
	inventory_changed.emit()
	
	return true

# --------------------------------------------------
# HELPERS
# --------------------------------------------------

func get_total_items() -> int:
	var total := 0
	for amount in inventory.values():
		total += amount
	return total

func get_item_amount(item: ItemResource) -> int:
	return inventory.get(item, 0)
	
func get_inventory_info() -> Dictionary:
	return inventory
	
func get_economy_assets() -> Dictionary:
	var assets = {}
	for item in inventory:
		if item is ItemResource:
			assets[item.display_name] = inventory[item]
	return assets


# 3. Implement Consumption Logic
func consume_resources(remaining_bill: Dictionary):
	var needed_items = remaining_bill.keys()
	
	for resource_name in needed_items:
		var amount_needed = remaining_bill[resource_name]
		var item_ref = _find_item_by_name(resource_name)
		
		if item_ref:
			var amount_we_have = inventory[item_ref]
			var amount_to_take = min(amount_needed, amount_we_have)
			
			inventory[item_ref] -= amount_to_take
			if inventory[item_ref] <= 0:
				inventory.erase(item_ref)
			
			remaining_bill[resource_name] -= amount_to_take
			if remaining_bill[resource_name] <= 0:
				remaining_bill.erase(resource_name)
	
	_prune_available_types()
	inventory_changed.emit()

func _find_item_by_name(name: String) -> ItemResource:
	for item in inventory:
		if item is ItemResource and item.display_name == name:
			return item
	return null
	
# --- UI ACTIONS ---
# --- UI ACTIONS ---
func toggle_inventory_mode():
	is_dedicated_mode = not is_dedicated_mode
	
	if is_dedicated_mode:
		if inventory.size() > 0:
			# 1. Find the item with the highest count
			var max_item_ref: ItemResource = null
			var max_count: int = -1
			
			for item in inventory.keys():
				if inventory[item] > max_count:
					max_count = inventory[item]
					max_item_ref = item
					
			# 2. Lock onto the winner!
			dedicated_item_name = max_item_ref.display_name
			print("Switched to Dedicated. Locked to majority item: ", dedicated_item_name)
			
			# 3. Void all the losers
			var assets_to_remove = {}
			var items_to_erase = []
			
			for item in inventory.keys():
				if item != max_item_ref:
					assets_to_remove[item.display_name] = inventory[item]
					items_to_erase.append(item)
					
			# 4. Clean up the economy and local data if anything was voided
			if not assets_to_remove.is_empty():
				EconomyManager.remove_resources_from_global(assets_to_remove)
				
				for item in items_to_erase:
					inventory.erase(item)
					
				# Reset available types cache to just the winner
				available_types.clear()
				available_types.append(dedicated_item_name)
				
				# Safety check: If we were trying to output arrows, but arrows just got voided, turn output OFF
				if selected_output_name != "" and selected_output_name != dedicated_item_name:
					selected_output_name = ""
					
		else:
			# It's completely empty, wait for the first item
			dedicated_item_name = ""
			print("Switched to Dedicated. Waiting for first item...")
	else:
		# Switched back to Mixed mode, clear the lock
		dedicated_item_name = ""
		print("Switched to Mixed mode.")
		
	inventory_changed.emit()

func void_inventory():
	var assets = get_economy_assets()
	if not assets.is_empty():
		# Erase from the global UI
		EconomyManager.remove_resources_from_global(assets)
		
	# Completely clear local data
	inventory.clear()
	available_types.clear()
	selected_output_name = "" # Turn off output
	
	# Reset the dedicated lock since it's empty now
	if is_dedicated_mode:
		dedicated_item_name = "" 
	
	inventory_changed.emit()
	
	
func _prune_available_types():
	var current_names = []
	for item in inventory.keys():
		current_names.append(item.display_name)
	available_types = current_names
	
	# If selected output is no longer available, turn it off
	if selected_output_name != "" and not selected_output_name in available_types:
		selected_output_name = ""
		print("Output auto-disabled: item no longer in inventory")
