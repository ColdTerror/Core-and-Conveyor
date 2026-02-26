extends Node2D
class_name BuildingManager

@export var object_layer: TileMapLayer
@export var hover_popup: Control

@export var terrain_layer: TileMapLayer
@export var corruption_layer: TileMapLayer

# ---TRACKERS ---
# Key: Vector2i (Grid Coord), Value: int (Number of buildings in range)
var safe_tiles: Dictionary = {}
var buildable_tiles: Dictionary = {} 

# --- VISUALIZER STATES ---
var show_build_grid: bool = false
var show_safe_grid: bool = false

var buildings: Array[Building] = []
var occupied_tiles := {} # Key: Vector2i, Value: Building

var ghost_building: Building = null
var placing_building := false

# --- DRAG VARIABLES ---
var is_dragging: bool = false
var drag_start: Vector2i
var drag_ghosts: Array[Node2D] = [] # Stores the temporary ghosts for the line

var level_ref: Node2D 

var pathfinder: Pathfinder

# -------------------------------
# PUBLIC API
# -------------------------------
func initialize(level_instance: Node2D):
	level_ref = level_instance
	
func start_placing(scene: PackedScene):
	if scene == null:
		return

	# Reset any previous state
	cancel_placement()

	ghost_building = scene.instantiate() as Building
	# Add to a dedicated ghost layer if possible, otherwise just child it
	if level_ref and level_ref.has_node("GhostLayer"):
		level_ref.get_node("GhostLayer").add_child(ghost_building)
	else:
		add_child(ghost_building)
	
	# Inject Level immediately so Ghost can see the grid
	if ghost_building is ConveyorBuilding:
		# Give it a default direction for the ghost preview
		ghost_building.setup(level_ref, Vector2i.RIGHT)
	elif ghost_building.has_method("setup"):
		ghost_building.setup(level_ref)

	ghost_building.set_ghost(true)
	placing_building = true
	
	# Reset drag state
	is_dragging = false
	_clear_drag_ghosts()

# --- NEW: INPUT HANDLER FOR LEVEL.GD ---
# This manages the Drag Logic vs Instant Click logic
func handle_input(event, current_grid_pos: Vector2i) -> bool:
	if not ghost_building: return false
	
	# 1. Update the Main Cursor Ghost (if not dragging)
	if not is_dragging:
		_update_ghost_position_to(current_grid_pos)

	# 2. HANDLE CLICKS
	if event.is_action_pressed("ui_left"):
		
		# CASE A: Draggable Building (Wall) -> START DRAG
		if ghost_building.is_draggable:
			is_dragging = true
			drag_start = current_grid_pos
			_update_drag_line(current_grid_pos)
			ghost_building.visible = false # Hide the main cursor
			return false # Keep processing input
			
		# CASE B: Normal Building (Tower) -> PLACE INSTANTLY
		else:
			return confirm_placement()

	# 3. HANDLE DRAG UPDATE (Mouse Moved)
	if is_dragging and event is InputEventMouseMotion:
		_update_drag_line(current_grid_pos)

	# 4. HANDLE RELEASE (Commit Drag)
	if event.is_action_released("ui_left") and is_dragging:
		
		ghost_building.visible = true # Show cursor again
		_commit_drag_line()
		is_dragging = false
		_clear_drag_ghosts()
		return false #Keep placing belts

	return false
# ---------------------------------------

func _process(delta):
	for b in buildings:
		b.building_tick(delta)
	

	if placing_building:
		queue_redraw()

# -------------------------------
# VISUAL OVERLAYS (Grid-Based)
# -------------------------------
func _draw():
	# If we aren't placing a building AND both toggles are off, don't draw anything
	if not placing_building and not show_build_grid and not show_safe_grid:
		return

	var tile_size = 32.0 
	var half_offset = Vector2(tile_size / 2.0, tile_size / 2.0)
	
	# 1. DRAW GLOBAL BUILD ZONES (F1 Hotkey)
	if show_build_grid:
		var build_color = Color(0.2, 1.0, 0.2, 0.15) # Faint green
		for tile in buildable_tiles.keys():
			var local_pos = object_layer.map_to_local(tile) - half_offset
			draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), build_color)

	# 2. DRAW GLOBAL SAFE ZONES (F2 Hotkey)
	if show_safe_grid:
		var safe_color = Color(0.2, 0.5, 1.0, 0.15) # Faint blue
		for tile in safe_tiles.keys():
			var local_pos = object_layer.map_to_local(tile) - half_offset
			draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), safe_color)

	# 3. DRAW GHOST PREVIEWS (When Placing)
	if placing_building:
		var ghosts_to_draw = []
		if is_dragging and drag_ghosts.size() > 0:
			ghosts_to_draw = drag_ghosts
		elif ghost_building:
			ghosts_to_draw = [ghost_building]

		var preview_build = Color(0.5, 1.0, 0.5, 0.2) # Brighter green
		var preview_safe = Color(0.5, 0.8, 1.0, 0.2)  # Brighter blue

		for g in ghosts_to_draw:
			if not is_instance_valid(g): continue
			
			var origin = object_layer.local_to_map(g.global_position)
			
			# Preview the exact tiles this building will make Safe
			if "corruption_range" in g and g.corruption_range > 0:
				var s_tiles = _get_tiles_in_radius(origin, g, g.corruption_range)
				for t in s_tiles:
					var pos = object_layer.map_to_local(t) - half_offset
					draw_rect(Rect2(pos, Vector2(tile_size, tile_size)), preview_safe)
					
			# Preview the exact tiles this building will make Buildable
			if "build_range" in g and g.build_range > 0:
				var b_tiles = _get_tiles_in_radius(origin, g, g.build_range)
				for t in b_tiles:
					var pos = object_layer.map_to_local(t) - half_offset
					draw_rect(Rect2(pos, Vector2(tile_size, tile_size)), preview_build)


func _on_building_destroyed(b: Building):
	if b in buildings:
		buildings.erase(b)
	
	for tile in b.occupied_tiles:
		if occupied_tiles.has(tile):
			occupied_tiles.erase(tile)
	
	_remove_safe_zone(b)
	_remove_build_zone(b)
	
	# Free up the Pathfinder Tiles
	# We iterate through the tiles the building used to occupy
	if pathfinder:
		for tile in b.occupied_tiles:
			# Reset the tile to be Walkable (Not Solid)
			pathfinder.set_obstacle(tile, false)
			
			# Reset the Weight (Cost) to default Grass (1.0)
			# This ensures Walls don't leave behind invisible "slow zones"
			pathfinder.set_weighted_obstacle(tile, 1.0)

	# We call the translator function. 
	# - If it's a Tower, it returns {} (Safe).
	# - If it's a Stockpile, it returns {"Wood": 50} (Safe).
	if b.has_method("get_economy_assets"):
		var assets = b.get_economy_assets()
		
		if not assets.is_empty():
			EconomyManager.remove_resources_from_global(assets)
	# ------------------

		

# --- UPDATED: Accepts optional grid position for Dragging ---
func confirm_placement(specific_pos: Vector2i = Vector2i(-1, -1)) -> bool:
	if not placing_building or ghost_building == null:
		return false

	var grid_pos = specific_pos
	if grid_pos == Vector2i(-1, -1):
		grid_pos = _get_mouse_grid()

	if not _can_place_building(ghost_building, grid_pos):
		return false
		
	# Check Economy
	var cost = ghost_building.get_build_cost()
	if not EconomyManager.can_afford(cost):
		return false

	# Pay the Cost
	EconomyManager.spend_resources(cost)

	# Finalize the Building
	ghost_building.set_ghost(false)
	ghost_building.place_at(grid_pos, object_layer)
	
	ghost_building.visible = true
	ghost_building.modulate = Color(1, 1, 1, 1)
	
	# NEW: Setup Conveyor Direction
	if ghost_building is ConveyorBuilding:
		# The ghost already has the correct direction from _update_drag_line or rotate_ghost
		ghost_building.setup(level_ref, ghost_building.direction)
	elif ghost_building.has_method("setup"):
			ghost_building.setup(level_ref)
	# ----------------
		
	# Connect Signals
	if ghost_building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
		ghost_building.fired_projectile.connect(level_ref._on_tower_fired)
		
	ghost_building.destroyed.connect(_on_building_destroyed)

	buildings.append(ghost_building)
	_register_building(ghost_building)
	_register_occupied_tiles(ghost_building)
	_add_safe_zone(ghost_building)
	_add_build_zone(ghost_building)
	
	# --- NEW: TRIGGER CORRUPTION ---
	if ghost_building is CoreBuilding:
		if level_ref and level_ref.has_node("CorruptionManager"):
			var corruption_manager = level_ref.get_node("CorruptionManager")
			var core_grid = object_layer.local_to_map(ghost_building.global_position)
			
			corruption_manager.start_outbreak(core_grid)
	# ------------------------------
	
	# Update Pathfinder
	if pathfinder:
		var footprint = ghost_building.get_footprint(grid_pos)
		
		if ghost_building.is_solid_obstacle:
			for tile in footprint:
				pathfinder.set_obstacle(tile, true)
		else:
			for tile in footprint:
				pathfinder.set_weighted_obstacle(tile, ghost_building.path_cost)
				
	ghost_building = null
	
	if not is_dragging:
		placing_building = false
		queue_redraw()
	
	return true

# -------------------------------
# DRAG LOGIC IMPLEMENTATION
# -------------------------------

func _update_drag_line(current_grid: Vector2i):
	var points = _get_straight_line(drag_start, current_grid)
	
	# 1. Calculate Direction (Conveyors only)
	var drag_direction = Vector2i.RIGHT 
	if ghost_building is ConveyorBuilding:
		# Default to whatever direction you manually rotated it to!
		drag_direction = ghost_building.direction 
		
		# If you dragged your mouse, THEN override the direction
		if points.size() > 1:
			var diff = points[-1] - points[0] 
			if abs(diff.x) >= abs(diff.y):
				drag_direction = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
			else:
				drag_direction = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
	
	# 2. Sync Ghost Count (Create/Delete visual nodes)
	while drag_ghosts.size() < points.size():
		var new_ghost = ghost_building.duplicate()
		new_ghost.visible = true
		
		# Apply initial direction
		if new_ghost is ConveyorBuilding:
			new_ghost.direction = drag_direction
			new_ghost.rotation = Vector2(drag_direction).angle()
		
		if level_ref and level_ref.has_node("GhostLayer"):
			level_ref.get_node("GhostLayer").add_child(new_ghost)
		else:
			add_child(new_ghost)
		drag_ghosts.append(new_ghost)
	
	while drag_ghosts.size() > points.size():
		var g = drag_ghosts.pop_back()
		g.queue_free()
	
	# 3. GET BASE COST
	var base_cost = ghost_building.get_build_cost() # e.g. {"Wood": 5}
	
	# --- NEW: REVERSE BUILD ORDER IF DRAGGING INWARD ---
	# Check if the player is dragging from outside the base INTO the base.
	if points.size() > 1 and buildings.size() > 0:
		var start_touches_base = false
		var end_touches_base = false
		
		# Quick distance check for the start and end of the line
		for b in buildings:
			var b_grid = object_layer.local_to_map(b.global_position)
			if points[0].distance_to(b_grid) <= b.build_range: start_touches_base = true
			if points[-1].distance_to(b_grid) <= b.build_range: end_touches_base = true
			
		# If the end is safe but the start isn't, flip the line!
		if end_touches_base and not start_touches_base:
			points.reverse()
			drag_ghosts.reverse()
	# ---------------------------------------------------
	
	# --- NEW: Track the valid grid positions in this drag line ---
	var current_drag_network: Array[Vector2i] = []
	
	# 4. Update Position & Color Loop
	for i in range(points.size()):
		var pt = points[i]
		var g = drag_ghosts[i]
		
		if g is ConveyorBuilding:
			g.direction = drag_direction
			g.rotation = Vector2(drag_direction).angle()
		
		if object_layer:
			g.global_position = object_layer.map_to_local(pt)
		
		var is_valid = true
		
		# A. Physical & Expansion Check (Pass in our temporary network!)
		if not _can_place_building(g, pt, current_drag_network):
			is_valid = false
			
		# B. Economic Check 
		if is_valid:
			var cumulative_cost = _calculate_cumulative_cost(base_cost, i + 1)
			if not EconomyManager.can_afford(cumulative_cost):
				is_valid = false
		
		# --- NEW: If this ghost is valid, add it to the network for the next ghosts to use ---
		if is_valid:
			current_drag_network.append(pt)
		
		# Apply Visuals
		if g.has_method("set_valid_placement"):
			g.set_valid_placement(is_valid)
		else:
			g.modulate = Color(0, 1, 0, 0.5) if is_valid else Color(1, 0, 0, 0.5)

func _commit_drag_line():
	# Store the original scene to respawn logic later
	if drag_ghosts.size() == 0: return
	
	var original_scene_path = ghost_building.scene_file_path
	var original_scene = load(original_scene_path)
	
	# 1. Kill the main cursor ghost so it doesn't get in the way
	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null
	
	# 2. Iterate and Build
	for g in drag_ghosts:
		# Promote 'g' to be the active ghost
		ghost_building = g
		
		# Calculate grid pos from the ghost's visual position
		# (Must use local_to_map relative to object_layer)
		var grid_pos = object_layer.local_to_map(object_layer.to_local(g.global_position))
		
		# Try to build
		var success = confirm_placement(grid_pos)
		
		# If placement failed (blocked/no money), we must delete the unused ghost
		if not success:
			g.queue_free()
			
	# --- CRITICAL FIX ---
	# We have either used or deleted all ghosts. 
	# Clear the array so handle_input doesn't try to delete them again!
	drag_ghosts.clear() 
	# --------------------

	# 3. Restore the main cursor for the next placement
	start_placing(original_scene)

# Add this function
func rotate_ghost():
	if not ghost_building:
		return
		
	if ghost_building is ConveyorBuilding:
		# Cycle through directions: RIGHT -> DOWN -> LEFT -> UP -> RIGHT
		var current_dir = ghost_building.direction
		var new_dir = Vector2i.ZERO
		
		if current_dir == Vector2i.RIGHT:
			new_dir = Vector2i.DOWN
		elif current_dir == Vector2i.DOWN:
			new_dir = Vector2i.LEFT
		elif current_dir == Vector2i.LEFT:
			new_dir = Vector2i.UP
		else:  # UP
			new_dir = Vector2i.RIGHT
		
		# Update the ghost with new direction
		ghost_building.direction = new_dir
		ghost_building.rotation = Vector2(new_dir).angle()
	# Add other rotatable building types here in the future

# -------------------------------
# INTERNAL HELPERS
# -------------------------------

func _update_ghost_position_to(grid_pos: Vector2i):
	ghost_building.place_at(grid_pos, object_layer)
	var valid = _can_place_building(ghost_building, grid_pos)
	ghost_building.set_valid_placement(valid)

func _get_mouse_grid() -> Vector2i:
	var mouse_global = get_global_mouse_position()
	if not object_layer: return Vector2i.ZERO
	return object_layer.local_to_map(object_layer.to_local(mouse_global))


func _can_place_building(building: Building, origin: Vector2i, temp_network: Array[Vector2i] = []) -> bool:
	if not object_layer: return false
	
	var footprint = building.get_footprint(origin)
	
	# --- 1. THE EXPANSION CHECK ---
	if buildings.size() > 0 or temp_network.size() > 0:
		var touches_range = false
		
		for tile in footprint:
			
			# 1A. Check the Established Base (O(1) Dictionary Lookup! Instant!)
			if buildable_tiles.has(tile):
				touches_range = true
				break 
				
			# 1B. Check against the temporary drag line
			# (We still do math here because these aren't actually built yet)
			for temp_grid in temp_network:
				if tile.distance_to(temp_grid) <= building.build_range:
					touches_range = true
					break
			
			if touches_range: break
			
		if not touches_range:
			return false
	# ------------------------------

	# 2. Check for Corruption
	for tile in footprint:
		if corruption_layer and corruption_layer.get_cell_source_id(tile) != -1:
			return false # Cannot build on purple fog!

	# 3. Check Terrain (Floor exists and is Buildable)
	for tile in footprint:
		if terrain_layer:
			var tile_data = terrain_layer.get_cell_tile_data(tile)
			
			# A. Is there even a floor tile here?
			if tile_data == null:
				return false 
				
			# B. Is it marked as 'buildable' in the TileSet Custom Data?
			if tile_data.get_custom_data("buildable") == false:
				return false # It's water, lava, or a void!

	# 4. Check Object Layer (Trees, Rocks)
	for tile in footprint:
		if object_layer and object_layer.get_cell_source_id(tile) != -1:
			return false

	# 5. Check Occupied Tiles (Other Buildings)
	for tile in footprint:
		if occupied_tiles.has(tile):
			return false

	return true
	
func _register_occupied_tiles(building: Building):
	for tile in building.occupied_tiles:
		occupied_tiles[tile] = building

func _register_building(building: Building):
	building.hovered.connect(_on_building_hovered)
	building.unhovered.connect(_on_building_unhovered)

func _unhandled_input(event):
	# --- NEW: HOTKEYS FOR OVERLAYS ---
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F1:
			show_build_grid = not show_build_grid
			queue_redraw()
		elif event.keycode == KEY_F2:
			show_safe_grid = not show_safe_grid
			queue_redraw()
	# ---------------------------------
	
	# Cancel logic
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
		if ghost_building != null:
			cancel_placement()
			
func cancel_placement():
	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null
	
	_clear_drag_ghosts()
	is_dragging = false
	placing_building = false
	
	queue_redraw()

func _clear_drag_ghosts():
	for g in drag_ghosts:
		if is_instance_valid(g): g.queue_free()
	drag_ghosts.clear()

func _on_building_hovered(building: Building):
	if hover_popup:
		hover_popup.show_building_info(building)

func _on_building_unhovered(building):
	if hover_popup:
		# THE FIX: Only hide if the popup is currently displaying THIS building.
		# If the popup has already switched to a new building, ignore this signal.
		if hover_popup.current_building == building:
			hover_popup.hide_popup()

# Same math as your Level.gd
func _get_straight_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var diff = end - start
	var final_end = end
	
	# Axis Lock
	if abs(diff.x) >= abs(diff.y):
		final_end.y = start.y
	else:
		final_end.x = start.x
		
	var current = start
	var step = Vector2i.ZERO
	if final_end.x != start.x: step.x = sign(final_end.x - start.x)
	if final_end.y != start.y: step.y = sign(final_end.y - start.y)
	
	var safe = 0
	while safe < 100:
		points.append(current)
		if current == final_end: break
		current += step
		safe += 1
		
	return points

func _calculate_cumulative_cost(base_cost: Dictionary, quantity: int) -> Dictionary:
	var total = {}
	for resource_name in base_cost:
		total[resource_name] = base_cost[resource_name] * quantity
	return total
	
# ==========================================
# CORRUPTION / SAFE ZONE LOGIC
# ==========================================

func _get_tiles_in_radius(origin: Vector2i, building: Building, radius: float) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var tile_size = 32.0 # Adjust this if your tiles are 16x16 or 64x64
	
	# 1. Get building size (default to 1x1 for belts/small props if missing)
	var b_size = building.size if "size" in building else Vector2i(1, 1)
	
	# 2. Find the EXACT pixel boundaries of the visual building
	var center_pos = building.global_position
	var half_w = (b_size.x * tile_size) / 2.0
	var half_h = (b_size.y * tile_size) / 2.0
	
	var rect_x_min = center_pos.x - half_w
	var rect_x_max = center_pos.x + half_w
	var rect_y_min = center_pos.y - half_h
	var rect_y_max = center_pos.y + half_h
	
	# 3. Create a generous search box around the origin tile
	var r_int = ceil(radius)
	var search_radius = r_int + max(b_size.x, b_size.y)
	
	var max_dist_px = radius * tile_size
	
	# 4. Check every tile in the search box
	for x in range(origin.x - search_radius, origin.x + search_radius + 1):
		for y in range(origin.y - search_radius, origin.y + search_radius + 1):
			var tile_pos = Vector2i(x, y)
			
			# Get the exact physical center of the tile we are testing
			var tile_center_px = object_layer.map_to_local(tile_pos)
			
			# Math: Measure distance from the tile's center to the building's outer edge
			var dx = max(0.0, max(rect_x_min - tile_center_px.x, tile_center_px.x - rect_x_max))
			var dy = max(0.0, max(rect_y_min - tile_center_px.y, tile_center_px.y - rect_y_max))
			
			var dist_px = Vector2(dx, dy).length()
			
			# If the tile is within the radius, add it!
			if dist_px <= max_dist_px:
				tiles.append(tile_pos)
				
	return tiles

func _add_safe_zone(building: Building):
	if not "corruption_range" in building or building.corruption_range <= 0: 
		return
	
	# Get the center tile of the building
	var origin = object_layer.local_to_map(building.global_position)
	var tiles = _get_tiles_in_radius(origin, building, building.corruption_range)
	
	for tile in tiles:
		# Add +1 to the protection ledger
		safe_tiles[tile] = safe_tiles.get(tile, 0) + 1
		
		# Instantly purge corruption if it exists here!
		if corruption_layer and corruption_layer.get_cell_source_id(tile) != -1:
			corruption_layer.set_cell(tile, -1)

func _remove_safe_zone(building: Building):
	if not "corruption_range" in building or building.corruption_range <= 0: 
		return
	
	var tiles = _get_tiles_in_radius(building.grid_origin, building, building.corruption_range)
	
	for tile in tiles:
		if safe_tiles.has(tile):
			# Subtract 1 from the protection ledger
			safe_tiles[tile] -= 1
			
			# If 0 buildings are protecting it now, remove it entirely
			if safe_tiles[tile] <= 0:
				safe_tiles.erase(tile)

func _add_build_zone(building: Building):
	if not "build_range" in building or building.build_range <= 0: return
	
	var origin = object_layer.local_to_map(building.global_position)
	var tiles = _get_tiles_in_radius(origin, building, building.build_range)
	
	for tile in tiles:
		buildable_tiles[tile] = buildable_tiles.get(tile, 0) + 1

func _remove_build_zone(building: Building):
	if not "build_range" in building or building.build_range <= 0: return
	
	var tiles = _get_tiles_in_radius(building.grid_origin, building, building.build_range)
	
	for tile in tiles:
		if buildable_tiles.has(tile):
			buildable_tiles[tile] -= 1
			if buildable_tiles[tile] <= 0:
				buildable_tiles.erase(tile)
