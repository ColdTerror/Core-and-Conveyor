extends ConveyorBuilding
class_name RouterBuilding

# Tracks the last port used so we can distribute evenly (Round-Robin)
var last_output_index: int = 0

# Tracks where the current item came from so we don't spit it back out
var input_direction: Vector2i = Vector2i.ZERO

# --- OVERRIDES ---

func setup(level_instance: Node2D, _dir: Vector2i):
	level_ref = level_instance
	# Routers are omni-directional, so we ignore the rotation/direction passed to us
	direction = Vector2i.ZERO 
	rotation = 0

func accept_item_node(item_node: Node2D, source_belt: ConveyorBuilding = null) -> bool:
	if held_item != null or not level_ref: 
		return false
	
	held_item = item_node
	
	# Remember where this came from so we don't accidentally push it backwards!
	if source_belt:
		var source_grid = level_ref.object_layer.local_to_map(source_belt.global_position)
		var my_grid = level_ref.object_layer.local_to_map(global_position)
		input_direction = source_grid - my_grid # e.g., if it came from the left, this is (-1, 0)
	else:
		input_direction = Vector2i.ZERO
	
	# Parenting Logic (Same as normal belt)
	var old_parent = item_node.get_parent()
	if old_parent and old_parent != level_ref:
		old_parent.remove_child(item_node)
	if not item_node.get_parent():
		level_ref.add_child(item_node)
	
	# Notice we DON'T snap to the edge here. 
	# We let the item glide smoothly from the previous belt directly into the center.
	return true

func _process(delta):
	if is_delivering: return
	
	if held_item == null: return
	if not is_instance_valid(held_item):
		held_item = null
		return

	# Always pull the item to the absolute center of the router
	var target_pos = global_position
	held_item.global_position = held_item.global_position.move_toward(target_pos, speed * delta)
	
	# Once it reaches the center, decide where it goes
	if held_item.global_position.distance_to(target_pos) < 1.0:
		held_item.global_position = target_pos # Snap exactly to center
		_try_route()

# --- THE SMART ROUTING LOGIC ---

func _try_route():
	var directions = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var manager = level_ref.building_manager
	var my_grid = manager.object_layer.local_to_map(global_position)
	
	# Check all 4 sides in a Round-Robin circle
	for i in range(4):
		var check_idx = (last_output_index + 1 + i) % 4
		var offset = directions[check_idx]
		
		# 1. Skip the side the item came from! No bouncing back.
		if offset == input_direction:
			continue
			
		var target_pos = my_grid + offset
		
		if manager.occupied_tiles.has(target_pos):
			var neighbor = manager.occupied_tiles[target_pos]
			
			# CASE A: Output to a normal Conveyor
			if neighbor is ConveyorBuilding and not neighbor is RouterBuilding:
				# Only output if the belt is pointing AWAY from the router
				if neighbor.direction == offset:
					if neighbor.accepts_item_at(Vector2i.ZERO):
						if neighbor.accept_item_node(held_item, self):
							_finish_routing(check_idx)
							return
							
			# CASE B: Output to another Router (Routers can feed Routers!)
			elif neighbor is RouterBuilding:
				if neighbor.accepts_item_at(Vector2i.ZERO):
					if neighbor.accept_item_node(held_item, self):
						_finish_routing(check_idx)
						return
						
			# CASE C: Output to Factory/Stockpile
			elif neighbor.has_method("add_item") and "item_data" in held_item:
				
				# Try to give the building 1 item. If it returns > 0, it took it!
				if neighbor.add_item(held_item.item_data, 1) > 0:
					
					# --- THE FIX: Animate instead of teleporting ---
					is_delivering = true # Lock the router!
					
					# Slide it in the direction of the offset we are currently checking
					var slide_target = global_position + (Vector2(offset) * 16.0)
					var tween = create_tween()
					tween.tween_property(held_item, "global_position", slide_target, 0.2)
					
					# Wait for the animation to finish before cleaning up
					tween.tween_callback(func():
						if is_instance_valid(held_item):
							held_item.queue_free()
						is_delivering = false # Unlock the router
						_finish_routing(check_idx) # Clear the held_item and update the index
					)
					return
					# -----------------------------------------------

func _finish_routing(index_used: int):
	held_item = null
	last_output_index = index_used
	
# ==========================================
# SAVE / LOAD SYSTEM (Router)
# ==========================================
func get_save_data() -> Dictionary:
	# 1. Grab everything from the Conveyor parent (including the physical item!)
	var data = super.get_save_data()
	
	# 2. Add the Router's unique memory
	data["last_output_index"] = last_output_index
	data["input_direction"] = var_to_str(input_direction)
	
	return data

func load_save_data(data: Dictionary):
	# 1. Let the Conveyor script unpack the item, rotation, and base stats
	super.load_save_data(data)
	
	# 2. Restore the Router's memory
	last_output_index = data.get("last_output_index", 0)
	
	if data.has("input_direction"):
		input_direction = str_to_var(data["input_direction"])
	else:
		input_direction = Vector2i.ZERO
