extends Building
class_name StockpileBuilding

@export var generic_item_scene: PackedScene
@export var capacity := 50   # Max total items stored
@export var work_interval: float = 1.0 # Speed of output

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

# Accept items on ANY tile we occupy
func accepts_item_at(tile: Vector2i) -> bool:
	return tile in occupied_tiles

func can_accept_item(item: ItemResource) -> bool:
	return get_total_items() < capacity

func accept_item(item: ItemResource) -> bool:
	if not can_accept_item(item):
		return false
		
	if not item.display_name in available_types:
		available_types.append(item.display_name)

	inventory[item] = inventory.get(item, 0) + 1
	
	# Emit inventory changed signal for ui
	inventory_changed.emit()
	
	# NEW: Update Global Economy
	EconomyManager.add_resources(item.display_name, 1)
	
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
	
	inventory_changed.emit()

func _find_item_by_name(name: String) -> ItemResource:
	for item in inventory:
		if item is ItemResource and item.display_name == name:
			return item
	return null
