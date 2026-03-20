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

#signal processing_tick(progress_ratio)

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance

# --- INPUT LOGIC (From Conveyors) ---
func accepts_item_at(_tile: Vector2i) -> bool:
	return true

func add_item(item_res: ItemResource, amount: int = 1) -> int:
	# 1. Filter: Reject if no recipe or wrong item
	if not active_recipe: return 0
	if not active_recipe.inputs.has(item_res): return 0 
	
	# 2. Capacity: Is the buffer full for this specific item?
	var current_stored = input_inventory.get(item_res, 0)
	var space_left = buffer_capacity - current_stored
	
	if space_left <= 0: return 0
	
	# 3. Math: Take the items!
	var amount_to_take = min(amount, space_left)
	
	input_inventory[item_res] = current_stored + amount_to_take
	inventory_changed.emit() 
	
	return amount_to_take
	

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
	
	inventory_changed.emit()
	_check_can_start_work()

# --- OUTPUT LOGIC ---
func _try_output_item():
	if not level_ref: return
	var manager = level_ref.building_manager

	for my_tile in occupied_tiles:
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			if occupied_tiles.has(target_pos): continue
			
			if manager.occupied_tiles.has(target_pos):
				var neighbor = manager.occupied_tiles[target_pos]
				
				if neighbor is ConveyorBuilding:
					if neighbor.direction == offset:
						if _spawn_item_into_conveyor(neighbor):
							return 

func _spawn_item_into_conveyor(conveyor: ConveyorBuilding) -> bool:
	if not generic_item_scene or not active_recipe: return false
	
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = active_recipe.output_item
	
	new_item_node.global_position = global_position
	
	if new_item_node.has_method("_ready"): new_item_node._ready()
	
	if conveyor.accept_item_node(new_item_node):
		output_inventory -= 1
		inventory_changed.emit()
		return true 
	else:
		new_item_node.queue_free()
		return false 



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
