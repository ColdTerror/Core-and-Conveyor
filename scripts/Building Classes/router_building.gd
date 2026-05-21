# ==============================================================================
# Script: Building Classes/router_building.gd
# Purpose: Round-robin splitter node that accepts items from any side and routes them evenly to available output neighbors (belts, routers, or structures), preventing backwards backtracking, and packing delivery port variables into save/load states.
# Dependencies: Inherits ConveyorBuilding. Requires parent level reference level_ref, global Autoloads, and building manager metrics.
# Signals: Emits item_changed (inherited from ConveyorBuilding).
# ==============================================================================
extends ConveyorBuilding
class_name RouterBuilding

var last_output_index: int = 0
var input_direction: Vector2i = Vector2i.ZERO


## Configures the router with the active level reference, keeping visual orientation neutral.
func setup(level_instance: Node2D, _dir: Vector2i):
	level_ref = level_instance
	direction = Vector2i.ZERO 
	rotation = 0



## Welcomes an incoming item node and tracks its entry vector to avoid routing it backwards.
func accept_item_node(item_node: Node2D, source_belt: ConveyorBuilding = null) -> bool:
	if held_item != null or not level_ref: 
		return false
	
	held_item = item_node
	is_moving_to_edge = false
	
	if source_belt:
		var source_grid = level_ref.object_layer.local_to_map(source_belt.global_position)
		var my_grid = level_ref.object_layer.local_to_map(global_position)
		input_direction = source_grid - my_grid
	else:
		input_direction = Vector2i.ZERO
	
	var old_parent = item_node.get_parent()
	if old_parent and old_parent != level_ref:
		old_parent.remove_child(item_node)
	if not item_node.get_parent():
		level_ref.add_child(item_node)
	
	return true



## Moves held items to the absolute center before calling routing selectors.
func _process(delta):
	if held_item == null: return
	if not is_instance_valid(held_item):
		held_item = null
		return

	if push_cooldown > 0:
		push_cooldown -= delta
		return

	# PHASE 1: Pull to the absolute center
	if not is_moving_to_edge:
		var target_pos = global_position
		held_item.global_position = held_item.global_position.move_toward(target_pos, current_speed * delta)
		
		if held_item.global_position.distance_to(target_pos) < 1.0:
			held_item.global_position = target_pos
			_try_route()
			
	# PHASE 2: Push to the chosen edge
	else:
		var target_pos = global_position + (Vector2(direction) * 16.0)
		
		if not _can_push_to_neighbor():
			is_moving_to_edge = false
			return
			
		held_item.global_position = held_item.global_position.move_toward(target_pos, current_speed * delta)
		
		if held_item.global_position.distance_to(target_pos) < 1.0:
			if _push_to_neighbor():
				pass
			else:
				is_moving_to_edge = false



## Scans output directions in a round-robin loop to find vacant output receptors.
func _try_route():
	var directions = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var manager = level_ref.building_manager
	var my_grid = manager.object_layer.local_to_map(global_position)
	
	for i in range(4):
		var check_idx = (last_output_index + 1 + i) % 4
		var offset = directions[check_idx]
		
		if offset == input_direction:
			continue
			
		var target_pos = my_grid + offset
		
		if manager.occupied_tiles.has(target_pos):
			var neighbor = manager.occupied_tiles[target_pos]
			var can_push = false
			
			if neighbor is ConveyorBuilding and not neighbor is RouterBuilding:
				if neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed):
					can_push = true
						
			elif neighbor is RouterBuilding:
				if neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed):
					can_push = true
					
			elif neighbor.has_method("can_accept_item") and "item_data" in held_item:
				if neighbor.can_accept_item(held_item.item_data):
					can_push = true
				
			if can_push:
				direction = offset
				is_moving_to_edge = true 
				last_output_index = check_idx
				return
				
	push_cooldown = 0.1



## Packs current round-robin indexes and last entry directions for save files.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	data["last_output_index"] = last_output_index
	data["input_direction"] = var_to_str(input_direction)
	
	return data


## Restores saved round-robin indexes and entry direction configurations.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	last_output_index = data.get("last_output_index", 0)
	
	if data.has("input_direction"):
		input_direction = str_to_var(data["input_direction"])
	else:
		input_direction = Vector2i.ZERO
