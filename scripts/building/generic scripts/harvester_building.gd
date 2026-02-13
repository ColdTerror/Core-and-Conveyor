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

func _ready():
	super() # Make sure this calls Building._ready()
	
	# 1. Register Self
	EconomyManager.register_source(self)

func _exit_tree():
	# 2. Unregister Self
	EconomyManager.unregister_source(self)

# 3. Implement Consumption Logic
func consume_resources(remaining_bill: Dictionary):
	# Harvesters only hold ONE type of resource, so check is simple
	if not target_resource or not target_resource.item_drop: return
	
	var res_name = target_resource.item_drop.display_name
	
	if remaining_bill.has(res_name):
		var amount_needed = remaining_bill[res_name]
		var amount_we_have = stored_amount
		
		var amount_to_take = min(amount_needed, amount_we_have)
		
		# A. Remove from Internal Buffer
		stored_amount -= amount_to_take
		
		# B. Update the Bill
		remaining_bill[res_name] -= amount_to_take
		if remaining_bill[res_name] <= 0:
			remaining_bill.erase(res_name)
			
		inventory_changed.emit()
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
		# --- THE FIX: ADD TO BANK ---
		# We physically have the item, so we tell the EconomyManager we are richer.
		if target_resource.item_drop:
			EconomyManager.add_resources(target_resource.item_drop.display_name, harvest_damage)
		# ----------------------------
		
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
	for my_tile in occupied_tiles:
		# These are the directions we are "pushing" items out to
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			# 1. Standard Checks (Don't output into myself or blocked tiles)
			if occupied_tiles.has(target_pos): continue
			if level_ref.item_grid.has(target_pos): continue 
			
			# 2. Check Grid Data
			if level_ref.active_grid_objects.has(target_pos):
				var info = level_ref.active_grid_objects[target_pos]
				var data = info["data"]
				
				# 3. Is it a Conveyor?
				if data.is_conveyor:
					# 4. CRITICAL: Check Direction
					# We retrieve the specific direction stored in the grid dictionary
					# (Make sure Level.gd place_tile is saving "direction" correctly!)
					var conveyor_dir = info.get("direction", Vector2.ZERO)
					
					# We want the conveyor to be moving in the SAME direction we are pushing.
					# offset is our push direction (e.g. (1, 0) for Right)
					# conveyor_dir is the belt's movement (e.g. (1, 0) for Right)
					
					# Note: We cast offset to Vector2 to match conveyor_dir type
					if conveyor_dir == Vector2(offset):
						_spawn_item(target_pos)

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
	# --- THE FIX: REMOVE FROM BANK ---
	# The item is leaving "Storage" and going onto a belt.
	# Items on belts are considered "In Transit" (not spendable), so we deduct it.
	# (It will be re-added when it enters a Stockpile later).
	var dict = { target_resource.item_drop.display_name: 1 }
	EconomyManager.remove_resources_from_global(dict)
	# ---------------------------------
	level_ref.item_grid[target_pos] = new_item_node
	inventory_changed.emit()
	
func get_inventory_info() -> Dictionary:
	if target_resource and stored_amount > 0:
		return { target_resource: stored_amount }
	return {}
