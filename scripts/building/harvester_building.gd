extends Building
class_name HarvesterBuilding

@export_group("Settings")
@export var target_resource: TileDataResource 
@export var generic_item_scene: PackedScene
@export var scan_radius: int = 4
@export var harvest_damage: int = 2
@export var work_interval: float = 1.0


@export_group("Inventory")
@export var buffer_capacity: int = 10 # Stops working if we hold 10 items
var stored_amount: int = 0

# Visuals
@onready var beam_line: Line2D = $Line2D

var level_ref: Node2D
var work_timer: float = 0.0
var current_target: Vector2i = Vector2i.MAX

# --- NEW: Range Visual Variables ---
var show_range_overlay := false:
	set(value):
		show_range_overlay = value
		queue_redraw() # Forces Godot to run _draw() again

const TILE_SIZE = 32 # Assuming 32x32 tiles. Change if different!

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance

# --- DRAWING THE RANGE ---
func _draw():
	if show_range_overlay:
		# 1. Get the center TILE (the exact same logic _perform_harvest uses)
		# If level_ref is missing (e.g. disconnected ghost), fallback to simple rect
		if not level_ref:
			_draw_fallback_rect()
			return

		var center_tile = level_ref.object_layer.local_to_map(global_position)
		
		# 2. Calculate the Grid Bounds
		# We scan from -radius to +radius. 
		# If radius is 4, width is 9 tiles (4 left + 1 center + 4 right)
		var top_left_tile = center_tile - Vector2i(scan_radius, scan_radius)
		var size_in_tiles = Vector2(scan_radius * 2 + 1, scan_radius * 2 + 1)
		
		# 3. Convert Grid -> World Pixels
		# map_to_local gives the CENTER of the tile. 
		# We need the TOP-LEFT corner of the rectangle.
		var tile_center_world = level_ref.object_layer.map_to_local(top_left_tile)
		var tile_top_left_world = tile_center_world - (Vector2(TILE_SIZE, TILE_SIZE) / 2.0)
		
		# 4. Convert World -> Local (relative to this building node)
		var local_pos = to_local(tile_top_left_world)
		var size_px = size_in_tiles * TILE_SIZE
		
		# 5. Draw
		var rect = Rect2(local_pos, size_px)
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.2), true) # Transparent Fill
		draw_rect(rect, Color(0.2, 1.0, 0.2, 0.5), false, 2.0) # Border

func _draw_fallback_rect():
	# Keeps the old logic just in case the level reference is missing
	var diameter_tiles = (scan_radius * 2) + 1
	var size_px = diameter_tiles * TILE_SIZE
	var top_left = Vector2(-size_px / 2.0, -size_px / 2.0)
	draw_rect(Rect2(top_left, Vector2(size_px, size_px)), Color(1, 0, 0, 0.3), true)

# --- OVERRIDES FOR VISIBILITY ---

# 1. When becoming a Ghost (Placement Mode)
func set_ghost(enabled: bool):
	super.set_ghost(enabled) # Run the original logic (transparency)
	show_range_overlay = enabled # Show range while placing!

# 2. When Mouse Enters (Hover Mode)
func _on_mouse_entered():
	super._on_mouse_entered() # Run original signal logic
	# Only show if placed (not a ghost) to avoid conflict, 
	# though ghost usually handles its own state.
	if not get_node("Area2D").monitoring: return # Ghost mode check
	show_range_overlay = true

# 3. When Mouse Exits
func _on_mouse_exited():
	super._on_mouse_exited()
	# Only hide if we aren't a ghost (ghosts always show range)
	if not get_node("Area2D").monitoring: return 
	show_range_overlay = false

# --- MAIN LOOP  ---
func building_tick(delta: float) -> void:
	if not level_ref or not target_resource: return
	
	if stored_amount > 0:
		_try_output_item()
	
		
	# NEW LOGIC: Check if there is space for the NEXT harvest
	# If we have 9/10 and harvest gives 2, (9+2) > 10, so we wait.
	if stored_amount + harvest_damage > buffer_capacity:
		if beam_line: beam_line.clear_points()
		return
	work_timer -= delta
	
	# Update Visuals (Only if not full)
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
		
		# 1. Mine the resource
		ResourceManager.request_harvest(current_target, info, harvest_damage)
		
		# 2. NEW: Add to Internal Buffer
		stored_amount += harvest_damage
		print("Harvester Buffer: %d/%d" % [stored_amount, buffer_capacity])
		
		# 3. Emit inventory changed signal for ui
		inventory_changed.emit()
		

func _find_nearest_target() -> Vector2i:
	var center = level_ref.object_layer.local_to_map(global_position)
	var best_pos = Vector2i.MAX
	var min_dist = 99999.0
	
	for x in range(-scan_radius, scan_radius + 1):
		for y in range(-scan_radius, scan_radius + 1):
			var check_pos = center + Vector2i(x, y)
			
			if _is_valid_target(check_pos):
				var dist = center.distance_squared_to(check_pos)
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
	
	
func get_inventory_info() -> Dictionary:
	# If we have a resource and items, return them
	if target_resource and stored_amount > 0:
		return { target_resource: stored_amount }
	return {}
	
# --- OUTPUT LOGIC ---

func _try_output_item():
	# 1. Loop through every tile this building occupies (e.g., all 16 tiles)
	for my_tile in occupied_tiles:
		
		# 2. Check all 4 directions from this specific tile
		var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in directions:
			var target_pos = my_tile + offset
			
			# 3. CRITICAL: Skip if this neighbor is actually still part of myself!
			# (We don't want to output from the left side of the building into the right side)
			if occupied_tiles.has(target_pos):
				continue
				
			# 4. Safety: Is the target tile blocked by another item?
			if level_ref.item_grid.has(target_pos):
				continue 

			# 5. Check for Conveyor
			if _is_conveyor_at(target_pos):
				_spawn_item(target_pos)
				return # Successfully output one item; stop for this frame.

func _is_conveyor_at(grid_pos: Vector2i) -> bool:
	if level_ref.active_grid_objects.has(grid_pos):
		var data = level_ref.active_grid_objects[grid_pos]["data"]
		return data.is_conveyor
	return false

func _spawn_item(target_pos: Vector2i):
	# 1. Validation
	if not generic_item_scene:
		print("Error: Generic Item Scene not assigned to Harvester Inspector!")
		return
	
	# Ensure the Resource (Tree.tres) has an Item (Log.tres) assigned
	if not target_resource.item_drop:
		print("Error: Resource %s has no item_drop assigned!" % target_resource.display_name)
		return

	# 2. Instantiate
	var new_item_node = generic_item_scene.instantiate()
	
	# 3. Inject Data
	
	if new_item_node.has_method("setup"):
		new_item_node.setup(level_ref)
		
	
	# We give the generic item the specific data (Log/Stone)
	if "item_data" in new_item_node:
		new_item_node.item_data = target_resource.item_drop
		# If your item script needs a kick to update the texture:
		if new_item_node.has_method("_ready"):
			new_item_node._ready() 
	
	# 4. Add to World
	level_ref.add_child(new_item_node)
	new_item_node.global_position = level_ref.object_layer.map_to_local(target_pos)
	
	# 5. Update Logic
	stored_amount -= 1
	level_ref.item_grid[target_pos] = new_item_node # Register to grid
	
	inventory_changed.emit()
	print("Output item to ", target_pos)
