extends Sprite2D

@export var speed = 100.0
@onready var level_node = get_tree().current_scene
@export var item_data: ItemResource

var stopped = false  # Tracks if item is blocked or finished conveyor
var deadlocked = false  # NEW: permanent deadlock flag
var blocked_by = null   # NEW: reference to item blocking us

var conveyor_stopped = false

func _ready():
	if item_data:
		texture = item_data.texture

func _process(delta):
	if deadlocked or not level_node:
		return

	var object_layer = level_node.object_layer
	var current_grid_pos = object_layer.local_to_map(global_position)

	# -----------------------------
	# 1️⃣ Check if current tile is a building that accepts items
	# -----------------------------
	var b_manager = level_node.building_manager 
	
	# Optimization: Use the dictionary lookup instead of looping through all buildings
	if b_manager.occupied_tiles.has(current_grid_pos):
		var building = b_manager.occupied_tiles[current_grid_pos]
		
		# Now check if this specific building wants the item
		if building.accepts_item_at(current_grid_pos) and building.can_accept_item(item_data):
			building.accept_item(item_data)
			
			# Cleanup grid and delete item
			if level_node.item_grid.get(current_grid_pos) == self:
				level_node.item_grid.erase(current_grid_pos)
				
			queue_free()
			return


	# -----------------------------
	# 2️⃣ Claim current tile if possible
	# -----------------------------
	if level_node.item_grid.has(current_grid_pos):
		if level_node.item_grid[current_grid_pos] != self:
			global_position = object_layer.map_to_local(current_grid_pos)
			stopped = true
			conveyor_stopped = true
			return
	else:
		level_node.item_grid[current_grid_pos] = self
		stopped = false
		conveyor_stopped = false

	# -----------------------------
	# 3️⃣ Check if we are on a conveyor
	# -----------------------------
	var move_vec = Vector2.ZERO
	var on_conveyor = false
	if level_node.active_grid_objects.has(current_grid_pos):
		var data = level_node.active_grid_objects[current_grid_pos]["data"]
		if data.is_conveyor:
			move_vec = data.conveyor_direction
			on_conveyor = true

	if not on_conveyor:
		# Snap and stop if not on a conveyor
		global_position = object_layer.map_to_local(current_grid_pos)
		stopped = true
		conveyor_stopped = true
		return

	# -----------------------------
	# 4️⃣ Determine next tile
	# -----------------------------
	# Proper grid offset using sign
	var offset = Vector2i(sign(move_vec.x), sign(move_vec.y))
	var next_grid_pos = current_grid_pos + offset

	# Check if next tile is a conveyor
	var next_is_conveyor = false
	if level_node.active_grid_objects.has(next_grid_pos):
		var next_data = level_node.active_grid_objects[next_grid_pos]["data"]
		if next_data.is_conveyor:
			next_is_conveyor = true

			


	# -----------------------------
	# 5️⃣ Stop if next tile is neither conveyor nor building accepts items
	# -----------------------------
	if not next_is_conveyor and not next_tile_accepts_item(next_grid_pos):
		global_position = object_layer.map_to_local(current_grid_pos)
		stopped = true
		conveyor_stopped = true
		return

	# -----------------------------
	# 6️⃣ Check if next tile is blocked by another item
	# -----------------------------
	if level_node.item_grid.has(next_grid_pos):
		var blocking_item = level_node.item_grid[next_grid_pos]
		blocked_by = blocking_item

		# Deadlock detection
		if blocking_item is Sprite2D and blocking_item.blocked_by == self:
			deadlocked = true
			blocking_item.deadlocked = true
			modulate = Color.RED
			blocking_item.modulate = Color.RED
			print_debug("Deadlock!")

		global_position = object_layer.map_to_local(current_grid_pos)
		stopped = true
		conveyor_stopped = true
		return

	# -----------------------------
	# 7️⃣ Move smoothly
	# -----------------------------
	global_position += move_vec * speed * delta

	# -----------------------------
	# 8️⃣ Update grid ownership
	# -----------------------------
	var new_grid_pos = object_layer.local_to_map(global_position)
	if new_grid_pos != current_grid_pos:
		if level_node.item_grid.get(current_grid_pos) == self:
			level_node.item_grid.erase(current_grid_pos)
		level_node.item_grid[new_grid_pos] = self
		blocked_by = null
		
func next_tile_accepts_item(tile: Vector2i) -> bool:
	var b_manager = level_node.building_manager
	
	if b_manager.occupied_tiles.has(tile):
		var building = b_manager.occupied_tiles[tile]
		return building.accepts_item_at(tile) and building.can_accept_item(item_data)
		
	return false
