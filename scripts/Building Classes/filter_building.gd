extends RouterBuilding
class_name FilterBuilding

# --- NEW STATE ---
var filter_options: Array[String] = ["None", "Wood", "Stone", "Plank", "Stone Brick", "Wooden Arrow", "Stone Arrow"]
var current_filter_index: int = 0

# true = Filtered items go SIDES, others go FORWARD
# false = Filtered items go FORWARD, others go SIDES
var is_split_mode: bool = true 

var side_toggle: int = 0

# --- OVERRIDES ---

func setup(level_instance: Node2D, dir: Vector2i):
	level_ref = level_instance
	# We NO LONGER set direction to ZERO. We use the placement rotation!
	direction = dir if dir != Vector2i.ZERO else Vector2i.RIGHT
	rotation = Vector2(direction).angle()

func cycle_filter():
	current_filter_index = (current_filter_index + 1) % filter_options.size()

func toggle_filter_mode():
	is_split_mode = not is_split_mode

# --- SMART FIXED-DIRECTION LOGIC ---
func _try_route():
	if not held_item or not "item_data" in held_item: return
	
	var manager = level_ref.building_manager
	var my_grid = manager.object_layer.local_to_map(global_position)
	
	var current_filter = filter_options[current_filter_index]
	var item_name = held_item.item_data.display_name
	var matches_filter = (item_name == current_filter)
	
	# Fixed directions based on the building's rotation
	var forward_dir = direction
	var right_dir = Vector2i(-direction.y, direction.x)
	var left_dir = Vector2i(direction.y, -direction.x)
	var back_dir = -direction
	
	var target_dirs = []
	
	if current_filter == "None":
		# No filter? Just act like a 3-to-1 joiner and pass everything forward
		target_dirs = [forward_dir]
	else:
		# If SPLIT mode: Filtered -> Sides, Others -> Forward
		# If SEND mode:  Filtered -> Forward, Others -> Sides
		var should_go_to_sides = (matches_filter == is_split_mode)
		
		if should_go_to_sides:
			# Round-robin between left and right
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
		
		# Prevent pushing back onto an input belt (even if it's the "side")
		if offset == input_direction: continue 

		if manager.occupied_tiles.has(target_pos):
			var neighbor = manager.occupied_tiles[target_pos]
			
			if neighbor is ConveyorBuilding and not neighbor is RouterBuilding:
				# Only push to conveyors if they aren't pointing INTO us
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
