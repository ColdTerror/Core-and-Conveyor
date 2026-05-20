extends Building
class_name ProcessorBuilding

@export_group("Settings")
@export var recipes: Array[RecipeResource] = [] 
@export var generic_item_scene: PackedScene 

# NEW: 1.5 = 150% time (Slower). 0.8 = 80% time (Faster).
@export var crafting_time_multiplier: float = 1.5

# Recipe State
var current_recipe_index: int = 0
var active_recipe: RecipeResource:
	get:
		if recipes.size() > 0:
			return recipes[current_recipe_index]
		return null

# Buffers
# CHANGED: Input inventory is now a Dictionary mapping ItemResource -> amount
var input_inventory: Dictionary = {} 
var output_inventory: int = 0
@export var buffer_capacity: int = 10 

# State
var work_timer: float = 0.0
var is_working: bool = false
var level_ref: Node2D


# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance

func _ready():
	EconomyManager.register_source(self, false)
	super()
#Log items when destroyed
func die():
	# 1. Log the unrefined ingredients that burn down
	for item_res in input_inventory.keys():
		EconomyManager.log_item_consumed(item_res.display_name, input_inventory[item_res])
	input_inventory.clear()
	
	# 2. Log the finished products that burn down
	if output_inventory > 0 and active_recipe and active_recipe.output_item:
		EconomyManager.log_item_consumed(active_recipe.output_item.display_name, output_inventory)
	output_inventory = 0
	
	super() # Call the base class die() function!
	
# --- INPUT LOGIC (From Conveyors) ---
func accepts_item_at(_tile: Vector2i) -> bool:
	return true

# 2. Unpack the backpack into the correct buffers
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	if not active_recipe: return 0
	
	# --- SCENARIO A: Receiving Finished Products from Memory Limbo ---
	if item_res == active_recipe.output_item:
		var out_space_left = buffer_capacity - output_inventory
		if out_space_left <= 0: return 0
		
		var out_take = min(amount, out_space_left)
		output_inventory += out_take
		inventory_changed.emit()
		return out_take
		
	# --- SCENARIO B: Receiving Raw Ingredients (Normal Delivery or Limbo) ---
	if not active_recipe.inputs.has(item_res): return 0 
	
	var current_stored = input_inventory.get(item_res, 0)
	var space_left = buffer_capacity - current_stored
	
	if space_left <= 0: return 0
	
	var amount_to_take = min(amount, space_left)
	input_inventory[item_res] = current_stored + amount_to_take
	inventory_changed.emit() 
	
	return amount_to_take

func can_accept_item(item_res: ItemResource) -> bool:
	if not active_recipe: return false
	if not active_recipe.inputs.has(item_res): return false 
	
	# Do we have space in the buffer?
	var current_stored = input_inventory.get(item_res, 0)
	return current_stored < buffer_capacity
	
# --- MAIN LOOP ---
func building_tick(delta: float) -> void:
	if not level_ref or not active_recipe: return

	if output_inventory > 0:
		_try_output_item()

	if is_working:
		_process_work(delta)
	else:
		_check_can_start_work()

func _check_can_start_work():
	if not active_recipe: return
	if output_inventory + active_recipe.output_count > buffer_capacity: return

	# 1. Check if we have enough of EVERY required item
	for req_item in active_recipe.inputs:
		var req_amount = active_recipe.inputs[req_item]
		var stored_amount = input_inventory.get(req_item, 0)
		
		if stored_amount < req_amount:
			return # Missing an ingredient! Abort!

	# 2. If we made it here, we have everything! Deduct them all.
	for req_item in active_recipe.inputs:
		var req_amount = active_recipe.inputs[req_item]
		input_inventory[req_item] -= req_amount
		EconomyManager.log_item_consumed(req_item.display_name, req_amount)

	inventory_changed.emit()
	is_working = true
	
	# --- UPDATED: Apply the multiplier to the base recipe time! ---
	work_timer = active_recipe.craft_time * crafting_time_multiplier

func _process_work(delta: float):
	if not active_recipe: return

	work_timer -= delta
	if work_timer <= 0:
		_finish_work()

func _finish_work():
	if not active_recipe: return

	is_working = false
	output_inventory += active_recipe.output_count
	
	EconomyManager.log_item_produced(active_recipe.output_item.display_name, active_recipe.output_count)
	
	inventory_changed.emit()
	_check_can_start_work()

# =================================================================
# UPGRADED: OUTPUT LOGIC (Strict Belts & Filters, Permissive Routers)
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
				
				# 1. Ensure the neighbor can physically accept items
				if neighbor.has_method("accept_item_node"):
					var can_output = false
					
					# --- Catch the Router FIRST so it bypasses the Conveyor rules! ---
					if neighbor is RouterBuilding:
						can_output = true
						
					# 2. STRICT CHECK: Belts and Filters must point exactly away!
					elif neighbor is ConveyorBuilding or neighbor is FilterBuilding:
						if neighbor.direction == offset:
							can_output = true
							
					# 3. ANYTHING ELSE: Magic omnidirectional bypass!
					else:
						can_output = true
							
					# 4. If valid, attempt the transfer
					if can_output:
						if _spawn_item_into_conveyor(neighbor, my_tile, offset):
							return # Success! Stop trying other neighbors this tick.

# --- FIXED: Accepts ANY node that has accept_item_node! ---
func _spawn_item_into_conveyor(receiver: Node, source_tile: Vector2i, direction_offset: Vector2i) -> bool:
	# Safely check that we actually have a valid recipe and output item!
	if not generic_item_scene or not active_recipe or not active_recipe.output_item: return false
	
	# 1. Create the Visual Node
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = active_recipe.output_item
	
	# ========================================
	# FIXED: PERFECT POSITION SNAPPING
	# ========================================
	# 1. Find the exact pixel center of the specific 1x1 tile the item is leaving
	var tile_center_px = level_ref.object_layer.map_to_local(source_tile)
	
	# 2. Push the item exactly 16 pixels (half a tile) in the orthogonal direction
	var edge_px = tile_center_px + (Vector2(direction_offset) * 16.0)
	
	new_item_node.global_position = edge_px
	# ========================================
	
	if new_item_node.has_method("_ready"): new_item_node._ready() 
	
	# 2. Try to hand it to the Receiver (Belt, Router, Filter)
	if receiver.accept_item_node(new_item_node):
		# Success! Processors use output_inventory instead of stored_amount
		output_inventory -= 1
		inventory_changed.emit()
		
		return true # RETURN SUCCESS
		
	else:
		# Receiver was full or refused, delete the temp node
		new_item_node.queue_free()
		return false # RETURN FAILURE


# ==========================================
# HYBRID UPGRADE PIPELINE (Duck Typing)
# ==========================================

# 1. Pack BOTH inventories into the backpack
func get_economy_assets() -> Dictionary:
	var assets = {}
	
	# Pack the raw ingredients
	for item_res in input_inventory.keys():
		if input_inventory[item_res] > 0:
			assets[item_res.display_name] = input_inventory[item_res]
			
	# Pack the finished products
	if output_inventory > 0 and active_recipe and active_recipe.output_item:
		var out_name = active_recipe.output_item.display_name
		# .get() just in case the input and output happen to be the exact same item
		assets[out_name] = assets.get(out_name, 0) + output_inventory 
		
	return assets
	
# --- UI HELPERS ---
func get_inventory_info() -> Dictionary:
	var info = {}
	if active_recipe:
		info["Recipe"] = active_recipe.recipe_name 
		
		for item in input_inventory.keys():
			if input_inventory[item] > 0:
				info[item.display_name] = input_inventory[item]
				
		if output_inventory > 0:
			info[active_recipe.output_item.display_name] = output_inventory
	else:
		info["Status"] = "No Recipe"
		
	return info

func get_progress_ratio() -> float:
	if not is_working or not active_recipe or active_recipe.craft_time == 0:
		return 0.0
		
	# --- UPDATED: Calculate the total modified time to get an accurate percentage ---
	var total_time = active_recipe.craft_time * crafting_time_multiplier
	return 1.0 - (work_timer / total_time)

func cycle_recipe():
	if recipes.size() <= 1: return
	
	if is_working or not input_inventory.is_empty() or output_inventory > 0:
		input_inventory.clear()
		output_inventory = 0
		is_working = false

	current_recipe_index = (current_recipe_index + 1) % recipes.size()
	print("Switched to recipe: " + active_recipe.recipe_name)
	inventory_changed.emit()
	
# ==========================================
# SAVE / LOAD SYSTEM (Processor)
# ==========================================
func get_save_data() -> Dictionary:
	# 1. Grab the base stats (health, building_name)
	var data = super.get_save_data()
	
	# 2. Translate the input inventory (Resources -> Strings)
	var saved_input = {}
	for item_res in input_inventory.keys():
		saved_input[item_res.display_name] = input_inventory[item_res]
	data["input_inventory"] = saved_input
	
	# 3. Save the simple state variables
	data["output_inventory"] = output_inventory
	data["current_recipe_index"] = current_recipe_index
	data["work_timer"] = work_timer
	data["is_working"] = is_working
	
	return data

func load_save_data(data: Dictionary):
	# 1. Restore the base stats
	super.load_save_data(data)
	
	# 2. Restore the simple variables
	output_inventory = data.get("output_inventory", 0)
	current_recipe_index = data.get("current_recipe_index", 0)
	work_timer = data.get("work_timer", 0.0)
	is_working = data.get("is_working", false)
	
	# 3. Rebuild the input inventory using the ItemDatabase
	input_inventory.clear()
	if data.has("input_inventory"):
		var saved_inv = data["input_inventory"]
		for item_name in saved_inv.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				input_inventory[item_res] = int(saved_inv[item_name])
				
	# Tell the UI to update!
	inventory_changed.emit()
