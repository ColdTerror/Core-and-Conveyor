# ==============================================================================
# Script: Managers/building_manager.gd
# Purpose: Core coordinator that manages all building states, grid/tile occupation maps, range overlay grids, dragging/placement blueprints, upgrades, and bot job prioritizations.
# Dependencies: Requires TileMapLayers (object, terrain, corruption, wall), hover popup Control, and integrates with Pathfinder and EconomyManager.
# Signals:
#   - placement_cost_updated: Emitted to update building blueprint preview costs.
#   - placement_ended: Emitted when building placement mode cancels or finishes.
#   - core_placed_event: Emitted when the first core building is placed.
# ==============================================================================
class_name BuildingManager
extends Node2D


signal placement_cost_updated(building_name: String, total_cost: Dictionary, can_afford: bool, extra_stats: Dictionary)
signal placement_ended
signal core_placed_event

@export_group("Layers")
@export var object_layer: TileMapLayer
@export var terrain_layer: TileMapLayer
@export var corruption_layer: TileMapLayer
@export var wall_layer: TileMapLayer 

@export_group("UI & Visuals")
@export var hover_popup: Control
@export var construction_site_scene: PackedScene
@export var terraform_site_scene: PackedScene

var is_core_placed: bool = false
var level_ref: Node2D
var pathfinder: Pathfinder

var buildings: Array[Building] = []
var occupied_tiles := {}

var safe_tiles: Dictionary = {}
var buildable_tiles: Dictionary = {}
var attack_tiles: Dictionary = {}

var terraform_jobs: Dictionary = {}

var show_build_grid: bool = false
var show_safe_grid: bool = false
var show_attack_grid: bool = false
var show_path_grid: bool = false
var overlay_threshold: int = 1 
var show_overlay_numbers: bool = true
var _auto_enabled_grids: Dictionary = {"build": false, "safe": false, "attack": false}

var ghost_building: Building = null
var placing_building: bool = false
var is_dragging: bool = false
var drag_start: Vector2i
var drag_ghosts: Array[Node2D] = []

var is_relocating: bool = false
var relocate_saved_pos: Vector2i
var relocate_saved_scene: PackedScene
var relocate_saved_data: Dictionary = {}
var relocate_saved_inventory: Dictionary = {}

var master_priority_queue: Array = []



func _is_grouped_type(building: Node) -> bool:
	if building is ConveyorBuilding or building is WallBuilding or building is TerraformSite:
		return true
		
	# Check the blueprint name to identify construction sites for grouped types
	if building is ConstructionSite:
		var b_name = building.building_name
		if "Wall" in b_name or "Conveyor" in b_name or "Belt" in b_name or "Router" in b_name or "Filter" in b_name:
			return true
			
	return false



func _counts_towards_limit(building: Node) -> bool:
	return not _is_grouped_type(building)



func _ready():
	EconomyManager.inventory_changed.connect(_on_inventory_changed)



func _process(delta):
	for b in buildings:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			b.building_tick(delta)
	
	if placing_building:
		queue_redraw()



## Initializes the manager with the level instance reference.
func initialize(level_instance: Node2D):
	level_ref = level_instance



## Handles overlay grid toggle hotkeys and threshold adjustments.
func handle_overlay_hotkeys(keycode: int):
	match keycode:
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
		KEY_N:
			show_overlay_numbers = not show_overlay_numbers



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
	
	_auto_enabled_grids = {"build": false, "safe": false, "attack": false}



## Starts the placement mode for a specific building scene.
func start_placing(scene: PackedScene):
	if scene == null: return

	if placing_building:
		cancel_placement()
	elif ghost_building:
		# Safety net: quietly clean up any orphaned ghost without triggering a rescue
		ghost_building.queue_free()
		ghost_building = null

	ghost_building = scene.instantiate() as Building
	ghost_building.set_ghost(true)
	
	add_child(ghost_building)
	
	if ghost_building is ConveyorBuilding:
		ghost_building.setup(level_ref, Vector2i.RIGHT)
	elif ghost_building.has_method("setup"):
		ghost_building.setup(level_ref)

	placing_building = true
	is_dragging = false
	_clear_drag_ghosts()
	
	InputManager.current_mode = InputManager.InteractionMode.PLACE_BUILDING
		
	if not show_build_grid:
		show_build_grid = true
		_auto_enabled_grids["build"] = true
		
	if "attack_range" in ghost_building:
		if not show_attack_grid:
			show_attack_grid = true
			_auto_enabled_grids["attack"] = true
	
	_update_ghost_position_to(_get_mouse_grid())



## Initiates relocation for an existing building.
func start_relocating(building: Building):
	if not is_instance_valid(building): return
	
	var scene_path = building.scene_file_path
	var target_scene = load(scene_path)
	
	relocate_saved_pos = building.grid_origin
	relocate_saved_scene = target_scene
	
	relocate_saved_data.clear()
	if building.has_method("get_upgrade_data"):
		relocate_saved_data = building.get_upgrade_data()
		
	relocate_saved_inventory.clear()
	if building.has_method("get_economy_assets"):
		relocate_saved_inventory = building.get_economy_assets().duplicate()
		
	# Cleanly remove the old building to enforce the Teleport Tax
	_on_building_destroyed(building)
	building.queue_free()
	
	# Trigger standard placement with our special flags active!
	start_placing(target_scene)
	is_relocating = true



## Process user input for placement mode, supporting drag-placement if enabled.
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



## Confirms the placement of the current ghost building at the target grid position.
func confirm_placement(specific_pos: Vector2i = Vector2i(-1, -1)) -> bool:
	if not placing_building or ghost_building == null: return false
	
	var grid_pos = specific_pos if specific_pos != Vector2i(-1, -1) else _get_mouse_grid()

	var cost = ghost_building.get_build_cost()
	var is_instant = ghost_building is ConveyorBuilding or ghost_building is CoreBuilding or cost.is_empty()
	
	if is_instant and not cost.is_empty():
		if not EconomyManager.can_afford(cost):
			return false

	# Handle conveyor build-over (free rotation vs upgrade)
	if occupied_tiles.has(grid_pos):
		var existing_building = occupied_tiles[grid_pos]
		if existing_building is ConveyorBuilding and ghost_building is ConveyorBuilding:
			var existing_is_advanced = existing_building is RouterBuilding or existing_building is ConveyorBridge
			var ghost_is_advanced = ghost_building is RouterBuilding or ghost_building is ConveyorBridge
			
			if existing_is_advanced and not ghost_is_advanced:
				ghost_building.queue_free()
				ghost_building = null
				return true
				
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

	# Check placement rules (must happen AFTER deconstructing the old belt)
	if not _can_place_building(ghost_building, grid_pos): return false
			
	# Place the building!
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



## Cancels placement mode, restoring relocated buildings to their original positions if necessary.
func cancel_placement():
	# If canceling a relocate, place the building back where it was fully finished, no tax
	if is_relocating and relocate_saved_scene != null:
		var restored_building = relocate_saved_scene.instantiate() as Building
		add_child(restored_building)
		
		if restored_building.has_method("apply_upgrade_data"):
			restored_building.apply_upgrade_data(relocate_saved_data)
			
		_place_instant(restored_building, relocate_saved_pos, {})
		
		if restored_building.has_method("add_item"):
			for item_name in relocate_saved_inventory.keys():
				var amount = relocate_saved_inventory[item_name]
				var item_res = ItemDatabase.get_item(item_name)
				if item_res:
					restored_building.add_item(item_res, amount)

	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null
		
	_clear_drag_ghosts()
	is_dragging = false
	placing_building = false
	is_relocating = false
	relocate_saved_scene = null
	relocate_saved_data.clear()
	relocate_saved_inventory.clear()
	
	_reset_auto_grids()
	queue_redraw()
	placement_ended.emit()
	
	# Give the mouse back to the world
	InputManager.current_mode = InputManager.InteractionMode.NONE



## Rotates the ghost building blueprint if rotation is supported by its type.
func rotate_ghost():
	if not ghost_building: return
	
	if ghost_building is ConveyorBuilding:
		var dirs = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
		var idx = dirs.find(ghost_building.direction)
		var new_dir = dirs[(idx + 1) % dirs.size()]
		ghost_building.direction = new_dir
		ghost_building.rotation = Vector2(new_dir).angle()
		
	elif ghost_building is GateBuilding:
		ghost_building.is_horizontal = not ghost_building.is_horizontal
		
		# Force the manager to redraw the placement indicators
		_update_ghost_position_to(_get_mouse_grid())



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
	
	_register_building_pathfinder(building, grid_pos)
	
	if building == ghost_building:
		ghost_building = null



func _place_blueprint(building: Building, grid_pos: Vector2i, cost: Dictionary):
	var site = construction_site_scene.instantiate() as ConstructionSite
	var target_scene = load(building.scene_file_path)

	add_child(site)
	site.setup_blueprint(level_ref, target_scene, cost, building.size, building.building_name)
	
	var final_blueprint_data = {}
	
	if is_relocating:
		# Enforce the wear and tear tax on relocated buildings
		for item_name in site.required_items.keys():
			var total_needed = site.required_items[item_name]
			# Pre-fill exactly half the cost (Salvaged from the old building)
			site.delivered_items[item_name] = floor(total_needed / 2.0)
			
		# Automatically apply existing inventory from relocation to the site
		for item_name in site.required_items.keys():
			if relocate_saved_inventory.has(item_name):
				# Calculate what is still needed after the salvage tax
				var needed = site.required_items[item_name] - site.delivered_items.get(item_name, 0)
				var available = relocate_saved_inventory[item_name]
				var to_consume = min(needed, available)
				
				if to_consume > 0:
					site.delivered_items[item_name] = site.delivered_items.get(item_name, 0) + to_consume
					
					relocate_saved_inventory[item_name] -= to_consume
					if relocate_saved_inventory[item_name] <= 0:
						relocate_saved_inventory.erase(item_name)
						
		# Merge the configuration and the leftover inventory
		final_blueprint_data = relocate_saved_data.duplicate()
		if not relocate_saved_inventory.is_empty():
			final_blueprint_data["saved_inventory"] = relocate_saved_inventory.duplicate()
			
		is_relocating = false
		relocate_saved_data.clear()
		relocate_saved_inventory.clear()
	else:
		# Extract rotation/configuration data from the transparent ghost
		if building.has_method("get_upgrade_data"):
			final_blueprint_data = building.get_upgrade_data()
			
	if not final_blueprint_data.is_empty():
		site.set_meta("blueprint_data", final_blueprint_data)
	
	# Wake up the construction site to process existing resources
	if site.has_method("evaluate_requirements"):
		site.evaluate_requirements()
		
	site.place_at(grid_pos, object_layer)

	_register_building(site)
	site.destroyed.connect(_on_building_destroyed)
	
	if pathfinder:
		for tile in site.occupied_tiles:
			pathfinder.enemy_astar.set_point_solid(tile, false)
			pathfinder.enemy_astar.set_point_weight_scale(tile, 50.0)
			
			pathfinder.bot_astar.set_point_solid(tile, false)
			pathfinder.bot_astar.set_point_weight_scale(tile, 50.0)
			
	building.queue_free()
	if building == ghost_building:
		ghost_building = null



## Adds wall tiles and connects them using autotiling.
func add_wall_visual(tiles: Array[Vector2i]):
	if not wall_layer: return
	wall_layer.set_cells_terrain_connect(tiles, 0, 0)



## Removes wall tiles and updates connection states of surrounding wall neighbors.
func remove_wall_visual(tiles: Array[Vector2i]):
	if not wall_layer: return
	
	# Erase all the tiles completely
	for tile in tiles:
		wall_layer.set_cell(tile, -1)
	
	# Gather only neighbors that actually have wall tiles in them
	var neighbors: Array[Vector2i] = []
	for tile in tiles:
		var check_tiles = [
			tile + Vector2i(0, -1),
			tile + Vector2i(0, 1),
			tile + Vector2i(-1, 0),
			tile + Vector2i(1, 0)
		]
		for n in check_tiles:
			if wall_layer.get_cell_source_id(n) != -1 and not neighbors.has(n):
				neighbors.append(n)
	
	# Force the neighbors to update so they don't connect to thin air
	if not neighbors.is_empty():
		wall_layer.set_cells_terrain_connect(neighbors, 0, 0, false)



func _can_place_building(building: Building, origin: Vector2i, temp_network: Array[Vector2i] = []) -> bool:
	if not object_layer: return false
	
	# Core must be placed first
	if not is_core_placed and not (building is CoreBuilding):
		return false

	# Building limit check (excludes belts, walls, and terraforming)
	if _counts_towards_limit(building):
		var capped = buildings.filter(func(b): return _counts_towards_limit(b))
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

	# Check required terrain constraint
	if building.required_terrain_coords != Vector2i(-9999, -9999):
		var has_required_terrain = false
		for tile in footprint:
			if terrain_layer:
				var coords = terrain_layer.get_cell_atlas_coords(tile)
				if coords == building.required_terrain_coords:
					has_required_terrain = true
					break
		if not has_required_terrain:
			return false

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



## Updates the placement UI costs based on the quantity and validity of the current blueprint action.
func update_placement_cost_ui(chargeable_count: int = 1, is_location_valid: bool = true):
	if not is_instance_valid(ghost_building): return
	
	var can_place = is_location_valid
	var display_count = chargeable_count if is_location_valid else 1
		
	var base_cost = ghost_building.get_build_cost()
	var total_cost = {}
	
	var is_instant = ghost_building is ConveyorBuilding or ghost_building is CoreBuilding or base_cost.is_empty()
	
	for res in base_cost:
		var total_needed = base_cost[res] * display_count
		total_cost[res] = total_needed

	# Disable can_place if the location itself is invalid
	if not is_location_valid:
		can_place = false

	var extra_stats = {}
	if _counts_towards_limit(ghost_building):
		var capped = buildings.filter(func(b): return _counts_towards_limit(b))
		extra_stats["Building Limit"] = "%d / %d" % [capped.size(), ResearchManager.max_buildings_allowed]
		if capped.size() >= ResearchManager.max_buildings_allowed:
			can_place = false
	
	placement_cost_updated.emit(ghost_building.building_name, total_cost, can_place, extra_stats)



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
		var is_instant = ghost_building is ConveyorBuilding or ghost_building is CoreBuilding or cost.is_empty()
		
		if is_instant and not cost.is_empty():
			if not EconomyManager.can_afford(cost):
				valid = false
				
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



func _register_building(building: Building):
	if building.is_ghost: return
	
	buildings.append(building)
	_register_occupied_tiles(building)
	
	if _is_grouped_type(building):
		var group_name = ""
		var b_name = building.building_name if "building_name" in building else ""
		
		# Catch both finished buildings and their construction sites
		if building is ConveyorBuilding or "Conveyor" in b_name or "Belt" in b_name or "Router" in b_name or "Filter" in b_name: 
			group_name = "Belts"
		elif building is WallBuilding or "Wall" in b_name: 
			group_name = "Walls"
		elif building is TerraformSite: 
			group_name = "Terraform"
			
		if group_name != "" and not master_priority_queue.has(group_name):
			master_priority_queue.append(group_name)
	else:
		if not master_priority_queue.has(building):
			master_priority_queue.append(building)
		
	building.hovered.connect(InputManager._on_object_hovered)
	building.unhovered.connect(InputManager._on_object_unhovered)



func _register_occupied_tiles(building: Building):
	for tile in building.occupied_tiles:
		occupied_tiles[tile] = building



## Registers the building on the pathfinder, creating solid centers and passable but costly outer rings for large structures.
func _register_building_pathfinder(building: Building, grid_pos: Vector2i):
	if not pathfinder: return
	
	var footprint = building.get_footprint(grid_pos)
	var size = building.size
	
	# Determine outer ring and inner center tiles if building is large enough (>= 3x3)
	var is_large_obstacle = building.is_solid_obstacle and size.x >= 3 and size.y >= 3
	
	if is_large_obstacle:
		for x in range(size.x):
			for y in range(size.y):
				var tile = grid_pos + Vector2i(x, y)
				var is_center = x >= 1 and x < size.x - 1 and y >= 1 and y < size.y - 1
				if is_center:
					pathfinder.set_obstacle(tile, true)
				else:
					pathfinder.set_weighted_obstacle(tile, 10.0, false)
	else:
		if building.is_solid_obstacle:
			for tile in footprint:
				pathfinder.set_obstacle(tile, true)
		else:
			if (building is WallBuilding):
				for tile in footprint:
					pathfinder.set_weighted_obstacle(tile, building.path_cost, true)
			else:
				for tile in footprint:
					pathfinder.set_weighted_obstacle(tile, building.path_cost, false)



## Registers a building that has completed construction, mapping its status and priority correctly.
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
	
	_register_building_pathfinder(new_building, grid_pos)



## Initiates deconstruction/destruction of the building located at the target grid coordinates.
func deconstruct_building_at(grid_pos: Vector2i):
	if not occupied_tiles.has(grid_pos): return
	var building = occupied_tiles[grid_pos]
	if building is CoreBuilding:
		print("Cannot deconstruct the Core!")
		return
	if building is BotHomeBuilding:
		print("Cannot deconstruct a Bot Home!")
		return
	building.die()



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
	var origin = object_layer.local_to_map(building.global_position)
	for tile in _get_tiles_in_radius(origin, building, building.corruption_range):
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
	var origin = object_layer.local_to_map(building.global_position)
	for tile in _get_tiles_in_radius(origin, building, building.build_range):
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
	var origin = object_layer.local_to_map(building.global_position)
	for offset in building._cached_range_tiles.keys():
		var tile = origin + offset
		if attack_tiles.has(tile):
			attack_tiles[tile] -= 1
			if attack_tiles[tile] <= 0: attack_tiles.erase(tile)



## Upgrades the building located at the target coordinates, checking costs and spawning the appropriate scene.
func upgrade_building_at(grid_pos: Vector2i) -> bool:
	if not occupied_tiles.has(grid_pos): return false
	var old_building = occupied_tiles[grid_pos]
	if not old_building.upgrades_to: return false
	
	var upgrade_cost_dict = {}
	for cost in old_building.upgrade_cost:
		upgrade_cost_dict[cost.item_name] = cost.amount
	
	var is_instant = old_building is ConveyorBuilding or old_building is WallBuilding
	
	if is_instant and not upgrade_cost_dict.is_empty():
		if not EconomyManager.can_afford(upgrade_cost_dict):
			return false
	
	var true_origin = old_building.grid_origin
	var old_priority_index = master_priority_queue.find(old_building)
	
	var saved_data = {}
	if old_building.has_method("get_upgrade_data"):
		saved_data = old_building.get_upgrade_data()
		
	if "direction" in old_building: saved_data["direction"] = old_building.direction
	if "rotation" in old_building: saved_data["rotation"] = old_building.rotation
		
	var old_inventory = {}
	if old_building.has_method("get_economy_assets"):
		old_inventory = old_building.get_economy_assets().duplicate()
	
	_on_building_destroyed(old_building)
	old_building.queue_free()
	
	if is_instant:
		# Fast Track: Instant Upgrade
		var new_building = old_building.upgrades_to.instantiate() as Building
		add_child(new_building)
		
		if new_building.has_method("apply_upgrade_data"):
			new_building.apply_upgrade_data(saved_data)
			
		new_building.place_at(true_origin, level_ref.object_layer)
		new_building.set_ghost(false)
		
		if new_building is ConveyorBuilding:
			new_building.setup(level_ref, new_building.direction)
		elif new_building.has_method("setup"):
			new_building.setup(level_ref)
			
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
		
		_register_building_pathfinder(new_building, grid_pos)
		
		if not upgrade_cost_dict.is_empty():
			EconomyManager.spend_resources(upgrade_cost_dict)
			
	else:
		# Slow Track: Blueprint Upgrade
		var site = construction_site_scene.instantiate() as ConstructionSite
		add_child(site)
		
		var target_name = old_building.building_name + " (Upgrading)"
		site.setup_blueprint(level_ref, old_building.upgrades_to, upgrade_cost_dict, old_building.size, target_name)
		
		for item_name in upgrade_cost_dict.keys():
			if old_inventory.has(item_name):
				var needed = upgrade_cost_dict[item_name]
				var available = old_inventory[item_name]
				var to_consume = min(needed, available)
				
				if to_consume > 0:
					site.delivered_items[item_name] = site.delivered_items.get(item_name, 0) + to_consume
					
					old_inventory[item_name] -= to_consume
					if old_inventory[item_name] <= 0:
						old_inventory.erase(item_name)
						
		if not old_inventory.is_empty():
			saved_data["saved_inventory"] = old_inventory
			
		if not saved_data.is_empty():
			site.set_meta("blueprint_data", saved_data)
		if site.has_method("evaluate_requirements"):
			site.evaluate_requirements()
			
		site.place_at(true_origin, level_ref.object_layer)
		
		_register_building(site)
		site.destroyed.connect(_on_building_destroyed)
		
		if pathfinder:
			for tile in site.occupied_tiles:
				pathfinder.enemy_astar.set_point_solid(tile, false)
				pathfinder.enemy_astar.set_point_weight_scale(tile, 50.0)
				
	return true



## Gathers cost information and updates the placement UI to show upgrade preview metrics.
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
	
	var is_instant = b is ConveyorBuilding or b is WallBuilding
	var can_afford = true
	
	if is_instant and not upgrade_cost_dict.is_empty():
		can_afford = EconomyManager.can_afford(upgrade_cost_dict)
		
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
		stats["Attack Range"] = "%d -> %d Tiles" % [int(b.attack_range), int(temp.attack_range)]
	if "fire_rate" in b and "fire_rate" in temp and b.fire_rate != temp.fire_rate:
		stats["Fire Rate"] = "%d -> %d/s" % [b.fire_rate, temp.fire_rate]
	if "damage_multiplier" in b and "damage_multiplier" in temp and b.damage_multiplier != temp.damage_multiplier:
		stats["Damage Multiplier"] = "%.2fx -> %.2fx" % [b.damage_multiplier, temp.damage_multiplier]
	if "max_mixed_capacity" in b and "max_mixed_capacity" in temp and b.max_mixed_capacity != temp.max_mixed_capacity:
		stats["Mixed Capacity"] = "%d -> %d" % [b.max_mixed_capacity, temp.max_mixed_capacity]
	if "max_dedicated_capacity" in b and "max_dedicated_capacity" in temp and b.max_dedicated_capacity != temp.max_dedicated_capacity:
		stats["Dedicated Capacity"] = "%d -> %d" % [b.max_dedicated_capacity, temp.max_dedicated_capacity]
		
	temp.queue_free()
	return stats



## Checks if the given grid position is adjacent (orthogonally or diagonally) to walkable land.
func _is_adjacent_to_walkable_land(grid_pos: Vector2i) -> bool:
	if not terrain_layer: return false
	
	var neighbors = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1,  0),                  Vector2i(1,  0),
		Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1)
	]
	
	for offset in neighbors:
		var n_tile = grid_pos + offset
		var tile_data = terrain_layer.get_cell_tile_data(n_tile)
		if tile_data != null and tile_data.get_custom_data("buildable") == true:
			return true
			
	return false



## Validates if the given grid position can be terraformed (either removing debris or converting adjacent water).
func can_terraform(grid_pos: Vector2i) -> bool:
	if occupied_tiles.has(grid_pos): return false
	
	if object_layer and object_layer.get_cell_source_id(grid_pos) != -1:
		return true
	if level_ref and level_ref.active_grid_objects.has(grid_pos):
		return true
		
	if terrain_layer:
		var tile_data = terrain_layer.get_cell_tile_data(grid_pos)
		if tile_data != null and tile_data.get_custom_data("buildable") == false:
			# Water tile found! Enforce solid-adjacent constraint.
			return _is_adjacent_to_walkable_land(grid_pos)
			
	return false



func _try_add_terrain_job(grid_pos: Vector2i):
	if not can_terraform(grid_pos):
		return
		
	var job_type = -1
	if object_layer.get_cell_source_id(grid_pos) != -1 or level_ref.active_grid_objects.has(grid_pos):
		job_type = TerraformSite.JobType.REMOVE_OBJECT
	elif terrain_layer:
		var tile_data = terrain_layer.get_cell_tile_data(grid_pos)
		if tile_data != null and tile_data.get_custom_data("buildable") == false:
			job_type = TerraformSite.JobType.CONVERT_WATER


		
	var site = terraform_site_scene.instantiate() as TerraformSite
	add_child(site)
	site.setup(level_ref, grid_pos, job_type)
	terraform_jobs[grid_pos] = job_type
	_register_building(site)
	site.destroyed.connect(_on_building_destroyed)
	site.destroyed.connect(func(_b): terraform_jobs.erase(grid_pos))



## Searches the queue to find the highest priority job needing bot interaction.
## Searches the queue to find the highest priority job needing bot interaction.
func get_highest_priority_job(bot_position: Vector2, is_flying: bool = false, bot_requesting: Node = null) -> Node:
	for item in master_priority_queue:
		if typeof(item) == TYPE_STRING:
			var best = _find_closest_needing_work_in_group(item, bot_position, is_flying, bot_requesting)
			if best != null: return best
		else:
			if is_instance_valid(item) and _building_needs_work_with_commitments(item, bot_requesting):
				return item
	return null



## Standard raw check of whether a building requires material delivery or repair/construction progress.
func _building_needs_work_raw(bldg: Node) -> bool:
	if not is_instance_valid(bldg):
		return false
		
	if bldg is ConstructionSite or bldg is TerraformSite:
		if bldg.is_ready_to_build:
			return bldg.health < bldg.max_health
		else:
			for req_name in bldg.required_items.keys():
				var needed = bldg.required_items[req_name]
				var delivered = bldg.delivered_items.get(req_name, 0)
				if delivered < needed:
					return true
			return false
			
	if bldg.has_method("needs_materials") and bldg.needs_materials():
		return true
		
	if bldg.health < bldg.max_health:
		return true
		
	return false



## Scans the list of active buildings to check if any task currently has 0 bots assigned.
func _has_unserved_jobs(bot_requesting: Node = null) -> bool:
	if not level_ref:
		return false
		
	var bots = level_ref.get_tree().get_nodes_in_group("Bots")
	
	for b in buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
			
		if not _building_needs_work_raw(b):
			continue
			
		var b_tile = b.occupied_tiles[0] if not b.occupied_tiles.is_empty() else Vector2i(-1, -1)
		var is_served = false
		
		for bot in bots:
			if not is_instance_valid(bot) or bot.is_queued_for_deletion():
				continue
			if bot == bot_requesting:
				continue
				
			# Check delivery commitments
			if "committed_job_tile" in bot and bot.committed_job_tile == b_tile:
				is_served = true
				break
				
			# Check building/repairing commitments
			if bot.target_tile in b.occupied_tiles:
				if bot.current_state in [bot.State.MOVING_TO_BUILD, bot.State.BUILDING, bot.State.MOVING_TO_REPAIR, bot.State.REPAIRING]:
					is_served = true
					break
					
		if not is_served:
			return true
			
	return false



## Evaluates whether a building needs work, taking in-transit deliveries and active workers into account.
func _building_needs_work_with_commitments(bldg: Node, bot_requesting: Node = null) -> bool:
	if not is_instance_valid(bldg):
		return false
		
	if not _building_needs_work_raw(bldg):
		return false
		
	var builders_or_repairers = 0
	var delivery_promised = {}
	var b_tile = bldg.occupied_tiles[0] if not bldg.occupied_tiles.is_empty() else Vector2i(-1, -1)
	
	if level_ref:
		var bots = level_ref.get_tree().get_nodes_in_group("Bots")
		for bot in bots:
			if not is_instance_valid(bot) or bot.is_queued_for_deletion():
				continue
			if bot == bot_requesting:
				continue
				
			# Check delivery commitments
			if "committed_job_tile" in bot and bot.committed_job_tile == b_tile:
				var item = bot.carried_item_name
				if item != "":
					var amount = bot.carried_amount if bot.carried_amount > 0 else bot.carry_capacity
					delivery_promised[item] = delivery_promised.get(item, 0) + amount
					
			# Check building/repairing commitments
			if bot.target_tile in bldg.occupied_tiles:
				if bot.current_state in [bot.State.MOVING_TO_BUILD, bot.State.BUILDING, bot.State.MOVING_TO_REPAIR, bot.State.REPAIRING]:
					builders_or_repairers += 1

	if bldg is ConstructionSite or bldg is TerraformSite:
		if bldg.is_ready_to_build:
			# Soft cap of 1 builder: allow more if there are no unserved jobs on the map
			if builders_or_repairers >= 1:
				if _has_unserved_jobs(bot_requesting):
					return false
			return bldg.health < bldg.max_health
		else:
			# Hard delivery cap: check if any required item is not fully promised in-transit
			for req_name in bldg.required_items.keys():
				var needed = bldg.required_items[req_name]
				var delivered = bldg.delivered_items.get(req_name, 0)
				var promised = delivery_promised.get(req_name, 0)
				if delivered + promised < needed:
					return true
			return false
			
	if bldg.has_method("needs_materials") and bldg.needs_materials():
		return true
		
	if bldg.health < bldg.max_health:
		# Soft cap of 1 repairer: allow more if there are no unserved jobs
		if builders_or_repairers >= 1:
			if _has_unserved_jobs(bot_requesting):
				return false
		return true
		
	return false



## Finds the closest candidate node within a specific priority group that needs work.
func _find_closest_needing_work_in_group(group_name: String, bot_pos: Vector2, is_flying: bool = false, bot_requesting: Node = null) -> Node:
	var candidates: Array = []
	var bot_grid = terrain_layer.local_to_map(terrain_layer.to_local(bot_pos))
	
	# Step 1: Collect all active buildings/sites in the target group needing maintenance or delivery
	for b in buildings:
		var matches = false
		
		if group_name == "Belts":
			matches = (b is ConveyorBuilding) or (b is ConstructionSite and "Conveyor" in b.building_name)
			
		elif group_name == "Walls":
			matches = (b is WallBuilding) or (b is ConstructionSite and "Wall" in b.building_name)
			
		elif group_name == "Terraform":
			matches = (b is TerraformSite)
			
		if matches and _building_needs_work_with_commitments(b, bot_requesting):
			var dist = bot_pos.distance_squared_to(b.global_position)
			candidates.append({
				"building": b,
				"dist": dist
			})
			
	# Sort candidate priority jobs by straight-line distance first
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	var best_target = null
	var min_path_cost = INF
	var valid_paths_found = 0
	
	# Step 2: Compute pathfinding cost to the standable tiles adjacent to each candidate.
	# Capping the search after checking the top 5 reachable jobs preserves excellent performance.
	var active_astar = pathfinder.flying_astar if (is_flying and "flying_astar" in pathfinder) else pathfinder.bot_astar
	
	for cand in candidates:
		if valid_paths_found >= 5:
			break
			
		var b = cand["building"]
		var shortest_cost = INF
		var neighbors = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		
		# Find the closest reachable neighbor tile of the building's occupied grid footprint
		for t_tile in b.occupied_tiles:
			for offset in neighbors:
				var test_tile = t_tile + offset
				if test_tile in b.occupied_tiles: continue
				
				if pathfinder and active_astar.is_in_boundsv(test_tile) and not active_astar.is_point_solid(test_tile):
					var path_array = active_astar.get_id_path(bot_grid, test_tile)
					if not path_array.is_empty() or bot_grid == test_tile:
						var path_len = path_array.size()
						if path_len < shortest_cost:
							shortest_cost = path_len
							
		if shortest_cost != INF:
			valid_paths_found += 1
			if shortest_cost < min_path_cost:
				min_path_cost = shortest_cost
				best_target = b
	return best_target



## Returns the 1-based priority queue rank of the given item.
func get_priority_rank(item: Variant) -> int:
	var idx = master_priority_queue.find(item)
	return idx + 1 if idx != -1 else 0


## Returns the total size of the priority queue.
func get_total_priority_ranks() -> int:
	return master_priority_queue.size()


## Moves the priority of the target item up by one rank.
func move_priority_up(item: Variant):
	var idx = master_priority_queue.find(item)
	if idx > 0:
		var temp = master_priority_queue[idx - 1]
		master_priority_queue[idx - 1] = item
		master_priority_queue[idx] = temp


## Moves the priority of the target item down by one rank.
func move_priority_down(item: Variant):
	var idx = master_priority_queue.find(item)
	if idx != -1 and idx < master_priority_queue.size() - 1:
		var temp = master_priority_queue[idx + 1]
		master_priority_queue[idx + 1] = item
		master_priority_queue[idx] = temp



func _get_empty_tiles_around(building: Building, count: int) -> Array[Vector2i]:
	var valid_tiles: Array[Vector2i] = []
	var origin = building.grid_origin
	var search_radius = 1
	
	# Collect all currently reserved bot home tiles to avoid spawning on them
	var reserved_homes: Array[Vector2i] = []
	if is_inside_tree():
		for bot in get_tree().get_nodes_in_group("Bots"):
			if is_instance_valid(bot) and not bot.is_queued_for_deletion():
				if "home_tile" in bot and bot.home_tile != Vector2i(-1, -1):
					reserved_homes.append(bot.home_tile)
					
	while valid_tiles.size() < count and search_radius < 10:
		for x in range(origin.x - search_radius, origin.x + building.size.x + search_radius):
			for y in range(origin.y - search_radius, origin.y + building.size.y + search_radius):
				var check_tile = Vector2i(x, y)
				if building.occupied_tiles.has(check_tile): continue
				if valid_tiles.has(check_tile): continue
				if check_tile in reserved_homes: continue
				if pathfinder and pathfinder.bot_astar.is_in_boundsv(check_tile):
					if not pathfinder.bot_astar.is_point_solid(check_tile):
						if pathfinder.bot_astar.get_point_weight_scale(check_tile) == 1.0:
							valid_tiles.append(check_tile)
							if valid_tiles.size() >= count: return valid_tiles
		search_radius += 1
		
	return valid_tiles



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



## Gathers and returns serialization data for all buildings and core states.
func get_save_data() -> Dictionary:
	var saved_buildings = []

	for b in buildings:
		if not is_instance_valid(b) or b.is_ghost: 
			continue

		var b_data = b.get_save_data() if b.has_method("get_save_data") else {}

		b_data["scene_file_path"] = b.scene_file_path
		b_data["grid_origin_x"] = b.grid_origin.x
		b_data["grid_origin_y"] = b.grid_origin.y

		saved_buildings.append(b_data)

	return {
		"is_core_placed": is_core_placed,
		"buildings": saved_buildings
	}


## Re-instantiates and restores all buildings and zones from loaded save state.
func load_save_data(data: Dictionary):
	is_core_placed = data.get("is_core_placed", false)

	if not data.has("buildings"): return

	for b_data in data["buildings"]:
		var path = b_data.get("scene_file_path", "")
		
		if path == "" or not ResourceLoader.exists(path):
			print("WARNING: Could not find scene file at: ", path)
			continue

		var new_building = load(path).instantiate() as Building
		if b_data.has("is_horizontal") and "is_horizontal" in new_building:
			new_building.set("is_horizontal", b_data["is_horizontal"])
		add_child(new_building)

		var grid_pos = Vector2i(b_data["grid_origin_x"], b_data["grid_origin_y"])
		if b_data.has("size_x") and b_data.has("size_y"):
			new_building.size = Vector2i(b_data["size_x"], b_data["size_y"])
		new_building.place_at(grid_pos, object_layer)
		new_building.set_ghost(false)

		if new_building is ConveyorBuilding:
			var temp_dir = str_to_var(b_data.get("direction", "Vector2i(1, 0)"))
			new_building.setup(level_ref, temp_dir)
		elif new_building is TerraformSite:
			var temp_type = b_data.get("job_type", 0)
			new_building.setup(level_ref, grid_pos, temp_type)
		elif new_building.has_method("setup"):
			new_building.setup(level_ref)

		if new_building.has_method("load_save_data"):
			new_building.load_save_data(b_data)

		_register_building(new_building)
		_add_safe_zone(new_building)
		_add_build_zone(new_building)
		_add_attack_zone(new_building)

		if new_building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
			new_building.fired_projectile.connect(level_ref._on_tower_fired)
			
		new_building.destroyed.connect(_on_building_destroyed)

		_register_building_pathfinder(new_building, grid_pos)
	if is_core_placed:
		print_debug("load placed")
		core_placed_event.emit()



func _on_core_placed(building: Building, grid_pos: Vector2i):
	is_core_placed = true
	core_placed_event.emit()
	
	var bot_scene = load("res://scenes/Workers/WorkerBot.tscn")
	for tile in _get_empty_tiles_around(building, 1):
		var new_bot = bot_scene.instantiate()
		level_ref.object_layer.add_child(new_bot)
		new_bot.global_position = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(tile))
		new_bot.setup(level_ref)
		new_bot.hovered.connect(InputManager._on_object_hovered)
		new_bot.unhovered.connect(InputManager._on_object_unhovered)
	
	if level_ref and level_ref.has_node("CorruptionManager"):
		level_ref.get_node("CorruptionManager").start_outbreak(object_layer.local_to_map(building.global_position))
		
	if level_ref.has_node("TimeManager"):
		level_ref.get_node("TimeManager").is_time_running = true



func _on_inventory_changed():
	if placing_building and is_instance_valid(ghost_building):
		var current_grid_pos = _get_mouse_grid()
		
		if is_dragging:
			_update_drag_line(current_grid_pos)
		else:
			_update_ghost_position_to(current_grid_pos)



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
			if not occupied_tiles.has(tile):
				pathfinder.set_obstacle(tile, false)
				pathfinder.set_weighted_obstacle(tile, 1.0)

	if b.has_method("get_economy_assets"):
		var assets = b.get_economy_assets()
		if not assets.is_empty():
			if EconomyManager.secured_sources.has(b):
				EconomyManager.remove_resources_from_global(assets)
				
			for item_name in assets.keys():
				EconomyManager.log_item_consumed(item_name, assets[item_name])
