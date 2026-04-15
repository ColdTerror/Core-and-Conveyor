extends Node2D
class_name BuildingManager

# ==========================================
# SIGNALS
# ==========================================
signal building_selected(building: Building)
signal placement_cost_updated(building_name: String, total_cost: Dictionary, can_afford: bool, extra_stats: Dictionary)
signal placement_ended
signal core_placed_event

# ==========================================
# EXPORTS
# ==========================================
@export var object_layer: TileMapLayer
@export var terrain_layer: TileMapLayer
@export var corruption_layer: TileMapLayer
@export var hover_popup: Control
@export var construction_site_scene: PackedScene
@export var terraform_site_scene: PackedScene

# ==========================================
# RUNTIME STATE
# ==========================================

# --- Core ---
var is_core_placed: bool = false
var level_ref: Node2D
var pathfinder: Pathfinder

# --- Building Tracking ---
var buildings: Array[Building] = []
var occupied_tiles := {}          # Key: Vector2i, Value: Building

# --- Zone Tracking ---
# Key: Vector2i, Value: int (overlap count)
var safe_tiles: Dictionary = {}
var buildable_tiles: Dictionary = {}
var attack_tiles: Dictionary = {}

# --- Terraform ---
var terraform_jobs: Dictionary = {} # Key: Vector2i, Value: TerraformSite.JobType

# --- Overlay Toggles (read by MapOverlayManager) ---
var show_build_grid: bool = false
var show_safe_grid: bool = false
var show_attack_grid: bool = false
var show_path_grid: bool = false
var overlay_threshold: int = 1 
var _auto_enabled_grids: Dictionary = {"build": false, "safe": false, "attack": false}

# --- Placement ---
var ghost_building: Building = null
var placing_building: bool = false
var is_dragging: bool = false
var drag_start: Vector2i
var drag_ghosts: Array[Node2D] = []

# ==========================================
# PRIORITY SYSTEM
# ==========================================
# Index 0 = highest priority. Groups use strings, unique buildings use node refs.
var master_priority_queue: Array = []

func _is_grouped_type(building: Node) -> bool:
	return building is ConveyorBuilding or building is WallBuilding or building is TerraformSite

# ==========================================
# SETUP
# ==========================================
func _ready():
	# Listen for any economy changes!
	EconomyManager.inventory_changed.connect(_on_inventory_changed)


			
func initialize(level_instance: Node2D):
	level_ref = level_instance

# ==========================================
# MAIN LOOP
# ==========================================

func _process(delta):
	for b in buildings:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			b.building_tick(delta)
	
	if placing_building:
		queue_redraw()

func _unhandled_input(event):
	_handle_overlay_hotkeys(event)
	
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
		if ghost_building != null:
			cancel_placement()

func _handle_overlay_hotkeys(event):
	if not event is InputEventKey or not event.is_pressed() or event.is_echo(): return
	
	match event.keycode:
		KEY_F1:
			var toggle = not show_build_grid
			_clear_all_overlays()
			show_build_grid = toggle
		KEY_F2:
			var toggle = not show_safe_grid
			_clear_all_overlays()
			show_safe_grid = toggle
		KEY_F3:
			var toggle = not show_attack_grid
			_clear_all_overlays()
			show_attack_grid = toggle
		KEY_F4: 
			var toggle = not show_path_grid
			_clear_all_overlays()
			show_path_grid = toggle
		KEY_EQUAL: # The '+' key 
			overlay_threshold += 1
			print("Overlay Threshold: ", overlay_threshold)
		KEY_MINUS: # The '-' key
			overlay_threshold = max(1, overlay_threshold - 1)
			print("Overlay Threshold: ", overlay_threshold)
		KEY_P:
			_debug_print_priority_queue()

# --- NEW HELPER FUNCTION ---
func _clear_all_overlays():
	show_build_grid = false
	show_safe_grid = false
	show_attack_grid = false
	show_path_grid = false

func _reset_auto_grids():
	# Only turn off the grids that the game turned on automatically
	if _auto_enabled_grids["build"]: show_build_grid = false
	if _auto_enabled_grids["safe"]: show_safe_grid = false
	if _auto_enabled_grids["attack"]: show_attack_grid = false
	
	# Reset the tracker
	_auto_enabled_grids = {"build": false, "safe": false, "attack": false}
	
# ==========================================
# PLACEMENT: PUBLIC API
# ==========================================

func start_placing(scene: PackedScene):
	if scene == null: return

	cancel_placement()

	ghost_building = scene.instantiate() as Building
	
	add_child(ghost_building)
	
	if ghost_building is ConveyorBuilding:
		ghost_building.setup(level_ref, Vector2i.RIGHT)
	elif ghost_building.has_method("setup"):
		ghost_building.setup(level_ref)

	ghost_building.set_ghost(true)
	placing_building = true
	is_dragging = false
	_clear_drag_ghosts()
	
	if not show_build_grid:
		show_build_grid = true
		_auto_enabled_grids["build"] = true
		
			
	if "attack_range" in ghost_building:
		if not show_attack_grid:
			show_attack_grid = true
			_auto_enabled_grids["attack"] = true
			
	
	_update_ghost_position_to(_get_mouse_grid())

func handle_input(event, raw_grid_pos: Vector2i) -> bool:
	if not ghost_building: return false
	
	var current_grid_pos = _get_mouse_grid()

	if not is_dragging:
		_update_ghost_position_to(current_grid_pos)

	if event.is_action_pressed("ui_left"):
		if ghost_building.is_draggable:
			is_dragging = true
			drag_start = current_grid_pos
			_update_drag_line(current_grid_pos)
			ghost_building.visible = false
			return false
		else:
			return confirm_placement()

	if is_dragging and event is InputEventMouseMotion:
		_update_drag_line(current_grid_pos)

	if event.is_action_released("ui_left") and is_dragging:
		ghost_building.visible = true
		_commit_drag_line()
		is_dragging = false
		_clear_drag_ghosts()
		return false

	return false

func confirm_placement(specific_pos: Vector2i = Vector2i(-1, -1)) -> bool:
	if not placing_building or ghost_building == null: return false
	
	var grid_pos = specific_pos if specific_pos != Vector2i(-1, -1) else _get_mouse_grid()

	# Handle conveyor build-over (free rotation vs upgrade)
	if occupied_tiles.has(grid_pos):
		var existing_building = occupied_tiles[grid_pos]
		if existing_building is ConveyorBuilding and ghost_building is ConveyorBuilding:
			if existing_building.building_name == ghost_building.building_name:
				# Same type — free rotation
				if existing_building.direction != ghost_building.direction:
					existing_building.direction = ghost_building.direction
					existing_building.rotation = Vector2(ghost_building.direction).angle()
					existing_building.setup(level_ref, ghost_building.direction)
				ghost_building.queue_free()
				ghost_building = null
				if not is_dragging:
					placing_building = false
					_reset_auto_grids()
					queue_redraw()
					placement_ended.emit()
				return true
			else:
				# Different type — upgrade, destroy old belt first
				deconstruct_building_at(grid_pos)

	if not _can_place_building(ghost_building, grid_pos): return false
	
	var cost = ghost_building.get_build_cost()
	var is_instant = ghost_building is ConveyorBuilding or ghost_building is CoreBuilding or ghost_building.is_draggable or cost.is_empty()
	
	if is_instant and not cost.is_empty():
		if not EconomyManager.can_afford(cost):
			return false # Instantly return false so the ghost gets deleted!
			
	if is_instant:
		_place_instant(ghost_building, grid_pos, cost)
	else:
		_place_blueprint(ghost_building, grid_pos, cost)

	if not is_dragging:
		placing_building = false
		_reset_auto_grids()
		queue_redraw()
		placement_ended.emit()
	
	return true

func cancel_placement():
	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null
	_clear_drag_ghosts()
	is_dragging = false
	placing_building = false
	_reset_auto_grids()
	queue_redraw()
	placement_ended.emit()

func rotate_ghost():
	if not ghost_building or not ghost_building is ConveyorBuilding: return
	
	var dirs = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var idx = dirs.find(ghost_building.direction)
	var new_dir = dirs[(idx + 1) % dirs.size()]
	ghost_building.direction = new_dir
	ghost_building.rotation = Vector2(new_dir).angle()

# ==========================================
# PLACEMENT: INTERNAL
# ==========================================

func _place_instant(building: Building, grid_pos: Vector2i, cost: Dictionary):
	EconomyManager.spend_resources(cost)

	building.set_ghost(false)
	building.place_at(grid_pos, object_layer)
	building.visible = true
	building.modulate = Color(1, 1, 1, 1)
	
	if building is ConveyorBuilding:
		building.setup(level_ref, building.direction)
	elif building.has_method("setup"):
		building.setup(level_ref)
		
	if building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
		building.fired_projectile.connect(level_ref._on_tower_fired)
	building.destroyed.connect(_on_building_destroyed)

	_register_building(building)
	_add_safe_zone(building)
	_add_build_zone(building)
	_add_attack_zone(building)
	
	if building is CoreBuilding:
		_on_core_placed(building, grid_pos)
	
	if pathfinder:
		var footprint = building.get_footprint(grid_pos)
		if building.is_solid_obstacle:
			for tile in footprint: pathfinder.set_obstacle(tile, true)
		else:
			if (building is WallBuilding):
				for tile in footprint: pathfinder.set_weighted_obstacle(tile, building.path_cost, true)
			else:
				for tile in footprint: pathfinder.set_weighted_obstacle(tile, building.path_cost, false)
	
	ghost_building = null

func _place_blueprint(building: Building, grid_pos: Vector2i, cost: Dictionary):
	var site = construction_site_scene.instantiate() as ConstructionSite
	var target_scene = load(building.scene_file_path)

	add_child(site)
	site.setup_blueprint(level_ref, target_scene, cost, building.size, building.building_name)
	site.place_at(grid_pos, object_layer)

	_register_building(site)
	site.destroyed.connect(_on_building_destroyed)
	
	if pathfinder:
		for tile in site.occupied_tiles:
			pathfinder.enemy_astar.set_point_solid(tile, false)
			pathfinder.enemy_astar.set_point_weight_scale(tile, 50.0)
			
	building.queue_free()
	ghost_building = null

func _on_core_placed(building: Building, grid_pos: Vector2i):
	is_core_placed = true
	core_placed_event.emit()
	
	var bot_scene = load("res://scenes/Workers/WorkerBot.tscn")
	for tile in _get_empty_tiles_around(building, 1):
		var new_bot = bot_scene.instantiate()
		level_ref.object_layer.add_child(new_bot)
		new_bot.global_position = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(tile))
		new_bot.setup(level_ref)
		new_bot.clicked.connect(_on_bot_clicked)
		new_bot.hovered.connect(_on_building_hovered)
		new_bot.unhovered.connect(_on_building_unhovered)
	
	if level_ref and level_ref.has_node("CorruptionManager"):
		level_ref.get_node("CorruptionManager").start_outbreak(object_layer.local_to_map(building.global_position))
		
	if level_ref.has_node("TimeManager"):
		level_ref.get_node("TimeManager").is_time_running = true

func _can_place_building(building: Building, origin: Vector2i, temp_network: Array[Vector2i] = []) -> bool:
	if not object_layer: return false
	
	# Core must be placed first
	if not is_core_placed and not (building is CoreBuilding):
		return false

	# Building limit check (excludes belts, walls, and terraforming)
	if not (building is ConveyorBuilding) and not (building is WallBuilding) and not (building is TerraformSite):
		var capped = buildings.filter(func(b): return not (b is ConveyorBuilding) and not (b is WallBuilding) and not (b is TerraformSite))
		if capped.size() >= ResearchManager.max_buildings_allowed:
			return false

	var footprint = building.get_footprint(origin)
	
	# Must touch existing base or drag network
	if buildings.size() > 0 or temp_network.size() > 0:
		var touches_range = false
		for tile in footprint:
			if buildable_tiles.has(tile):
				touches_range = true
				break
			for temp_grid in temp_network:
				if tile.distance_to(temp_grid) <= building.build_range:
					touches_range = true
					break
			if touches_range: break
		if not touches_range: return false

	# No corruption
	for tile in footprint:
		if corruption_layer and corruption_layer.get_cell_source_id(tile) != -1:
			return false

	# Valid buildable terrain
	for tile in footprint:
		if terrain_layer:
			var tile_data = terrain_layer.get_cell_tile_data(tile)
			if tile_data == null: return false
			if tile_data.get_custom_data("buildable") == false: return false

	# No objects on tile
	for tile in footprint:
		if object_layer and object_layer.get_cell_source_id(tile) != -1:
			return false

	# No existing buildings (belts can overlap belts)
	for tile in footprint:
		if occupied_tiles.has(tile):
			var existing = occupied_tiles[tile]
			if existing is ConveyorBuilding and building is ConveyorBuilding:
				continue
			return false

	return true

func update_placement_cost_ui(chargeable_count: int = 1, is_location_valid: bool = true):
	if not is_instance_valid(ghost_building): return
	
	var can_place = is_location_valid
	var display_count = chargeable_count if is_location_valid else 1
		
	var base_cost = ghost_building.get_build_cost()
	var total_cost = {}
	
	var is_instant = ghost_building is ConveyorBuilding or ghost_building is CoreBuilding or ghost_building.is_draggable or base_cost.is_empty()
	
	for res in base_cost:
		var total_needed = base_cost[res] * display_count
		total_cost[res] = total_needed
		# We still calculate if we are missing resources, but we won't 
		# necessarily force can_place to false if it's a drag operation.

	# we only disable can_place if 
	# the location itself is invalid (like dragging over water).
	if not is_location_valid:
		can_place = false

	# (Keep your Building Limit check logic the same below)
	var extra_stats = {}
	if not (ghost_building is ConveyorBuilding) and not (ghost_building is WallBuilding) and not (ghost_building is TerraformSite):
		var capped = buildings.filter(func(b): return not (b is ConveyorBuilding) and not (b is WallBuilding) and not (b is TerraformSite))
		extra_stats["Building Limit"] = "%d / %d" % [capped.size(), ResearchManager.max_buildings_allowed]
		if capped.size() >= ResearchManager.max_buildings_allowed:
			can_place = false
	
	placement_cost_updated.emit(ghost_building.building_name, total_cost, can_place, extra_stats)
func _on_inventory_changed():
	# If we are currently holding a blueprint, re-check the tile we are hovering over!
	if placing_building and is_instance_valid(ghost_building):
		var current_grid_pos = _get_mouse_grid()
		
		if is_dragging:
			_update_drag_line(current_grid_pos)
		else:
			_update_ghost_position_to(current_grid_pos)
			
func _update_ghost_position_to(grid_pos: Vector2i):
	ghost_building.place_at(grid_pos, object_layer)
	var valid = _can_place_building(ghost_building, grid_pos)
	
	var is_free = false
	if valid and occupied_tiles.has(grid_pos):
		var existing = occupied_tiles[grid_pos]
		if existing is ConveyorBuilding and ghost_building is ConveyorBuilding:
			if existing.building_name == ghost_building.building_name:
				is_free = true
				
	if valid and not is_free:
		var cost = ghost_building.get_build_cost()
		var is_instant = ghost_building is ConveyorBuilding or ghost_building is CoreBuilding or ghost_building.is_draggable or cost.is_empty()
		
		if is_instant and not cost.is_empty():
			if not EconomyManager.can_afford(cost):
				valid = false # Turn the ghost red instantly!
				
	ghost_building.set_meta("is_valid", valid)
	
	ghost_building.set_valid_placement(valid)
	update_placement_cost_ui(0 if is_free else 1, valid)

func _get_mouse_grid() -> Vector2i:
	var mouse_global = get_global_mouse_position()
	if not object_layer: return Vector2i.ZERO
	
	var raw_grid = object_layer.local_to_map(object_layer.to_local(mouse_global))
	
	if ghost_building and "size" in ghost_building:
		var offset_x = int((ghost_building.size.x - 1) / 2.0)
		var offset_y = int((ghost_building.size.y - 1) / 2.0)
		return raw_grid - Vector2i(offset_x, offset_y)
		
	return raw_grid

# ==========================================
# DRAG LOGIC
# ==========================================

func _update_drag_line(current_grid: Vector2i):
	var points = _get_straight_line(drag_start, current_grid)
	
	var drag_direction = Vector2i.RIGHT
	if ghost_building is ConveyorBuilding:
		drag_direction = ghost_building.direction
		if points.size() > 1:
			var diff = points[-1] - points[0]
			if abs(diff.x) >= abs(diff.y):
				drag_direction = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
			else:
				drag_direction = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
	
	while drag_ghosts.size() < points.size():
		var new_ghost = ghost_building.duplicate()
		new_ghost.visible = true
		if new_ghost is ConveyorBuilding:
			new_ghost.direction = drag_direction
			new_ghost.rotation = Vector2(drag_direction).angle()
		add_child(new_ghost)
		drag_ghosts.append(new_ghost)
	
	while drag_ghosts.size() > points.size():
		drag_ghosts.pop_back().queue_free()
	
	var base_cost = ghost_building.get_build_cost()
	
	var current_drag_network: Array[Vector2i] = []
	var chargeable_count: int = 0
	var total_requested_count: int = 0
	
	for i in range(points.size()):
		var pt = points[i]
		var g = drag_ghosts[i]
		
		if g is ConveyorBuilding:
			g.direction = drag_direction
			g.rotation = Vector2(drag_direction).angle()
		
		if object_layer:
			g.global_position = object_layer.map_to_local(pt)
		
		var is_valid = _can_place_building(g, pt, current_drag_network)
		var is_free_overwrite = false
		
		if is_valid and occupied_tiles.has(pt):
			var existing = occupied_tiles[pt]
			if existing is ConveyorBuilding and g is ConveyorBuilding:
				if existing.building_name == g.building_name:
					is_free_overwrite = true
		
		if not is_free_overwrite:
			total_requested_count += 1
			
		if is_valid and not is_free_overwrite:
			if not base_cost.is_empty():
				if not EconomyManager.can_afford(_calculate_cumulative_cost(base_cost, chargeable_count + 1)):
					is_valid = false
		
		if is_valid:
			current_drag_network.append(pt)
			if not is_free_overwrite:
				chargeable_count += 1
		
		g.set_meta("is_valid", is_valid)
		
		if g.has_method("set_valid_placement"):
			g.set_valid_placement(is_valid)
		else:
			g.modulate = Color(0, 1, 0, 0.5) if is_valid else Color(1, 0, 0, 0.5)

	update_placement_cost_ui(total_requested_count, current_drag_network.size() > 0)

func _commit_drag_line():
	if drag_ghosts.size() == 0: return
	
	var original_scene = load(ghost_building.scene_file_path)
	
	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null
	
	for g in drag_ghosts:
		ghost_building = g
		var grid_pos = object_layer.local_to_map(object_layer.to_local(g.global_position))
		if not confirm_placement(grid_pos):
			g.queue_free()
			ghost_building = null
			
	drag_ghosts.clear()
	start_placing(original_scene)

func _clear_drag_ghosts():
	for g in drag_ghosts:
		if is_instance_valid(g): g.queue_free()
	drag_ghosts.clear()

# ==========================================
# BUILDING REGISTRATION & DESTRUCTION
# ==========================================

func _register_building(building: Building):
	buildings.append(building)
	_register_occupied_tiles(building)
	
	if _is_grouped_type(building):
		var group_name = ""
		if building is ConveyorBuilding: group_name = "Belts"
		elif building is WallBuilding: group_name = "Walls"
		elif building is TerraformSite: group_name = "Terraform"
		if not master_priority_queue.has(group_name):
			master_priority_queue.append(group_name)
	else:
		if not master_priority_queue.has(building):
			master_priority_queue.append(building)
		
	building.hovered.connect(_on_building_hovered)
	building.unhovered.connect(_on_building_unhovered)

func _register_occupied_tiles(building: Building):
	for tile in building.occupied_tiles:
		occupied_tiles[tile] = building

func _on_building_destroyed(b: Building):
	buildings.erase(b)
	master_priority_queue.erase(b)
		
	for tile in b.occupied_tiles:
		if occupied_tiles.get(tile) == b:
			occupied_tiles.erase(tile)
	
	_remove_safe_zone(b)
	_remove_build_zone(b)
	_remove_attack_zone(b)
	
	if pathfinder:
		for tile in b.occupied_tiles:
			pathfinder.set_obstacle(tile, false)
			pathfinder.set_weighted_obstacle(tile, 1.0)

	if not b.is_upgrading:
		if b.has_method("get_economy_assets"):
			var assets = b.get_economy_assets()
			if not assets.is_empty():
				EconomyManager.remove_resources_from_global(assets)

func register_finished_building(new_building: Building, grid_pos: Vector2i):
	var old_priority_index = -1
	if occupied_tiles.has(grid_pos):
		var old_site = occupied_tiles[grid_pos]
		old_priority_index = master_priority_queue.find(old_site)
		
	_register_building(new_building)
	if old_priority_index != -1 and not _is_grouped_type(new_building):
		master_priority_queue.erase(new_building)
		master_priority_queue.insert(old_priority_index, new_building)
	_add_safe_zone(new_building)
	_add_build_zone(new_building)
	_add_attack_zone(new_building)
	
	if new_building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
		new_building.fired_projectile.connect(level_ref._on_tower_fired)
	new_building.destroyed.connect(_on_building_destroyed)
	
	if pathfinder:
		var footprint = new_building.get_footprint(grid_pos)
		if new_building.is_solid_obstacle:
			for tile in footprint: pathfinder.set_obstacle(tile, true)
		else:
			if (new_building is WallBuilding):
				for tile in footprint: pathfinder.set_weighted_obstacle(tile, new_building.path_cost, true)
			else:
				for tile in footprint: pathfinder.set_weighted_obstacle(tile, new_building.path_cost, false)

func select_building_at(grid_pos: Vector2i):
	if occupied_tiles.has(grid_pos):
		building_selected.emit(occupied_tiles[grid_pos])

func deconstruct_building_at(grid_pos: Vector2i):
	if not occupied_tiles.has(grid_pos): return
	var building = occupied_tiles[grid_pos]
	if building is CoreBuilding:
		print("Cannot deconstruct the Core!")
		return
	building.die()

# ==========================================
# ZONE TRACKING
# ==========================================

func _get_tiles_in_radius(origin: Vector2i, building: Building, radius: float) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var tile_size = 32.0
	var b_size = building.size if "size" in building else Vector2i(1, 1)
	
	var center_pos = building.global_position
	var half_w = (b_size.x * tile_size) / 2.0
	var half_h = (b_size.y * tile_size) / 2.0
	var rect_x_min = center_pos.x - half_w
	var rect_x_max = center_pos.x + half_w
	var rect_y_min = center_pos.y - half_h
	var rect_y_max = center_pos.y + half_h
	
	var search_radius = ceil(radius) + max(b_size.x, b_size.y)
	var max_dist_px = radius * tile_size
	
	for x in range(origin.x - search_radius, origin.x + search_radius + 1):
		for y in range(origin.y - search_radius, origin.y + search_radius + 1):
			var tile_pos = Vector2i(x, y)
			var tile_center = object_layer.map_to_local(tile_pos)
			var dx = max(0.0, max(rect_x_min - tile_center.x, tile_center.x - rect_x_max))
			var dy = max(0.0, max(rect_y_min - tile_center.y, tile_center.y - rect_y_max))
			if Vector2(dx, dy).length() <= max_dist_px:
				tiles.append(tile_pos)
				
	return tiles

func _add_safe_zone(building: Building):
	if not "corruption_range" in building or building.corruption_range <= 0: return
	var origin = object_layer.local_to_map(building.global_position)
	for tile in _get_tiles_in_radius(origin, building, building.corruption_range):
		safe_tiles[tile] = safe_tiles.get(tile, 0) + 1
		if corruption_layer and corruption_layer.get_cell_source_id(tile) != -1:
			corruption_layer.set_cell(tile, -1)

func _remove_safe_zone(building: Building):
	if not "corruption_range" in building or building.corruption_range <= 0: return
	for tile in _get_tiles_in_radius(building.grid_origin, building, building.corruption_range):
		if safe_tiles.has(tile):
			safe_tiles[tile] -= 1
			if safe_tiles[tile] <= 0: safe_tiles.erase(tile)

func _add_build_zone(building: Building):
	if not "build_range" in building or building.build_range <= 0: return
	var origin = object_layer.local_to_map(building.global_position)
	for tile in _get_tiles_in_radius(origin, building, building.build_range):
		buildable_tiles[tile] = buildable_tiles.get(tile, 0) + 1

func _remove_build_zone(building: Building):
	if not "build_range" in building or building.build_range <= 0: return
	for tile in _get_tiles_in_radius(building.grid_origin, building, building.build_range):
		if buildable_tiles.has(tile):
			buildable_tiles[tile] -= 1
			if buildable_tiles[tile] <= 0: buildable_tiles.erase(tile)

func _add_attack_zone(building: Building):
	if not "attack_range" in building or not "_cached_range_tiles" in building: return
	var origin = object_layer.local_to_map(building.global_position)
	for offset in building._cached_range_tiles.keys():
		var tile = origin + offset
		attack_tiles[tile] = attack_tiles.get(tile, 0) + 1

func _remove_attack_zone(building: Building):
	if not "attack_range" in building or not "_cached_range_tiles" in building: return
	for offset in building._cached_range_tiles.keys():
		var tile = building.grid_origin + offset
		if attack_tiles.has(tile):
			attack_tiles[tile] -= 1
			if attack_tiles[tile] <= 0: attack_tiles.erase(tile)

# ==========================================
# UPGRADE SYSTEM
# ==========================================

func upgrade_building_at(grid_pos: Vector2i) -> bool:
	if not occupied_tiles.has(grid_pos): return false
	var old_building = occupied_tiles[grid_pos]
	if not old_building.upgrades_to: return false
	
	var upgrade_cost_dict = {}
	for cost in old_building.upgrade_cost:
		upgrade_cost_dict[cost.item_name] = cost.amount
	
	if not upgrade_cost_dict.is_empty() and not EconomyManager.can_afford(upgrade_cost_dict):
		return false
	
	var old_dir = old_building.direction if "direction" in old_building else Vector2i.RIGHT
	var old_rot = old_building.rotation
	var true_origin = old_building.grid_origin

	var old_priority_index = master_priority_queue.find(old_building)
	
	# EXTRACT DATA BEFORE DESTRUCTION
	var saved_data = old_building.get_upgrade_data()
	old_building.is_upgrading = true # Tell the system not to delete the global items!
	
	_on_building_destroyed(old_building)
	old_building.queue_free()
	
	# SPAWN NEW BUILDING

	var new_building = old_building.upgrades_to.instantiate() as Building
	add_child(new_building)
	new_building.place_at(true_origin, level_ref.object_layer)
	new_building.set_ghost(false)
	
	if new_building is ConveyorBuilding:
		new_building.direction = old_dir
		new_building.rotation = old_rot
		new_building.setup(level_ref, old_dir)
	elif new_building.has_method("setup"):
		new_building.setup(level_ref)
		
	# INJECT DATA INTO NEW BUILDING
	new_building.apply_upgrade_data(saved_data)
	
	_register_building(new_building)
	
	if old_priority_index != -1 and not _is_grouped_type(new_building):
		master_priority_queue.erase(new_building) # Take it off the bottom
		master_priority_queue.insert(old_priority_index, new_building) # Put it in the old spot!
		
	_add_safe_zone(new_building)
	_add_build_zone(new_building)
	_add_attack_zone(new_building)
	
	if new_building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
		new_building.fired_projectile.connect(level_ref._on_tower_fired)
	new_building.destroyed.connect(_on_building_destroyed)
	
	if pathfinder:
		var footprint = new_building.get_footprint(grid_pos)
		if new_building.is_solid_obstacle:
			for tile in footprint: pathfinder.set_obstacle(tile, true)
		else:
			if (new_building is WallBuilding):
				for tile in footprint: pathfinder.set_weighted_obstacle(tile, new_building.path_cost, true)
			else:
				for tile in footprint: pathfinder.set_weighted_obstacle(tile, new_building.path_cost, false)
	
	if not upgrade_cost_dict.is_empty():
		EconomyManager.spend_resources(upgrade_cost_dict)
		
	return true
	
func show_upgrade_preview(grid_pos: Vector2i):
	if not occupied_tiles.has(grid_pos):
		placement_ended.emit()
		return
		
	var b = occupied_tiles[grid_pos]
	
	if not b.upgrades_to:
		placement_cost_updated.emit(b.building_name + " (Max Tier)", {}, false, {})
		return

	var upgrade_cost_dict = {}
	for cost in b.upgrade_cost:
		upgrade_cost_dict[cost.item_name if "item_name" in cost else cost] = cost.amount if "amount" in cost else b.upgrade_cost[cost]
	
	var can_afford = upgrade_cost_dict.is_empty() or EconomyManager.can_afford(upgrade_cost_dict)
	var stats = _get_upgrade_stats(b)
	
	placement_cost_updated.emit("Upgrade " + b.building_name, upgrade_cost_dict, can_afford, stats)

func _get_upgrade_stats(b: Building) -> Dictionary:
	var stats = {}
	var temp = b.upgrades_to.instantiate()
	
	if "max_health" in b and "max_health" in temp and b.max_health != temp.max_health:
		stats["HP"] = "%d -> %d" % [b.max_health, temp.max_health]
	if "crafting_time_multiplier" in b and "crafting_time_multiplier" in temp and b.crafting_time_multiplier != temp.crafting_time_multiplier:
		stats["Craft Time"] = "%d%% -> %d%%" % [int(b.crafting_time_multiplier * 100), int(temp.crafting_time_multiplier * 100)]
	if "scan_radius" in b and "scan_radius" in temp and b.scan_radius != temp.scan_radius:
		stats["Harvest Radius"] = "%d -> %d" % [b.scan_radius, temp.scan_radius]
	if "harvest_damage" in b and "harvest_damage" in temp and b.harvest_damage != temp.harvest_damage:
		stats["Harvest Amount"] = "%d -> %d" % [b.harvest_damage, temp.harvest_damage]
	if "work_interval" in b and "work_interval" in temp and b.work_interval != temp.work_interval:
		stats["Time Per Harvest"] = "%.2fs -> %.2fs" % [b.work_interval, temp.work_interval]
	if "attack_range" in b and "attack_range" in temp and b.attack_range != temp.attack_range:
		stats["Attack Range"] = "%d -> %d Tiles" % [int(b.attack_range / 32.0), int(temp.attack_range / 32.0)]
	if "fire_rate" in b and "fire_rate" in temp and b.fire_rate != temp.fire_rate:
		stats["Fire Rate"] = "%d -> %d/s" % [b.fire_rate, temp.fire_rate]
	if "damage_multiplier" in b and "damage_multiplier" in temp and b.damage_multiplier != temp.damage_multiplier:
		stats["Damage Multiplier"] = "%.2fx -> %.2fx" % [b.damage_multiplier, temp.damage_multiplier]
	
	temp.queue_free()
	return stats

# ==========================================
# TERRAFORM
# ==========================================

func _try_add_terrain_job(grid_pos: Vector2i):
	if occupied_tiles.has(grid_pos): return
		
	var job_type = -1
	if object_layer.get_cell_source_id(grid_pos) != -1 or level_ref.active_grid_objects.has(grid_pos):
		job_type = TerraformSite.JobType.REMOVE_OBJECT
	elif terrain_layer:
		var tile_data = terrain_layer.get_cell_tile_data(grid_pos)
		if tile_data != null and tile_data.get_custom_data("buildable") == false:
			job_type = TerraformSite.JobType.CONVERT_WATER
			
	if job_type == -1:
		print("Nothing to remove at: ", grid_pos)
		return
		
	var site = terraform_site_scene.instantiate() as TerraformSite
	add_child(site)
	site.setup(level_ref, grid_pos, job_type)
	terraform_jobs[grid_pos] = job_type
	_register_building(site)
	site.destroyed.connect(_on_building_destroyed)
	site.destroyed.connect(func(_b): terraform_jobs.erase(grid_pos))

# ==========================================
# PRIORITY SYSTEM
# ==========================================

func get_highest_priority_job(bot_position: Vector2) -> Node:
	for item in master_priority_queue:
		if typeof(item) == TYPE_STRING:
			var best = _find_closest_needing_work_in_group(item, bot_position)
			if best != null: return best
		else:
			if is_instance_valid(item) and _building_needs_work(item):
				return item
	return null

func _building_needs_work(bldg: Node) -> bool:
	if bldg.has_method("needs_materials") and bldg.needs_materials(): return true
	if bldg.health < bldg.max_health: return true
	return false

func _find_closest_needing_work_in_group(group_name: String, bot_pos: Vector2) -> Node:
	var best_dist = INF
	var best_target = null
	
	for b in buildings:
		var matches = (group_name == "Belts" and b is ConveyorBuilding) or \
					  (group_name == "Walls" and b is WallBuilding) or \
					  (group_name == "Terraform" and b is TerraformSite)
		if matches and _building_needs_work(b):
			var dist = bot_pos.distance_squared_to(b.global_position)
			if dist < best_dist:
				best_dist = dist
				best_target = b
				
	return best_target

func get_priority_rank(item: Variant) -> int:
	var idx = master_priority_queue.find(item)
	return idx + 1 if idx != -1 else 0

func get_total_priority_ranks() -> int:
	return master_priority_queue.size()

func move_priority_up(item: Variant):
	var idx = master_priority_queue.find(item)
	if idx > 0:
		var temp = master_priority_queue[idx - 1]
		master_priority_queue[idx - 1] = item
		master_priority_queue[idx] = temp

func move_priority_down(item: Variant):
	var idx = master_priority_queue.find(item)
	if idx != -1 and idx < master_priority_queue.size() - 1:
		var temp = master_priority_queue[idx + 1]
		master_priority_queue[idx + 1] = item
		master_priority_queue[idx] = temp

# ==========================================
# BOT SPAWNING HELPER
# ==========================================

func _get_empty_tiles_around(building: Building, count: int) -> Array[Vector2i]:
	var valid_tiles: Array[Vector2i] = []
	var origin = building.grid_origin
	var search_radius = 1
	
	while valid_tiles.size() < count and search_radius < 10:
		for x in range(origin.x - search_radius, origin.x + building.size.x + search_radius):
			for y in range(origin.y - search_radius, origin.y + building.size.y + search_radius):
				var check_tile = Vector2i(x, y)
				if building.occupied_tiles.has(check_tile): continue
				if valid_tiles.has(check_tile): continue
				if pathfinder and pathfinder.enemy_astar.is_in_boundsv(check_tile):
					if not pathfinder.enemy_astar.is_point_solid(check_tile):
						valid_tiles.append(check_tile)
						if valid_tiles.size() >= count: return valid_tiles
		search_radius += 1
		
	return valid_tiles

# ==========================================
# MATH HELPERS
# ==========================================

func _get_straight_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var diff = end - start
	var final_end = end
	
	if abs(diff.x) >= abs(diff.y): final_end.y = start.y
	else: final_end.x = start.x
		
	var current = start
	var step = Vector2i(
		sign(final_end.x - start.x) if final_end.x != start.x else 0,
		sign(final_end.y - start.y) if final_end.y != start.y else 0
	)
	
	for _i in range(100):
		points.append(current)
		if current == final_end: break
		current += step
		
	return points

func _calculate_cumulative_cost(base_cost: Dictionary, quantity: int) -> Dictionary:
	var total = {}
	for resource_name in base_cost:
		total[resource_name] = base_cost[resource_name] * quantity
	return total

# ==========================================
# UI & HOVER EVENTS
# ==========================================

func _on_building_hovered(building: Node2D):
	if hover_popup:
		hover_popup.show_building_info(building)

func _on_building_unhovered(building: Node2D):
	if hover_popup and hover_popup.current_building == building:
		hover_popup.hide_popup()

func _on_bot_clicked(bot: Node2D):
	building_selected.emit(bot)

# ==========================================
# DEBUG
# ==========================================

func _debug_print_priority_queue():
	print("\n=== MASTER PRIORITY QUEUE ===")
	for i in range(master_priority_queue.size()):
		var item = master_priority_queue[i]
		var rank = i + 1
		if typeof(item) == TYPE_STRING:
			print("Rank %d: [GROUP] %s" % [rank, item])
		elif is_instance_valid(item):
			print("Rank %d: %s at %s" % [rank, item.building_name, item.global_position])
		else:
			print("Rank %d: [DELETED]" % rank)
	print("=============================\n")
	
# ==========================================
# SAVE / LOAD SYSTEM (BuildingManager)
# ==========================================
func get_save_data() -> Dictionary:
	var saved_buildings = []

	for b in buildings:
		# Don't save transparent placement ghosts, and don't save half-finished construction sites (yet)
		if not is_instance_valid(b) or b.is_ghost: 
			continue

		# 1. Ask the specific building to pack its own unique data!
		var b_data = b.get_save_data() if b.has_method("get_save_data") else {}

		# 2. Stamp the Spawner Data on the outside of the box
		b_data["scene_file_path"] = b.scene_file_path
		b_data["grid_origin_x"] = b.grid_origin.x
		b_data["grid_origin_y"] = b.grid_origin.y

		saved_buildings.append(b_data)

	return {
		"is_core_placed": is_core_placed,
		"buildings": saved_buildings
	}

func load_save_data(data: Dictionary):
	is_core_placed = data.get("is_core_placed", false)

	if not data.has("buildings"): return

	for b_data in data["buildings"]:
		var path = b_data.get("scene_file_path", "")
		
		if path == "" or not ResourceLoader.exists(path):
			print("WARNING: Could not find scene file at: ", path)
			continue

		# 1. Spawn the blueprint!
		var new_building = load(path).instantiate() as Building
		add_child(new_building)

		var grid_pos = Vector2i(b_data["grid_origin_x"], b_data["grid_origin_y"])
		new_building.place_at(grid_pos, object_layer)
		new_building.set_ghost(false)

		# 2. Run the Initial Setup
		if new_building is ConveyorBuilding:
			# Conveyors need their direction *before* setup so they rotate correctly
			var temp_dir = str_to_var(b_data.get("direction", "Vector2i(1, 0)"))
			new_building.setup(level_ref, temp_dir)
		elif new_building.has_method("setup"):
			new_building.setup(level_ref)

		# 3. Hand the packed box back to the building so it can unpack its health/inventory!
		if new_building.has_method("load_save_data"):
			new_building.load_save_data(b_data)

		# 4. Silently register it to the map (Bypassing the economy spending!)
		_register_building(new_building)
		_add_safe_zone(new_building)
		_add_build_zone(new_building)
		_add_attack_zone(new_building)

		if new_building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
			new_building.fired_projectile.connect(level_ref._on_tower_fired)
			
		new_building.destroyed.connect(_on_building_destroyed)

		# 5. Tell the pathfinder to navigate around it
		if pathfinder:
			var footprint = new_building.get_footprint(grid_pos)
			if new_building.is_solid_obstacle:
				for tile in footprint: pathfinder.set_obstacle(tile, true)
			else:
				if (new_building is WallBuilding):
					for tile in footprint: pathfinder.set_weighted_obstacle(tile, new_building.path_cost, true)
				else:
					for tile in footprint: pathfinder.set_weighted_obstacle(tile, new_building.path_cost, false)
