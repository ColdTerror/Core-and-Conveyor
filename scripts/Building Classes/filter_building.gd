extends RouterBuilding
class_name FilterBuilding

var filter_options: Array[String] = ["None"] # Will be filled dynamically!
var current_filter_index: int = 0
var is_split_mode: bool = true 
var side_toggle: int = 0

func _ready():
	super()
	
	# Dynamically grab every item from the database!
	for item_name in ItemDatabase.items.keys():
		if not filter_options.has(item_name):
			filter_options.append(item_name)

# ==========================================
# 1. SETUP: Lock the rotation visually!
# ==========================================
func setup(level_instance: Node2D, dir: Vector2i):
	level_ref = level_instance
	direction = dir if dir != Vector2i.ZERO else Vector2i.RIGHT
	rotation = Vector2(direction).angle()

# ==========================================
# 2. THE BOUNCER: Only accept items from the back!
# ==========================================
func accept_item_node(item_node: Node2D, source_belt: ConveyorBuilding = null) -> bool:
	if source_belt:
		var manager = level_ref.building_manager
		var my_grid = manager.object_layer.local_to_map(global_position)
		var source_grid = manager.object_layer.local_to_map(source_belt.global_position)
		
		# Calculate the tile exactly 1 space behind the filter
		var expected_input_grid = my_grid - direction
		
		# If the belt is NOT at the back door, reject the item!
		if source_grid != expected_input_grid:
			return false 
			
	# If it is at the back door, run the normal router acceptance logic
	return super.accept_item_node(item_node, source_belt)

# ==========================================
# UI TOGGLES
# ==========================================
func cycle_filter():
	current_filter_index = (current_filter_index + 1) % filter_options.size()

func toggle_filter_mode():
	is_split_mode = not is_split_mode

# ==========================================
# 3. ROUTING: Clean, predictable math
# ==========================================
func _try_route():
	if not held_item or not "item_data" in held_item: return
	
	var manager = level_ref.building_manager
	var my_grid = manager.object_layer.local_to_map(global_position)
	
	var current_filter = filter_options[current_filter_index]
	var item_name = held_item.item_data.display_name
	var matches_filter = (item_name == current_filter)
	
	# Because we GUARANTEE items only enter from the back, 
	# our outputs are permanently locked to the building's rotation!
	var forward_dir = direction
	var right_dir = Vector2i(-direction.y, direction.x)
	var left_dir = Vector2i(direction.y, -direction.x)
	
	var target_dirs = []
	
	if current_filter == "None":
		target_dirs = [forward_dir]
	else:
		var should_go_to_sides = (matches_filter == is_split_mode)
		
		if should_go_to_sides:
			if side_toggle == 0:
				target_dirs = [right_dir, left_dir]
				side_toggle = 1
			else:
				target_dirs = [left_dir, right_dir]
				side_toggle = 0
		else:
			target_dirs = [forward_dir]

	# Attempt to push
	for offset in target_dirs:
		var target_pos = my_grid + offset
		
		if manager.occupied_tiles.has(target_pos):
			var neighbor = manager.occupied_tiles[target_pos]
			
			if neighbor is ConveyorBuilding and not neighbor is RouterBuilding:
				if neighbor.direction == offset and neighbor.accepts_item_at(Vector2i.ZERO):
					if neighbor.accept_item_node(held_item, self):
						_finish_routing(0)
						return
			elif neighbor is RouterBuilding:
				if neighbor.accepts_item_at(Vector2i.ZERO):
					if neighbor.accept_item_node(held_item, self):
						_finish_routing(0)
						return
			elif neighbor.has_method("add_item"):
				if neighbor.add_item(held_item.item_data, 1) > 0:
					_animate_to_building(held_item, offset)
					return

func _animate_to_building(item, offset):
	is_delivering = true
	var slide_target = global_position + (Vector2(offset) * 16.0)
	var tween = create_tween()
	tween.tween_property(item, "global_position", slide_target, 0.2)
	tween.tween_callback(func():
		if is_instance_valid(item): item.queue_free()
		is_delivering = false
		_finish_routing(0)
	)
	
# ==========================================
# SAVE / LOAD SYSTEM (Filter)
# ==========================================
func get_save_data() -> Dictionary:
	# 1. Grab everything from the Router parent (item, cooldowns, router memory)
	var data = super.get_save_data()
	
	# 2. Save the string name, NOT the index!
	data["active_filter_name"] = filter_options[current_filter_index]
	data["is_split_mode"] = is_split_mode
	data["side_toggle"] = side_toggle
	
	return data

func load_save_data(data: Dictionary):
	# 1. Let the Router unpack the item and base stats
	super.load_save_data(data)
	
	is_split_mode = data.get("is_split_mode", true)
	side_toggle = data.get("side_toggle", 0)
	
	# 2. Safely find the index based on the saved string
	var saved_filter = data.get("active_filter_name", "None")
	var found_index = filter_options.find(saved_filter)
	
	if found_index != -1:
		current_filter_index = found_index
	else:
		# Fallback to "None" just in case you ever delete an item from the game files!
		current_filter_index = 0
