extends Building
class_name HarvesterBuilding

@export_group("Settings")
@export var target_resource: TileDataResource 
@export var generic_item_scene: PackedScene 
@export var scan_radius: int = 4
@export var harvest_damage: int = 2
@export var work_interval: float = 1.0

@export_group("Inventory")
@export var buffer_capacity: int = 10 
var stored_amount: int = 0

# Visuals
@onready var beam_line: Line2D = $Line2D

var level_ref: Node2D
var work_timer: float = 0.0
var current_target: Vector2i = Vector2i.MAX

# Range Visuals
var show_range_overlay := false:
	set(value):
		show_range_overlay = value
		queue_redraw()

const TILE_SIZE = 32

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance

# --- DRAWING THE RANGE ---
func _draw():
	if show_range_overlay and level_ref:
		# 1. Get the building's Top-Left Tile
		# Since 'place_at' in Building.gd centers the node, 
		# we calculate the true grid origin using the size.
		var center_tile = level_ref.object_layer.local_to_map(global_position)
		
		# Even sizes (2,4) shift the center tile index. 
		# We subtract half size to get back to Top-Left.
		var top_left_tile = center_tile - (size / 2)
		
		# 2. Calculate Drawing Start Point (Top-Left minus Radius)
		var range_top_left = top_left_tile - Vector2i(scan_radius, scan_radius)
		
		# 3. Calculate Total Dimensions in Tiles
		# Width = Building Width + Left Radius + Right Radius
		var total_width = size.x + (scan_radius * 2)
		var total_height = size.y + (scan_radius * 2)
		
		# 4. Convert Grid -> Local Pixels for drawing
		var world_pos = level_ref.object_layer.map_to_local(range_top_left)
		# map_to_local is center of tile; adjust to top-left corner of that tile
		world_pos -= Vector2(TILE_SIZE, TILE_SIZE) / 2.0
		
		var local_pos = to_local(world_pos)
		var size_px = Vector2(total_width, total_height) * TILE_SIZE
		
		var rect = Rect2(local_pos, size_px)
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.2), true)
		draw_rect(rect, Color(0.2, 1.0, 0.2, 0.5), false, 2.0)

# --- OVERRIDES FOR VISIBILITY ---
func set_ghost(enabled: bool):
	super.set_ghost(enabled)
	show_range_overlay = enabled

func _on_mouse_entered():
	super._on_mouse_entered()
	if not get_node("Area2D").monitoring: return 
	show_range_overlay = true

func _on_mouse_exited():
	super._on_mouse_exited()
	if not get_node("Area2D").monitoring: return 
	show_range_overlay = false

# --- MAIN LOOP ---
func building_tick(delta: float) -> void:
	if not level_ref or not target_resource: return
	
	if stored_amount > 0:
		_try_output_item()
	
	# Check if adding harvest_damage would exceed capacity
	if stored_amount + harvest_damage > buffer_capacity:
		if beam_line: beam_line.clear_points()
		return
		
	work_timer -= delta
	
	if current_target != Vector2i.MAX:
		_draw_beam(current_target)
	else:
		if beam_line: beam_line.clear_points()

	if work_timer <= 0:
		work_timer = work_interval
		_perform_harvest()

func _perform_harvest():
	if not _is_valid_target(current_target):
		current_target = _find_nearest_target()
	
	if current_target != Vector2i.MAX:
		var info = level_ref.active_grid_objects[current_target]
		ResourceManager.request_harvest(current_target, info, harvest_damage)
		stored_amount += harvest_damage
		inventory_changed.emit()

# --- TARGET FINDING (UPDATED) ---
func _find_nearest_target() -> Vector2i:
	var center_tile = level_ref.object_layer.local_to_map(global_position)
	var top_left_tile = center_tile - (size / 2) # Use self.size from Building.gd
	
	# Define bounds relative to the building footprint
	var start_x = top_left_tile.x - scan_radius
	var end_x = top_left_tile.x + size.x + scan_radius - 1 # -1 for inclusive index
	
	var start_y = top_left_tile.y - scan_radius
	var end_y = top_left_tile.y + size.y + scan_radius - 1
	
	var best_pos = Vector2i.MAX
	var min_dist = 99999.0
	
	# Spiral or simple box scan
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var check_pos = Vector2i(x, y)
			
			if _is_valid_target(check_pos):
				var dist = center_tile.distance_squared_to(check_pos)
				if dist < min_dist:
					min_dist = dist
					best_pos = check_pos
					
	return best_pos

func _is_valid_target(pos: Vector2i) -> bool:
	if pos == Vector2i.MAX: return false
	if not level_ref.active_grid_objects.has(pos): return false
	var info = level_ref.active_grid_objects[pos]
	if info["health"] <= 0: return false
	if info["data"] != target_resource: return false
	return true

func _draw_beam(grid_pos: Vector2i):
	if not beam_line: return
	var target_world = level_ref.object_layer.map_to_local(grid_pos)
	var target_local = to_local(target_world)
	beam_line.clear_points()
	beam_line.add_point(Vector2.ZERO)
	beam_line.add_point(target_local)

# --- OUTPUT LOGIC ---
func _try_output_item():
	# Loop through every tile occupied by this building
	for my_tile in occupied_tiles:
		var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in directions:
			var target_pos = my_tile + offset
			
			# Don't output into myself
			if occupied_tiles.has(target_pos): continue
			# Don't output if target tile is blocked
			if level_ref.item_grid.has(target_pos): continue 

			if _is_conveyor_at(target_pos):
				_spawn_item(target_pos)
				return 

func _is_conveyor_at(grid_pos: Vector2i) -> bool:
	if level_ref.active_grid_objects.has(grid_pos):
		var data = level_ref.active_grid_objects[grid_pos]["data"]
		return data.is_conveyor
	return false

func _spawn_item(target_pos: Vector2i):
	if not generic_item_scene or not target_resource.item_drop: return

	var new_item_node = generic_item_scene.instantiate()
	
	if new_item_node.has_method("setup"):
		new_item_node.setup(level_ref)
	
	if "item_data" in new_item_node:
		new_item_node.item_data = target_resource.item_drop
		if new_item_node.has_method("_ready"):
			new_item_node._ready() 

	level_ref.add_child(new_item_node)
	new_item_node.global_position = level_ref.object_layer.map_to_local(target_pos)
	
	stored_amount -= 1
	level_ref.item_grid[target_pos] = new_item_node
	inventory_changed.emit()
	
func get_inventory_info() -> Dictionary:
	if target_resource and stored_amount > 0:
		return { target_resource: stored_amount }
	return {}
