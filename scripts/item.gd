extends Sprite2D

@export var speed = 100.0
var level_node: Node2D
@export var item_data: ItemResource

var stopped = false
var deadlocked = false
var blocked_by = null
var conveyor_stopped = false

func setup(level_instance: Node2D):
	level_node = level_instance

func _ready():
	if item_data:
		texture = item_data.texture

func _process(delta):
	if deadlocked or not level_node:
		return

	var object_layer = level_node.object_layer
	var current_grid_pos = object_layer.local_to_map(global_position)
	var b_manager = level_node.building_manager 

	# -----------------------------
	# 1. Building Check (Unchanged)
	# -----------------------------
	if b_manager.occupied_tiles.has(current_grid_pos):
		var building = b_manager.occupied_tiles[current_grid_pos]
		if building.accepts_item_at(current_grid_pos) and building.can_accept_item(item_data):
			building.accept_item(item_data)
			if level_node.item_grid.get(current_grid_pos) == self:
				level_node.item_grid.erase(current_grid_pos)
			queue_free()
			return

	# -----------------------------
	# 2. Claim Tile (Unchanged)
	# -----------------------------
	if level_node.item_grid.has(current_grid_pos):
		if level_node.item_grid[current_grid_pos] != self:
			var other_item = level_node.item_grid[current_grid_pos]
			var distance = global_position.distance_to(other_item.global_position)
			if distance < 16.0: 
				stopped = true
				conveyor_stopped = true
				return
	else:
		level_node.item_grid[current_grid_pos] = self

	stopped = false
	conveyor_stopped = false

	# -----------------------------
	# 3. Check Conveyor (Unchanged)
	# -----------------------------
	var move_vec = Vector2.ZERO
	var on_conveyor = false

	if level_node.active_grid_objects.has(current_grid_pos):
		var data = level_node.active_grid_objects[current_grid_pos]["data"]
		if data.is_conveyor:
			move_vec = data.conveyor_direction
			on_conveyor = true

	if not on_conveyor:
		stopped = true
		conveyor_stopped = true
		return

	# -----------------------------
	# 4. Look Ahead (Unchanged)
	# -----------------------------
	var offset = Vector2i(sign(move_vec.x), sign(move_vec.y))
	var next_grid_pos = current_grid_pos + offset

	var next_is_valid = false
	if level_node.active_grid_objects.has(next_grid_pos):
		var next_data = level_node.active_grid_objects[next_grid_pos]["data"]
		if next_data.is_conveyor:
			next_is_valid = true
	
	if not next_is_valid and next_tile_accepts_item(next_grid_pos):
		next_is_valid = true

	# -----------------------------
	# 5. DOCKING LOGIC (THE FIX)
	# -----------------------------
	# If the path ends here, we don't stop immediately.
	# Instead, we move towards the CENTER of the current tile.
	if not next_is_valid:
		var center_pos = object_layer.map_to_local(current_grid_pos)
		
		# Move towards center
		global_position = global_position.move_toward(center_pos, speed * delta)
		
		# If we reached the center, NOW we stop.
		if global_position == center_pos:
			stopped = true
			conveyor_stopped = true
		
		# Return here so we skip the standard movement logic below.
		# This effectively "traps" the item in the center of the last tile.
		return

	# -----------------------------
	# 6. Check Blocking (Unchanged)
	# -----------------------------
	if level_node.item_grid.has(next_grid_pos):
		var blocking_item = level_node.item_grid[next_grid_pos]
		var distance_to_blocker = global_position.distance_to(blocking_item.global_position)
		var min_distance = 32.0 
		
		if distance_to_blocker < min_distance:
			blocked_by = blocking_item
			
			if blocking_item is Sprite2D and blocking_item.blocked_by == self:
				deadlocked = true
				blocking_item.deadlocked = true
				modulate = Color.RED
				blocking_item.modulate = Color.RED
				print("Deadlock!")

			stopped = true
			conveyor_stopped = true
			return

	# -----------------------------
	# 7. Move & Smooth Align (Unchanged)
	# -----------------------------
	global_position += move_vec * speed * delta
	
	var center_pos = object_layer.map_to_local(current_grid_pos)
	var align_speed = speed * delta 
	
	if move_vec.x != 0: 
		global_position.y = move_toward(global_position.y, center_pos.y, align_speed)
	elif move_vec.y != 0: 
		global_position.x = move_toward(global_position.x, center_pos.x, align_speed)

	# -----------------------------
	# 8. Update Grid (Unchanged)
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
