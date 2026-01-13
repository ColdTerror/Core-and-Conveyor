extends Sprite2D

@export var speed = 100.0
var current_direction = Vector2.ZERO
@onready var level_node = get_tree().current_scene 


func _process(delta):
	if not level_node: return
	
	var object_layer = level_node.object_layer
	var current_grid_pos = object_layer.local_to_map(global_position)
	
	# 1. Update our presence in the grid
	level_node.item_grid[current_grid_pos] = self
	
	# 2. Get direction from conveyor
	var move_vec = Vector2.ZERO
	if level_node.active_grid_objects.has(current_grid_pos):
		var data = level_node.active_grid_objects[current_grid_pos]["data"]
		if data.is_conveyor:
			move_vec = data.conveyor_direction

	# 3. PREDICTIVE COLLISION
	# Calculate where we will be AFTER this frame
	var next_pos = global_position + (move_vec * speed * delta)
	var next_grid_pos = object_layer.local_to_map(next_pos)
	
	# 4. If we are changing tiles, check if the target is blocked
	if next_grid_pos != current_grid_pos:
		if level_node.item_grid.has(next_grid_pos):
			# STOP! Snap to the very edge of the current tile so we don't 'bleed' over
			var tile_center = object_layer.map_to_local(current_grid_pos)
			# This math keeps the item exactly inside its current tile
			global_position = tile_center + (move_vec * (level_node.tile_size_px / 2.0))
			return # Exit early so we don't apply movement
	
	# 5. Otherwise, move normally and handle dictionary cleanup
	var old_tile = object_layer.local_to_map(global_position)
	global_position = next_pos
	var new_tile = object_layer.local_to_map(global_position)
	
	if old_tile != new_tile:
		if level_node.item_grid.get(old_tile) == self:
			level_node.item_grid.erase(old_tile)
