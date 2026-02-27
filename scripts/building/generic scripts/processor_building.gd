extends Building
class_name ProcessorBuilding

@export_group("Settings")
@export var recipes: Array[RecipeResource] = [] 
@export var generic_item_scene: PackedScene 

# Recipe State
var current_recipe_index: int = 0
var active_recipe: RecipeResource:
	get:
		if recipes.size() > 0:
			return recipes[current_recipe_index]
		return null

# Buffers
var input_inventory: int = 0
var output_inventory: int = 0
@export var buffer_limit: int = 10 

# State
var work_timer: float = 0.0
var is_working: bool = false
var level_ref: Node2D

signal processing_tick(progress_ratio)

# =================================================================
# NEW: ECONOMY REGISTRATION
# =================================================================
func _ready():
	super()
	EconomyManager.register_source(self)

func _exit_tree():
	EconomyManager.unregister_source(self)
# =================================================================

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance

# --- INPUT LOGIC (From Conveyors) ---
func accepts_item_at(_tile: Vector2i) -> bool:
	return true

func can_accept_item(item: ItemResource) -> bool:
	if not active_recipe: return false
	if item != active_recipe.input_item: return false
	if input_inventory >= buffer_limit: return false
	return true

func accept_item(item: ItemResource) -> bool:
	if not can_accept_item(item): return false
	
	input_inventory += 1
	
	# --- ECONOMY FIX: Item arrived from belt into storage ---
	EconomyManager.add_resources(item.display_name, 1)
	# --------------------------------------------------------
	
	inventory_changed.emit() 
	return true

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

	if input_inventory >= active_recipe.input_count and (output_inventory + active_recipe.output_count) <= buffer_limit:
		input_inventory -= active_recipe.input_count
		
		# --- ECONOMY FIX: Inputs are being destroyed/converted ---
		var dict = { active_recipe.input_item.display_name: active_recipe.input_count }
		EconomyManager.remove_resources_from_global(dict)
		# ---------------------------------------------------------
		
		inventory_changed.emit()
		is_working = true
		work_timer = active_recipe.craft_time

func _process_work(delta: float):
	if not active_recipe: return

	work_timer -= delta
	if work_timer <= 0:
		_finish_work()

func _finish_work():
	if not active_recipe: return

	is_working = false
	output_inventory += active_recipe.output_count
	
	# --- ECONOMY FIX: New item has been created! Tell the UI! ---
	EconomyManager.add_resources(active_recipe.output_item.display_name, active_recipe.output_count)
	# ------------------------------------------------------------
	
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
		
		# --- ECONOMY FIX: Item left storage onto belt ---
		var dict = { active_recipe.output_item.display_name: 1 }
		EconomyManager.remove_resources_from_global(dict)
		# ------------------------------------------------
		
		inventory_changed.emit()
		return true 
	else:
		new_item_node.queue_free()
		return false 

# =================================================================
# NEW: CONSUMPTION LOGIC (Allows spending from Processor buffers)
# =================================================================
func consume_resources(remaining_bill: Dictionary):
	if not active_recipe: return
	
	# Try to pay using Inputs
	var in_name = active_recipe.input_item.display_name
	if remaining_bill.has(in_name):
		var take = min(remaining_bill[in_name], input_inventory)
		input_inventory -= take
		remaining_bill[in_name] -= take
		if remaining_bill[in_name] <= 0: remaining_bill.erase(in_name)
			
	# Try to pay using Outputs
	var out_name = active_recipe.output_item.display_name
	if remaining_bill.has(out_name):
		var take = min(remaining_bill[out_name], output_inventory)
		output_inventory -= take
		remaining_bill[out_name] -= take
		if remaining_bill[out_name] <= 0: remaining_bill.erase(out_name)
			
	inventory_changed.emit()

func get_economy_assets() -> Dictionary:
	var assets = {}
	if active_recipe:
		if input_inventory > 0:
			assets[active_recipe.input_item.display_name] = input_inventory
		if output_inventory > 0:
			assets[active_recipe.output_item.display_name] = output_inventory
	return assets
# =================================================================

# --- UI HELPERS ---
func get_inventory_info() -> Dictionary:
	var info = {}
	if active_recipe:
		info["Recipe"] = active_recipe.recipe_name 
		
		if input_inventory > 0:
			info[active_recipe.input_item.display_name] = input_inventory
		if output_inventory > 0:
			info[active_recipe.output_item.display_name] = output_inventory
	else:
		info["Status"] = "No Recipe"
		
	return info

func get_progress_ratio() -> float:
	if not is_working or not active_recipe or active_recipe.craft_time == 0:
		return 0.0
	return 1.0 - (work_timer / active_recipe.craft_time)

func cycle_recipe():
	if recipes.size() <= 1: return
	
	if is_working or input_inventory > 0 or output_inventory > 0:
		# --- ECONOMY FIX: Void the existing items before clearing buffers ---
		var lost_assets = get_economy_assets()
		if not lost_assets.is_empty():
			EconomyManager.remove_resources_from_global(lost_assets)
		# ------------------------------------------------------------------
		
		input_inventory = 0
		output_inventory = 0
		is_working = false

	current_recipe_index = (current_recipe_index + 1) % recipes.size()
	print("Switched to recipe: " + active_recipe.recipe_name)
	inventory_changed.emit()
