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
	super() #run building class ready as well
	building_name = "Stockpile"
	size = Vector2i(4, 4)
	health = max_health
	EconomyManager.register_source(self)

func _exit_tree():
	# 2. Unregister Self
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
# Called by the Button in the Popup
func cycle_output_mode():
	# 1. Refresh available types from current inventory
	# (We merge new items found in inventory into our known list)
	for item in inventory.keys():
		var n = item.display_name
		if not n in available_types:
			available_types.append(n)
	
	if available_types.is_empty(): 
		selected_output_name = ""
		return

	# 2. Cycle Logic
	# Modes: "" (OFF) -> "Wood" -> "Stone" -> "" (OFF)
	if selected_output_name == "":
		selected_output_name = available_types[0]
	else:
		var idx = available_types.find(selected_output_name)
		if idx == -1 or idx + 1 >= available_types.size():
			selected_output_name = "" # Reset to OFF
		else:
			selected_output_name = available_types[idx + 1]
			
	print("Stockpile Output set to: ", selected_output_name if selected_output_name != "" else "OFF")

# --- OUTPUT LOGIC ---
func _try_output_item():
	# 1. Check if we actually have the selected item
	var item_res = _find_item_by_name(selected_output_name)
	if not item_res or inventory.get(item_res, 0) <= 0:
		return # Inventory empty for this type, wait for more
		
	# 2. Look for valid output spot (Conveyors)
	# (We assume 'level_ref' exists on base class or is injected)
	if not "level_ref" in self or not level_ref: return
	
	
	for my_tile in occupied_tiles:
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			if occupied_tiles.has(target_pos): continue # Don't output into self
			if level_ref.item_grid.has(target_pos): continue # Tile occupied
			
			# Check for Belt
			if level_ref.active_grid_objects.has(target_pos):
				var info = level_ref.active_grid_objects[target_pos]
				var data = info["data"]
				
				if data.is_conveyor:
					var conveyor_dir = info.get("direction", Vector2.ZERO)
					# Must match belt direction
					if conveyor_dir == Vector2(offset):
						_spawn_item_on_belt(target_pos, item_res)
						return # Only spawn 1 item per tick

func _spawn_item_on_belt(pos: Vector2i, item: ItemResource):
	if not generic_item_scene: return
	
	# 1. Visuals
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = item
	if new_item_node.has_method("_ready"): new_item_node._ready()
	
	level_ref.add_child(new_item_node)
	new_item_node.global_position = level_ref.object_layer.map_to_local(pos)
	level_ref.item_grid[pos] = new_item_node
	
	# 2. Inventory Logic
	inventory[item] -= 1
	if inventory[item] <= 0:
		inventory.erase(item)
		
	# 3. Economy Logic (CRITICAL)
	# We are moving item from Storage (Counted) -> Belt (In Transit/Not Counted)
	# So we must SUBTRACT from global economy.
	EconomyManager.remove_resources_from_global({ item.display_name: 1 })
	
	inventory_changed.emit()
	
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
	# We use the item's name (e.g., "Wood") to match the Economy variable
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
	
	# Translate Internal Inventory (ItemResource -> int)
	# Into Economy Format (String -> int)
	for item in inventory:
		if item is ItemResource:
			# Example: We have <Resource:Wood>.
			# We grab its name "Wood" and use that as the key.
			assets[item.display_name] = inventory[item]
			
	return assets
	
# 3. Implement Consumption Logic
func consume_resources(remaining_bill: Dictionary):
	# We iterate over the items we NEED to pay
	# (Use .keys() to duplicate the list so we can modify the dictionary safely)
	var needed_items = remaining_bill.keys()
	
	for resource_name in needed_items:
		var amount_needed = remaining_bill[resource_name]
		
		# Find the item object in our inventory that matches the string name
		var item_ref = _find_item_by_name(resource_name)
		
		if item_ref:
			var amount_we_have = inventory[item_ref]
			var amount_to_take = min(amount_needed, amount_we_have)
			
			# A. Remove from Internal Inventory
			inventory[item_ref] -= amount_to_take
			if inventory[item_ref] <= 0:
				inventory.erase(item_ref)
			
			# B. Update the Bill (Tell Manager we paid this much)
			remaining_bill[resource_name] -= amount_to_take
			if remaining_bill[resource_name] <= 0:
				remaining_bill.erase(resource_name)
	
	inventory_changed.emit()

# Helper to find <Resource:Wood> when given "Wood" string
func _find_item_by_name(name: String) -> ItemResource:
	for item in inventory:
		if item is ItemResource and item.display_name == name:
			return item
	return null
