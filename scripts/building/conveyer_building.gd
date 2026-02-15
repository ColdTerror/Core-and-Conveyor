extends Building
class_name ConveyorBuilding

@export var speed: float = 64.0 
var direction: Vector2i = Vector2i.RIGHT 

var held_item: Node2D = null 
var level_ref: Node2D

# State to track if we are waiting at the middle
var is_moving_to_edge: bool = false 

func setup(level_instance: Node2D, dir: Vector2i):
	level_ref = level_instance
	direction = dir
	rotation = Vector2(dir).angle()

# --- INPUT ---
func accepts_item_at(_tile: Vector2i) -> bool:
	return held_item == null

func accept_item_node(item_node: Node2D) -> bool:
	if held_item != null: return false
	
	held_item = item_node
	is_moving_to_edge = false # Reset state logic
	
	# --- THE FIX ---
	var old_parent = item_node.get_parent()
	
	if old_parent:
		# Case A: Moving from another belt (already has a parent)
		if old_parent != level_ref:
			old_parent.remove_child(item_node)
			level_ref.add_child(item_node)
	else:
		# Case B: Freshly spawned (has no parent)
		level_ref.add_child(item_node)
	# ---------------
	
	# Snap Check: If it's too far away (teleporting), snap to our "Back Edge"
	var back_edge = global_position - (Vector2(direction) * 16.0)
	if item_node.global_position.distance_to(back_edge) > 32:
		item_node.global_position = back_edge
		
	return true
# --- MOVEMENT LOOP ---
func _process(delta):
	if held_item == null: return
	
	var target_pos = Vector2.ZERO
	
	if not is_moving_to_edge:
		# PHASE 1: Move to Center
		target_pos = global_position
		
		# Move
		var move_step = speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		# Check Arrival
		if held_item.global_position.distance_to(target_pos) < 1.0:
			# We are at center! Check if we can proceed.
			if _can_push_to_neighbor():
				is_moving_to_edge = true
			else:
				# Neighbor is full/blocked. Stay here.
				pass
				
	else:
		# PHASE 2: Move to Edge
		# Target is 16px in front (The Handoff Point)
		target_pos = global_position + (Vector2(direction) * 16.0)
		
		# Move
		var move_step = speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		# Check Arrival at Edge
		if held_item.global_position.distance_to(target_pos) < 1.0:
			# Try to actually hand it over now
			if _push_to_neighbor():
				pass # Success! Item is gone.
			else:
				# Failed (Neighbor filled up while we were walking).
				# Go back to waiting state.
				is_moving_to_edge = false

# --- NEIGHBOR CHECKS ---

# Just CHECKS if the neighbor is open (Does not move item)
func _can_push_to_neighbor() -> bool:
	var neighbor = _get_neighbor()
	if not neighbor: return false
	
	# 1. Check Conveyors
	if neighbor is ConveyorBuilding:
		return neighbor.accepts_item_at(Vector2i.ZERO) # Vector2i.ZERO is dummy arg
		
	# 2. Check Buildings (Stockpiles/Factories)
	if neighbor.has_method("can_accept_item"):
		# We assume we have item_data on the node
		if "item_data" in held_item:
			return neighbor.can_accept_item(held_item.item_data)
			
	return false

# Actually MOVES the item
func _push_to_neighbor() -> bool:
	var neighbor = _get_neighbor()
	if not neighbor: return false
	
	if neighbor is ConveyorBuilding:
		if neighbor.accept_item_node(held_item):
			held_item = null
			return true
			
	elif neighbor.has_method("accept_item"):
		if "item_data" in held_item:
			if neighbor.accept_item(held_item.item_data):
				held_item.queue_free()
				held_item = null
				return true
	return false

func _get_neighbor() -> Node:
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	var neighbor_grid = my_grid + direction
	var manager = level_ref.building_manager
	
	if manager.occupied_tiles.has(neighbor_grid):
		return manager.occupied_tiles[neighbor_grid]
	return null
