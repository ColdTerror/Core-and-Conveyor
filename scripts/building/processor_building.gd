extends Building
class_name ProcessorBuilding

@export_group("Settings")
@export var recipe: RecipeResource
@export var generic_item_scene: PackedScene # Reference to GenericItem.tscn

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
# Override the generic check from Item.gd
func accepts_item_at(_tile: Vector2i) -> bool:
	return true

# Check if the item matches our recipe AND we have space
func can_accept_item(item: ItemResource) -> bool:
	if not recipe: return false
	if item != recipe.input_item: return false
	if input_inventory >= buffer_limit: return false
	return true

func accept_item(item: ItemResource) -> bool:
	if not can_accept_item(item): return false
	
	input_inventory += 1
	inventory_changed.emit() # Updates UI
	return true

# --- MAIN LOOP ---
func building_tick(delta: float) -> void:
	if not level_ref or not recipe: return

	# 1. Attempt to Output (Always try to empty the output buffer)
	if output_inventory > 0:
		_try_output_item()

	# 2. Work Logic
	if is_working:
		_process_work(delta)
	else:
		_check_can_start_work()

func _check_can_start_work():
	# Conditions to start:
	# 1. Have enough ingredients?
	# 2. Have space for output?
	if input_inventory >= recipe.input_count and output_inventory < buffer_limit:
		# Consume Input
		input_inventory -= recipe.input_count
		inventory_changed.emit()
		
		# Start Timer
		is_working = true
		work_timer = recipe.craft_time

func _process_work(delta: float):
	work_timer -= delta
	
	# Optional: Emit signal for progress bars
	var progress = 1.0 - (work_timer / recipe.craft_time)
	processing_tick.emit(progress) 

	if work_timer <= 0:
		_finish_work()

func _finish_work():
	is_working = false
	output_inventory += recipe.output_count
	inventory_changed.emit()
	print("Crafted %s! Output buffer: %d" % [recipe.output_item.display_name, output_inventory])
	
	# Immediately try to start next job
	_check_can_start_work()

# --- OUTPUT LOGIC (Same as Harvester) ---
func _try_output_item():
	for my_tile in occupied_tiles:
		# These are the directions we are "pushing" items out to
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			# 1. Standard Checks (Don't output into myself or blocked tiles)
			if occupied_tiles.has(target_pos): continue
			if level_ref.item_grid.has(target_pos): continue 
			
			# 2. Check Grid Data
			if level_ref.active_grid_objects.has(target_pos):
				var info = level_ref.active_grid_objects[target_pos]
				var data = info["data"]
				
				# 3. Is it a Conveyor?
				if data.is_conveyor:
					# 4. CRITICAL: Check Direction
					# We retrieve the specific direction stored in the grid dictionary
					# (Make sure Level.gd place_tile is saving "direction" correctly!)
					var conveyor_dir = info.get("direction", Vector2.ZERO)
					
					# We want the conveyor to be moving in the SAME direction we are pushing.
					# offset is our push direction (e.g. (1, 0) for Right)
					# conveyor_dir is the belt's movement (e.g. (1, 0) for Right)
					
					# Note: We cast offset to Vector2 to match conveyor_dir type
					if conveyor_dir == Vector2(offset):
						_spawn_output(target_pos)
						return # Success!

func _spawn_output(target_pos: Vector2i):
	if not generic_item_scene or not recipe.output_item: return

	var new_item = generic_item_scene.instantiate()
	
	if new_item.has_method("setup"): new_item.setup(level_ref)
	
	if "item_data" in new_item:
		new_item.item_data = recipe.output_item
		if new_item.has_method("_ready"): new_item._ready()

	level_ref.add_child(new_item)
	new_item.global_position = level_ref.object_layer.map_to_local(target_pos)
	
	output_inventory -= 1
	level_ref.item_grid[target_pos] = new_item
	inventory_changed.emit()

func _is_conveyor_at(grid_pos: Vector2i) -> bool:
	if level_ref.active_grid_objects.has(grid_pos):
		return level_ref.active_grid_objects[grid_pos]["data"].is_conveyor
	return false

# --- UI INFO ---
func get_inventory_info() -> Dictionary:
	var info = {}
	if recipe:
		if input_inventory > 0:
			info["In: " + recipe.input_item.display_name] = input_inventory
		if output_inventory > 0:
			info["Out: " + recipe.output_item.display_name] = output_inventory
	return info
	
# Returns a value between 0.0 (0%) and 1.0 (100%)
func get_progress_ratio() -> float:
	if not is_working or not recipe or recipe.craft_time == 0:
		return 0.0
	return 1.0 - (work_timer / recipe.craft_time)
