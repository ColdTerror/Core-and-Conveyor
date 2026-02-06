extends Node2D
class_name BuildingManager

@export var object_layer: TileMapLayer
@export var hover_popup: Control

var buildings: Array[Building] = []
var occupied_tiles := {} # Key: Vector2i, Value: Building

var ghost_building: Building = null
var placing_building := false

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

	if placing_building:
		cancel_placement()

	ghost_building = scene.instantiate() as Building
	add_child(ghost_building)
	
	# Inject Level immediately so Ghost can see the grid
	if ghost_building.has_method("setup") and level_ref:
		ghost_building.setup(level_ref)

	ghost_building.set_ghost(true)
	placing_building = true

func _process(delta):
	for b in buildings:
		b.building_tick(delta)
	
	if placing_building and ghost_building:
		_update_ghost_position()

# --- UPDATED: Now returns bool so Level.gd knows if it worked ---
func confirm_placement() -> bool:
	if not placing_building or ghost_building == null:
		return false

	var grid_pos = _get_mouse_grid()

	if not _can_place_building(ghost_building, grid_pos):
		return false
		
	# Check Economy
	var cost = ghost_building.get_build_cost()
	if not EconomyManager.can_afford(cost):
		print("Cannot afford building! Needed: ", cost)
		return false

	# Pay the Cost
	EconomyManager.spend_resources(cost)

	# Finalize the Building
	ghost_building.set_ghost(false)
	ghost_building.place_at(grid_pos, object_layer)
	
	# If the building script has a 'setup' function, pass the level to it
	if ghost_building.has_method("setup"):
		ghost_building.setup(level_ref)
		
	# --- NEW: CONNECT TOWER SIGNALS ---
	# If this is a Tower, connect its firing signal to the Level script
	if ghost_building.has_signal("fired_projectile") and level_ref.has_method("_on_tower_fired"):
		ghost_building.fired_projectile.connect(level_ref._on_tower_fired)
	# ----------------------------------

	buildings.append(ghost_building)
	_register_building(ghost_building)
	_register_occupied_tiles(ghost_building)
	
	if pathfinder:
		var footprint = ghost_building.get_footprint(grid_pos)
		
		# CHECK: Is this a Wall?
		if ghost_building.is_solid_obstacle:
			print_debug("not wall")
			# It's a solid building (Stockpile)
			for tile in footprint:
				pathfinder.set_obstacle(tile, true)
				
		else:
			print_debug("wall")
			# It's a weighted building (Wall)
			# We use the cost directly from the inspector
			for tile in footprint:
				pathfinder.set_weighted_obstacle(tile, ghost_building.path_cost)
				

	# Important: We do NOT queue_free the ghost here because it BECAME the real building.
	ghost_building = null
	placing_building = false
	
	
	
	return true # Success!



# -------------------------------
# INTERNAL
# -------------------------------
func _update_ghost_position():
	var grid_pos = _get_mouse_grid()
	ghost_building.place_at(grid_pos, object_layer)

	var valid = _can_place_building(ghost_building, grid_pos)
	ghost_building.set_valid_placement(valid)

func _get_mouse_grid() -> Vector2i:
	var mouse_global = get_global_mouse_position()
	# Safety check if object_layer isn't assigned yet
	if not object_layer: return Vector2i.ZERO
	
	var mouse_local = object_layer.to_local(mouse_global)
	return object_layer.local_to_map(mouse_local)

func _can_place_building(building: Building, origin: Vector2i) -> bool:
	if not object_layer: return false
	
	# 1. Check TileMap for obstacles
	for tile in building.get_footprint(origin):
		if object_layer.get_cell_source_id(tile) != -1:
			return false

	# 2. Check global occupied tiles
	for tile in building.get_footprint(origin):
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
	# Check if the player pressed ESC (ui_cancel is built-in)
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
		if ghost_building != null:
			cancel_placement()
			
func cancel_placement():
	if ghost_building:
		ghost_building.queue_free()
		ghost_building = null
		print("Placement cancelled.")

func _on_building_hovered(building: Building):
	if hover_popup:
		hover_popup.show_building_info(building)

func _on_building_unhovered(_building):
	if hover_popup:
		hover_popup.hide_popup()
