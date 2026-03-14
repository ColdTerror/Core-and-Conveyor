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
var attack_tiles: Dictionary = {}

# --- VISUALIZER STATES ---
var show_build_grid: bool = false
var show_safe_grid: bool = false
var show_attack_grid: bool = false

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

signal building_selected(building: Building)

signal placement_cost_updated(building_name: String, total_cost: Dictionary, can_afford: bool)
signal placement_ended # Fires when we cancel or finish placing

# --- NEW: CORE TRACKING ---
signal core_placed_event
var is_core_placed: bool = false

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
		# Give it a default direction for the ghost previews
		ghost_building.setup(level_ref, Vector2i.RIGHT)
	elif ghost_building.has_method("setup"):
		ghost_building.setup(level_ref)

	ghost_building.set_ghost(true)
	placing_building = true
	
	# Reset drag state
	is_dragging = false
	_clear_drag_ghosts()
	
	# --- FIXED: Force an immediate position and validity check! ---
	var initial_grid_pos = _get_mouse_grid()
	_update_ghost_position_to(initial_grid_pos)

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
	if not placing_building and not show_build_grid and not show_safe_grid and not show_attack_grid:
		return

	var tile_size = 32.0 
	var half_offset = Vector2(tile_size / 2.0, tile_size / 2.0)
	var b_width = 2.0 # Line width for all borders
	
	# 1. DRAW GLOBAL BUILD ZONES (F1 Hotkey)
	if show_build_grid:
		var build_color = Color(0.2, 1.0, 0.2, 0.15) # Faint green fill
		var build_border_color = Color(0.2, 1.0, 0.2, 0.8) # Solid green border
		
		for tile in buildable_tiles.keys():
			var local_pos = object_layer.map_to_local(tile) - half_offset
			draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), build_color)
			
			var tl = local_pos
			var tr = local_pos + Vector2(tile_size, 0)
			var bl = local_pos + Vector2(0, tile_size)
			var br = local_pos + Vector2(tile_size, tile_size)
			
			if not buildable_tiles.has(tile + Vector2i.UP): draw_line(tl, tr, build_border_color, b_width)
			if not buildable_tiles.has(tile + Vector2i.DOWN): draw_line(bl, br, build_border_color, b_width)
			if not buildable_tiles.has(tile + Vector2i.LEFT): draw_line(tl, bl, build_border_color, b_width)
			if not buildable_tiles.has(tile + Vector2i.RIGHT): draw_line(tr, br, build_border_color, b_width)

	# 2. DRAW GLOBAL SAFE ZONES (F2 Hotkey)
	if show_safe_grid:
		var safe_border_color = Color(0.2, 0.5, 1.0, 0.8) # Solid blue border
		
		for tile in safe_tiles.keys():
			var overlaps = safe_tiles[tile]
			
			# Heat Map Math: Start at 0.15 alpha. Add 0.15 for each overlapping resistance zone. Cap at 0.7.
			var current_alpha = min(0.15 + ((overlaps - 1) * 0.15), 0.7)
			var fill_color = Color(0.2, 0.5, 1.0, current_alpha)
			
			var local_pos = object_layer.map_to_local(tile) - half_offset
			draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), fill_color)
			
			var tl = local_pos
			var tr = local_pos + Vector2(tile_size, 0)
			var bl = local_pos + Vector2(0, tile_size)
			var br = local_pos + Vector2(tile_size, tile_size)
			
			if not safe_tiles.has(tile + Vector2i.UP): draw_line(tl, tr, safe_border_color, b_width)
			if not safe_tiles.has(tile + Vector2i.DOWN): draw_line(bl, br, safe_border_color, b_width)
			if not safe_tiles.has(tile + Vector2i.LEFT): draw_line(tl, bl, safe_border_color, b_width)
			if not safe_tiles.has(tile + Vector2i.RIGHT): draw_line(tr, br, safe_border_color, b_width)
	
	# 3 DRAW GLOBAL ATTACK ZONES (F3 Hotkey)
	if show_attack_grid:
		var attack_border_color = Color(1.0, 0.2, 0.2, 0.8) # Solid red border
		
		for tile in attack_tiles.keys():
			var overlaps = attack_tiles[tile]
			
			# Heat Map Math: Start at 0.15 alpha. Add 0.15 for each overlapping tower. Cap it at 0.7 so it doesn't turn black.
			var current_alpha = min(0.15 + ((overlaps - 1) * 0.15), 0.7)
			var fill_color = Color(1.0, 0.2, 0.2, current_alpha)
			
			var local_pos = object_layer.map_to_local(tile) - half_offset
			draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), fill_color)
			
			var tl = local_pos
			var tr = local_pos + Vector2(tile_size, 0)
			var bl = local_pos + Vector2(0, tile_size)
			var br = local_pos + Vector2(tile_size, tile_size)
			
			# ONLY draw the border if the neighboring tile is completely empty!
			if not attack_tiles.has(tile + Vector2i.UP): draw_line(tl, tr, attack_border_color, b_width)
			if not attack_tiles.has(tile + Vector2i.DOWN): draw_line(bl, br, attack_border_color, b_width)
			if not attack_tiles.has(tile + Vector2i.LEFT): draw_line(tl, bl, attack_border_color, b_width)
			if not attack_tiles.has(tile + Vector2i.RIGHT): draw_line(tr, br, attack_border_color, b_width)
			
	# 4. DRAW GHOST PREVIEWS (When Placing)
	if placing_building:
		var ghosts_to_draw = []
		if is_dragging and drag_ghosts.size() > 0:
			ghosts_to_draw = drag_ghosts
		elif ghost_building:
			ghosts_to_draw = [ghost_building]

		var preview_build = Color(0.5, 1.0, 0.5, 0.15) # Brighter green fill
		var preview_safe = Color(0.5, 0.8, 1.0, 0.15)  # Brighter blue fill

		var unique_safe_tiles = {}
		var unique_build_tiles = {}

		# A. Gather all the tiles without drawing them yet
		for g in ghosts_to_draw:
			if not is_instance_valid(g): continue
			
			var origin = object_layer.local_to_map(g.global_position)
			
			if "corruption_range" in g and g.corruption_range > 0:
				var s_tiles = _get_tiles_in_radius(origin, g, g.corruption_range)
				for t in s_tiles:
					unique_safe_tiles[t] = true 
					
			if "build_range" in g and g.build_range > 0:
				var b_tiles = _get_tiles_in_radius(origin, g, g.build_range)
				for t in b_tiles:
					unique_build_tiles[t] = true

		# B. Draw every collected tile fill exactly ONCE!
		for t in unique_safe_tiles.keys():
			var pos = object_layer.map_to_local(t) - half_offset
			draw_rect(Rect2(pos, Vector2(tile_size, tile_size)), preview_safe)
			
		for t in unique_build_tiles.keys():
			var pos = object_layer.map_to_local(t) - half_offset
			draw_rect(Rect2(pos, Vector2(tile_size, tile_size)), preview_build)

		# C. Draw crisp, color-coded borders around the outer edges
		var build_border_color = Color(0.2, 1.0, 0.2, 0.8) 
		for t in unique_build_tiles.keys():
			var pos = object_layer.map_to_local(t) - half_offset
			var tl = pos                                      
			var tr = pos + Vector2(tile_size, 0)              
			var bl = pos + Vector2(0, tile_size)              
			var br = pos + Vector2(tile_size, tile_size)      
			
			if not unique_build_tiles.has(t + Vector2i.UP): draw_line(tl, tr, build_border_color, b_width)
			if not unique_build_tiles.has(t + Vector2i.DOWN): draw_line(bl, br, build_border_color, b_width)
			if not unique_build_tiles.has(t + Vector2i.LEFT): draw_line(tl, bl, build_border_color, b_width)
			if not unique_build_tiles.has(t + Vector2i.RIGHT): draw_line(tr, br, build_border_color, b_width)

		var safe_border_color = Color(0.2, 0.5, 1.0, 0.8) 
		for t in unique_safe_tiles.keys():
			var pos = object_layer.map_to_local(t) - half_offset
			var tl = pos
			var tr = pos + Vector2(tile_size, 0)
			var bl = pos + Vector2(0, tile_size)
			var br = pos + Vector2(tile_size, tile_size)
			
			if not unique_safe_tiles.has(t + Vector2i.UP): draw_line(tl, tr, safe_border_color, b_width)
			if not unique_safe_tiles.has(t + Vector2i.DOWN): draw_line(bl, br, safe_border_color, b_width)
			if not unique_safe_tiles.has(t + Vector2i.LEFT): draw_line(tl, bl, safe_border_color, b_width)
			if not unique_safe_tiles.has(t + Vector2i.RIGHT): draw_line(tr, br, safe_border_color, b_width)
	
func _on_building_destroyed(b: Building):
	if b in buildings:
		buildings.erase(b)
	
	for tile in b.occupied_tiles:
		if occupied_tiles.has(tile) and occupied_tiles[tile] == b:  # ONLY erase if it's still THIS building
			occupied_tiles.erase(tile)
	
	_remove_safe_zone(b)
	_remove_build_zone(b)
	_remove_attack_zone(b)
	
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
	


func select_building_at(grid_pos: Vector2i):
	if occupied_tiles.has(grid_pos):
		var building = occupied_tiles[grid_pos]
		building_selected.emit(building)

# --- UPDATED: Accepts optional grid position for Dragging ---
func confirm_placement(specific_pos: Vector2i = Vector2i(-1, -1)) -> bool:
	print_debug('try to confirm')
	if not placing_building or ghost_building == null:
		print_debug('fail to confirm')
		return false
	
	var grid_pos = specific_pos
	if grid_pos == Vector2i(-1, -1):
		grid_pos = _get_mouse_grid()

	# ==========================================================
	# NEW: INTERCEPT CONVEYOR BUILD-OVER (FREE ROTATION VS UPGRADE)
	# ==========================================================
	if occupied_tiles.has(grid_pos):
		var existing_building = occupied_tiles[grid_pos]
		if existing_building is ConveyorBuilding and ghost_building is ConveyorBuilding:
			
			# CASE A: Same building type! (Belt on Belt). Do Free Rotation.
			if existing_building.building_name == ghost_building.building_name:
				if existing_building.direction != ghost_building.direction:
					existing_building.direction = ghost_building.direction
					existing_building.rotation = Vector2(ghost_building.direction).angle()
					existing_building.setup(level_ref, ghost_building.direction)
				
				ghost_building.queue_free()
				ghost_building = null
		
				if not is_dragging:
					placing_building = false
					queue_redraw()
					placement_ended.emit()
					
				print_debug('success confirm')
				return true 
				
			# CASE B: Different type! (Router on Belt). Upgrade it!
			else:
				# Destroy the old belt first, then let the rest of the function run 
				# to charge the player and place the Router!
				deconstruct_building_at(grid_pos)
	# ==========================================================
	
	if not _can_place_building(ghost_building, grid_pos):
		print_debug('fail confirm')
		return false
	
	# Check Economy
	var cost = ghost_building.get_build_cost()
	if not EconomyManager.can_afford(cost):
		print_debug('fail confirm')
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
	_add_attack_zone(ghost_building)
	
	# --- NEW: TRIGGER CORRUPTION AND UNLOCK GAME ---
	if ghost_building is CoreBuilding:
		
		# 1. Unlock the building manager!
		is_core_placed = true
		core_placed_event.emit() 
		
		# 2. Trigger Corruption
		if level_ref and level_ref.has_node("CorruptionManager"):
			var corruption_manager = level_ref.get_node("CorruptionManager")
			var core_grid = object_layer.local_to_map(ghost_building.global_position)
			corruption_manager.start_outbreak(core_grid)
			
		# 3. Start the Clock!
		if level_ref.has_node("TimeManager"):
			var time_manager = level_ref.get_node("TimeManager")
			time_manager.is_time_running = true
			print("Core placed! The clock is ticking...")
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
		placement_ended.emit()
	
	print_debug('success confirm')
	return true


func update_placement_cost_ui(chargeable_count: int = 1, is_location_valid: bool = true):
	if not is_instance_valid(ghost_building): return
	
	var can_place = is_location_valid 
	var display_count = chargeable_count
	
	# If every single tile is physically blocked, show the cost of 1 base building in red.
	if not is_location_valid:
		can_place = false
		display_count = 1
		
	var base_cost = ghost_building.get_build_cost()
	var total_cost = {}
	
	for res in base_cost:
		var total_needed = base_cost[res] * display_count
		total_cost[res] = total_needed
		
		# Check against the economy
		var have = EconomyManager.global_inventory.get(res, 0)
		if have < total_needed:
			can_place = false # We are broke!
			
	# Tell the UI! 
	placement_cost_updated.emit(ghost_building.building_name, total_cost, can_place)

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
	
	# --- NEW: Track the valid grid positions and the actual BILL ---
	var current_drag_network: Array[Vector2i] = []
	var chargeable_count: int = 0 
	
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
		var is_free_overwrite = false 
		
		# A. Physical & Expansion Check 
		if not _can_place_building(g, pt, current_drag_network):
			is_valid = false
			
		# --- FIXED: Check if this is a free rotation overwrite (names must match!) ---
		if is_valid and occupied_tiles.has(pt):
			var existing = occupied_tiles[pt]
			if existing is ConveyorBuilding and g is ConveyorBuilding:
				if existing.building_name == g.building_name:
					is_free_overwrite = true
				
		# B. Economic Check 
		if is_valid and not is_free_overwrite:
			var cumulative_cost = _calculate_cumulative_cost(base_cost, chargeable_count + 1)
			if not EconomyManager.can_afford(cumulative_cost):
				is_valid = false
		
		# --- NEW: Only charge money if it's not a free overwrite ---
		if is_valid:
			current_drag_network.append(pt)
			if not is_free_overwrite:
				chargeable_count += 1
		 
		# Apply Visuals
		if g.has_method("set_valid_placement"):
			g.set_valid_placement(is_valid)
		else:
			g.modulate = Color(0, 1, 0, 0.5) if is_valid else Color(1, 0, 0, 0.5)

	# --- FIXED: Tell UI to charge for new belts, but stay green if overwriting! ---
	var is_location_valid = current_drag_network.size() > 0
	update_placement_cost_ui(chargeable_count, is_location_valid)

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
	
	# --- FIXED: Only free if they are the EXACT SAME building! ---
	var is_free = false
	if valid and occupied_tiles.has(grid_pos):
		var existing = occupied_tiles[grid_pos]
		if existing is ConveyorBuilding and ghost_building is ConveyorBuilding:
			if existing.building_name == ghost_building.building_name:
				is_free = true
			
	ghost_building.set_valid_placement(valid)
	
	# --- FIXED: Pass 0 if free, 1 if normal! ---
	update_placement_cost_ui(0 if is_free else 1, valid)

func _get_mouse_grid() -> Vector2i:
	var mouse_global = get_global_mouse_position()
	if not object_layer: return Vector2i.ZERO
	return object_layer.local_to_map(object_layer.to_local(mouse_global))


func _can_place_building(building: Building, origin: Vector2i, temp_network: Array[Vector2i] = []) -> bool:
	if not object_layer: return false
	
	# ==========================================
	# --- NEW: UNIVERSAL CORE BLOCKADE ---
	# ==========================================
	if not is_core_placed and not (building is CoreBuilding):
		print_debug("Place core first")
		return false
	# ==========================================
	
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
			var existing_building = occupied_tiles[tile]
			
			# --- NEW: ALLOW BELT BUILD-OVER ---
			# If both the ghost and the existing building are conveyors, allow it!
			if existing_building is ConveyorBuilding and building is ConveyorBuilding:
				continue 
			# ----------------------------------
			
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
		elif event.keycode == KEY_F3:
			print("show attack key")
			show_attack_grid = not show_attack_grid
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
	
	placement_ended.emit()

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

#--------------------------------------------------------------------------------#
#Add/Remove Visual Zones
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

func _add_attack_zone(building: Building):
	# Make sure it's actually a tower with a pre-calculated range!
	if not "attack_range" in building or not "_cached_range_tiles" in building: return
	
	var origin = object_layer.local_to_map(building.global_position)
	
	for offset in building._cached_range_tiles.keys():
		var tile = origin + offset
		attack_tiles[tile] = attack_tiles.get(tile, 0) + 1

func _remove_attack_zone(building: Building):
	if not "attack_range" in building or not "_cached_range_tiles" in building: return
	
	var origin = building.grid_origin
	
	for offset in building._cached_range_tiles.keys():
		var tile = origin + offset
		if attack_tiles.has(tile):
			attack_tiles[tile] -= 1
			if attack_tiles[tile] <= 0:
				attack_tiles.erase(tile)

#--------------------------------------------------------------------------------#



func deconstruct_building_at(grid_pos: Vector2i):
	if occupied_tiles.has(grid_pos):
		var building = occupied_tiles[grid_pos]

		# --- NEW: Block Core Deletion ---
		if building is CoreBuilding:
			print("Cannot deconstruct the Core!")
			# Optional: Play an error sound or show a floating text warning here
			return # Stop the function immediately!
		# --------------------------------
		
		print("Deconstructed: ", building.building_name)
		
		# Calling die() will trigger the 'destroyed' signal you already set up, 
		# which tells the BuildingManager to clean up the occupied_tiles dictionary!
		building.die()
		
		

# ============================================================================
# UPGRADE SYSTEM
# ============================================================================
func upgrade_building_at(grid_pos: Vector2i) -> bool:
	if not occupied_tiles.has(grid_pos):
		return false
		
	var old_building = occupied_tiles[grid_pos]
	
	if not old_building.upgrades_to:
		return false
	
	# 1. Build the cost dict and check affordability
	var upgrade_cost_dict = {}
	for cost in old_building.upgrade_cost:
		upgrade_cost_dict[cost.item_name] = cost.amount
	
	if not upgrade_cost_dict.is_empty():
		if not EconomyManager.can_afford(upgrade_cost_dict):
			return false
	
	# 2. Save old state
	var old_dir = old_building.direction if "direction" in old_building else Vector2i.RIGHT
	var old_rot = old_building.rotation
	
	# 3. CLEANUP: Force the grid to forget the old building instantly
	_on_building_destroyed(old_building) # Removes from all dictionaries and grids immediately
	old_building.queue_free() # Safely erases the visual node at the end of the frame
	
	# 4. INSTANTIATE: Create the new building
	var new_building = old_building.upgrades_to.instantiate() as Building
	
	# If your place_at handles reparenting to the object_layer, you just need this!
	# (If it doesn't, just keep the add_child line above this one)
	level_ref.object_layer.add_child(new_building) 
	
	# 5. POSITION: Use the building's own internal logic!
	new_building.place_at(grid_pos, level_ref.object_layer)
	new_building.set_ghost(false)
	
	# 6. SETUP: Apply rotation and initialize
	if new_building is ConveyorBuilding:
		new_building.direction = old_dir
		new_building.rotation = old_rot
		new_building.setup(level_ref, old_dir)
	elif new_building.has_method("setup"):
		new_building.setup(level_ref)
	
	# 7. REGISTRATION: Tell the BuildingManager this exists now
	buildings.append(new_building)
	_register_building(new_building)
	_register_occupied_tiles(new_building)
	_add_safe_zone(new_building)
	_add_build_zone(new_building)
	_add_attack_zone(new_building)
	
	# Connect essential signals
	if new_building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
		new_building.fired_projectile.connect(level_ref._on_tower_fired)
	new_building.destroyed.connect(_on_building_destroyed)
	
	# Update pathfinder (Crucial for walls!)
	if pathfinder:
		var footprint = new_building.get_footprint(grid_pos)
		if new_building.is_solid_obstacle:
			for tile in footprint: pathfinder.set_obstacle(tile, true)
		else:
			for tile in footprint: pathfinder.set_weighted_obstacle(tile, new_building.path_cost)
	
	# 8. FINALIZE: Spend the resources ONLY for the upgrade cost
	if not upgrade_cost_dict.is_empty():
		EconomyManager.spend_resources(upgrade_cost_dict)
		
	print("Successfully Upgraded to: ", new_building.building_name)
	return true
