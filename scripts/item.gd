extends Sprite2D

@export var speed = 100.0
@onready var level_node = get_tree().current_scene

var stopped = false  # Tracks if item is blocked or finished conveyor

func _process(delta):
	if not level_node:
		return

	var object_layer = level_node.object_layer
	var current_grid_pos = object_layer.local_to_map(global_position)

	# ---- CLAIM CURRENT TILE SAFELY ----
	if level_node.item_grid.has(current_grid_pos):
		if level_node.item_grid[current_grid_pos] != self:
			# Tile occupied → stop at center
			global_position = object_layer.map_to_local(current_grid_pos)
			stopped = true
			return
	else:
		level_node.item_grid[current_grid_pos] = self
		stopped = false  # We successfully claimed the tile

	# ---- CHECK FOR CONVEYOR ----
	var move_vec = Vector2.ZERO
	var on_conveyor = false
	if level_node.active_grid_objects.has(current_grid_pos):
		var data = level_node.active_grid_objects[current_grid_pos]["data"]
		if data.is_conveyor:
			move_vec = data.conveyor_direction
			on_conveyor = true

	# ---- IF NOT ON CONVEYOR, SNAP AND STOP ----
	if not on_conveyor:
		global_position = object_layer.map_to_local(current_grid_pos)
		stopped = true
		return

	# ---- IF STOPPED, WAIT UNTIL NEXT TILE FREE ----
	if stopped:
		# Check if next tile is now free
		var next_pos_check = global_position + (move_vec * speed * delta)
		var next_grid_pos_check = object_layer.local_to_map(next_pos_check)
		if not level_node.item_grid.has(next_grid_pos_check):
			stopped = false  # Can move now
		else:
			return  # Still blocked

	# ---- PREDICT NEXT POSITION ----
	var next_pos = global_position + (move_vec * speed * delta)
	var next_grid_pos = object_layer.local_to_map(next_pos)

	# ---- BLOCKED BY NEXT ITEM ----
	if next_grid_pos != current_grid_pos and level_node.item_grid.has(next_grid_pos):
		global_position = object_layer.map_to_local(current_grid_pos)
		stopped = true
		return

	# ---- MOVE SMOOTHLY ----
	global_position = next_pos

	# ---- UPDATE GRID OWNERSHIP ----
	var new_grid_pos = object_layer.local_to_map(global_position)
	if new_grid_pos != current_grid_pos:
		if level_node.item_grid.get(current_grid_pos) == self:
			level_node.item_grid.erase(current_grid_pos)
		level_node.item_grid[new_grid_pos] = self
