extends RouterBuilding
class_name FilterBuilding


# The items we can cycle through (You can expand this later!)
var filter_options: Array[String] = ["None", "Wood", "Stone"]
var current_filter_index: int = 0

var side_toggle: int = 0 # Used to alternate left/right when filtering


# Called when the player clicks on this building with the default interaction tool
func cycle_filter():
	current_filter_index = (current_filter_index + 1) % filter_options.size()

# --- OVERRIDE THE ROUTER LOGIC ---
func _try_route():
	if not held_item or not "item_data" in held_item: return
	
	var manager = level_ref.building_manager
	var my_grid = manager.object_layer.local_to_map(global_position)
	
	var current_filter = filter_options[current_filter_index]
	var item_name = held_item.item_data.display_name
	var is_filtered = (item_name == current_filter)
	
	# Failsafe: If a bot dropped it directly, assume it came from the bottom
	var safe_input = input_direction
	if safe_input == Vector2i.ZERO:
		safe_input = Vector2i.DOWN
		
	# Relative Direction Math
	var forward_dir = -safe_input
	var right_dir = Vector2i(-safe_input.y, safe_input.x)
	var left_dir = Vector2i(safe_input.y, -safe_input.x)
	
	var target_dirs = []
	
	if current_filter == "None":
		# If no filter is set, act like a normal straight belt
		target_dirs = [forward_dir]
	elif is_filtered:
		# If it matches the filter, kick it out to the sides (Round-Robin)
		if side_toggle == 0:
			target_dirs = [right_dir, left_dir]
			side_toggle = 1
		else:
			target_dirs = [left_dir, right_dir]
			side_toggle = 0
	else:
		# Unfiltered items go straight through
		target_dirs = [forward_dir]
		
	# Try to push to the chosen directions
	for offset in target_dirs:
		var target_pos = my_grid + offset
		
		if manager.occupied_tiles.has(target_pos):
			var neighbor = manager.occupied_tiles[target_pos]
			
			# CASE A: Output to Conveyor
			if neighbor is ConveyorBuilding and not neighbor is RouterBuilding:
				if neighbor.direction == offset and neighbor.accepts_item_at(Vector2i.ZERO):
					if neighbor.accept_item_node(held_item, self):
						_finish_routing(0)
						return
						
			# CASE B: Output to Router/Filter
			elif neighbor is RouterBuilding:
				if neighbor.accepts_item_at(Vector2i.ZERO):
					if neighbor.accept_item_node(held_item, self):
						_finish_routing(0)
						return
						
			# CASE C: Output to Factory
			elif neighbor.has_method("add_item"):
				if neighbor.add_item(held_item.item_data, 1) > 0:
					is_delivering = true
					var slide_target = global_position + (Vector2(offset) * 16.0)
					var tween = create_tween()
					tween.tween_property(held_item, "global_position", slide_target, 0.2)
					tween.tween_callback(func():
						if is_instance_valid(held_item):
							held_item.queue_free()
						is_delivering = false
						_finish_routing(0)
					)
					return
