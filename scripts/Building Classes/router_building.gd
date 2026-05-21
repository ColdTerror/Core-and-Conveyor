# ==============================================================================
# Script: Building Classes/router_building.gd
# Purpose: Round-robin splitter node that accepts items from any side and routes them evenly to available output neighbors (belts, routers, or structures), preventing backwards backtracking, and packing delivery port variables into save/load states.
# Dependencies: Inherits ConveyorBuilding. Requires parent level reference level_ref, global Autoloads, and building manager metrics.
# Signals: Emits item_changed (inherited from ConveyorBuilding).
# ==============================================================================
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
	is_moving_to_edge = false # Start in Phase 1 (Moving to center)
	
	# Remember where this came from so we don't accidentally push it backwards!
	if source_belt:
		var source_grid = level_ref.object_layer.local_to_map(source_belt.global_position)
		var my_grid = level_ref.object_layer.local_to_map(global_position)
		input_direction = source_grid - my_grid # e.g., if it came from the left, this is (-1, 0)
	else:
		input_direction = Vector2i.ZERO
	
	# Parenting Logic
	var old_parent = item_node.get_parent()
	if old_parent and old_parent != level_ref:
		old_parent.remove_child(item_node)
	if not item_node.get_parent():
		level_ref.add_child(item_node)
	
	return true

func _process(delta):
	if held_item == null: return
	if not is_instance_valid(held_item):
		held_item = null
		return

	# --- HANDLE COOLDOWN ---
	if push_cooldown > 0:
		push_cooldown -= delta
		return

	# ========================================
	# PHASE 1: Pull to the absolute center
	# ========================================
	if not is_moving_to_edge:
		var target_pos = global_position
		held_item.global_position = held_item.global_position.move_toward(target_pos, current_speed * delta)
		
		# Once it reaches the center, decide where it goes
		if held_item.global_position.distance_to(target_pos) < 1.0:
			held_item.global_position = target_pos # Snap exactly to center
			_try_route()
			
	# ========================================
	# PHASE 2: Push to the chosen edge
	# ========================================
	else:
		var target_pos = global_position + (Vector2(direction) * 16.0)
		
		# Use the base class function to check if the route is still open!
		if not _can_push_to_neighbor():
			is_moving_to_edge = false
			return
			
		held_item.global_position = held_item.global_position.move_toward(target_pos, current_speed * delta)
		
		if held_item.global_position.distance_to(target_pos) < 1.0:
			# Use the base class function to physically push it!
			if _push_to_neighbor():
				pass # Success! (Base class handles clearing held_item)
			else:
				is_moving_to_edge = false

# --- THE SMART ROUTING LOGIC ---

func _try_route():
	var directions = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var manager = level_ref.building_manager
	var my_grid = manager.object_layer.local_to_map(global_position)
	
	# Check all 4 sides in a Round-Robin circle
	for i in range(4):
		var check_idx = (last_output_index + 1 + i) % 4
		var offset = directions[check_idx]
		
		# Skip the side the item came from! No bouncing back.
		if offset == input_direction:
			continue
			
		var target_pos = my_grid + offset
		
		if manager.occupied_tiles.has(target_pos):
			var neighbor = manager.occupied_tiles[target_pos]
			var can_push = false
			
			# CASE A: Output to a normal Conveyor
			if neighbor is ConveyorBuilding and not neighbor is RouterBuilding:
				if neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed):
					can_push = true
						
			# CASE B: Output to another Router (Routers can feed Routers!)
			elif neighbor is RouterBuilding:
				if neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed):
					can_push = true
			# CASE C: Output to Factory/Stockpile
			elif neighbor.has_method("can_accept_item") and "item_data" in held_item:
				# --- FIXED: Only route here if the building confirms it has space! ---
				if neighbor.can_accept_item(held_item.item_data):
					can_push = true
				
			if can_push:
				# --- THE FIX: Transition to Phase 2 ---
				direction = offset # Temporarily use the inherited direction variable!
				is_moving_to_edge = true 
				last_output_index = check_idx
				return
				# --------------------------------------
				
	# If all valid outputs are blocked, pause briefly before checking again
	push_cooldown = 0.1
	
# SAVE / LOAD SYSTEM (Router)
func get_save_data() -> Dictionary:
	# Grab everything from the Conveyor parent (including the physical item!)
	var data = super.get_save_data()
	
	# Add the Router's unique memory
	data["last_output_index"] = last_output_index
	data["input_direction"] = var_to_str(input_direction)
	
	# Note: We removed data["is_delivering"]!
	
	return data

func load_save_data(data: Dictionary):
	# Let the Conveyor script unpack the item, rotation, and base stats
	super.load_save_data(data)
	
	# Restore the Router's memory
	last_output_index = data.get("last_output_index", 0)
	
	if data.has("input_direction"):
		input_direction = str_to_var(data["input_direction"])
	else:
		input_direction = Vector2i.ZERO
