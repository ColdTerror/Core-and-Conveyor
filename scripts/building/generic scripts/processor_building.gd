extends Building
class_name ProcessorBuilding

@export_group("Settings")
# CHANGE: Now an Array to support switching (e.g. Wood Arrow -> Stone Arrow)
@export var recipes: Array[RecipeResource] = [] 
@export var generic_item_scene: PackedScene # Reference to GenericItem.tscn

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
@export var buffer_limit: int = 10 # Max items for both input and output

# State
var work_timer: float = 0.0
var is_working: bool = false
var level_ref: Node2D

signal processing_tick(progress_ratio) # Optional: For a progress bar UI later

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance

# --- INPUT LOGIC (From Conveyors) ---

# 1. Override base default: Yes, we accept items generally
func accepts_item_at(_tile: Vector2i) -> bool:
	return true

# 2. Specific Check: Do we want THIS item right now?
func can_accept_item(item: ItemResource) -> bool:
	if not active_recipe: return false
	
	# Only accept ingredients for the ACTIVE recipe
	if item != active_recipe.input_item: return false
	
	# Check buffer space
	if input_inventory >= buffer_limit: return false
	
	return true

# 3. Take the item
func accept_item(item: ItemResource) -> bool:
	if not can_accept_item(item): return false
	
	input_inventory += 1
	inventory_changed.emit() # Updates UI
	return true

# --- MAIN LOOP ---
func building_tick(delta: float) -> void:
	if not level_ref or not active_recipe: return

	# 1. Attempt to Output (Always try to empty the output buffer)
	if output_inventory > 0:
		_try_output_item()

	# 2. Work Logic
	if is_working:
		_process_work(delta)
	else:
		_check_can_start_work()

func _check_can_start_work():
	if not active_recipe: return

	# Conditions to start:
	# 1. Have enough ingredients?
	# 2. Have space for output?
	if input_inventory >= active_recipe.input_count and output_inventory < buffer_limit:
		# Consume Input
		input_inventory -= active_recipe.input_count
		inventory_changed.emit()
		
		# Start Timer
		is_working = true
		work_timer = active_recipe.craft_time

func _process_work(delta: float):
	if not active_recipe: return

	work_timer -= delta
	
	# Optional: Emit signal if needed, though UI polls get_progress_ratio() usually
	# var progress = 1.0 - (work_timer / active_recipe.craft_time)
	# processing_tick.emit(progress) 

	if work_timer <= 0:
		_finish_work()

func _finish_work():
	if not active_recipe: return

	is_working = false
	output_inventory += active_recipe.output_count
	inventory_changed.emit()
	
	# Immediately try to start next job
	_check_can_start_work()

# =================================================================
# UPDATED: OUTPUT LOGIC (Now using ConveyorBuilding Nodes)
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
					# Try to output to this conveyor
					# If successful, return. If not, continue to next neighbor
					if _spawn_item_into_conveyor(neighbor):
						return # Successfully outputted, stop here
					# If it failed, loop continues to try next neighbor

func _spawn_item_into_conveyor(conveyor: ConveyorBuilding) -> bool:
	if not generic_item_scene or not active_recipe: return false
	
	# 1. Create the Visual Node
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = active_recipe.output_item
	
	# Position the item at the processor's location before handoff
	new_item_node.global_position = global_position
	
	if new_item_node.has_method("_ready"): new_item_node._ready()
	
	# 2. Try to hand it to the Conveyor
	if conveyor.accept_item_node(new_item_node):
		# Success!
		output_inventory -= 1
		inventory_changed.emit()
		return true # Success!
	else:
		# Belt was full or refused, delete the temp node
		new_item_node.queue_free()
		return false # Failed, try next conveyor

# =================================================================

# --- UI HELPERS ---

func get_inventory_info() -> Dictionary:
	var info = {}
	if active_recipe:
		info["Recipe"] = active_recipe.recipe_name # Show active recipe name
		
		if input_inventory > 0:
			info[active_recipe.input_item.display_name] = input_inventory
		if output_inventory > 0:
			info[active_recipe.output_item.display_name] = output_inventory
	else:
		info["Status"] = "No Recipe"
		
	return info

# Used by the Progress Bar in UI
func get_progress_ratio() -> float:
	if not is_working or not active_recipe or active_recipe.craft_time == 0:
		return 0.0
	return 1.0 - (work_timer / active_recipe.craft_time)

# Call this from a UI button to switch arrows/products
func cycle_recipe():
	if recipes.size() <= 1: return
	
	# Empty buffers and set working to false
	if is_working or input_inventory > 0 or output_inventory > 0:
		input_inventory = 0
		output_inventory = 0
		is_working = false

	current_recipe_index = (current_recipe_index + 1) % recipes.size()
	print("Switched to recipe: " + active_recipe.recipe_name)
	inventory_changed.emit()
