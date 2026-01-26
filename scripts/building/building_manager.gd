extends Node2D
class_name BuildingManager

@export var object_layer: TileMapLayer
@export var hover_popup: Control

var buildings: Array[Building] = []
var occupied_tiles := {} # Key: Vector2i, Value: Building

var ghost_building: Building = null
var placing_building := false

var level_ref: Node2D 


	
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
	
	# --- NEW: Inject Level immediately so Ghost can see the grid ---
	if ghost_building.has_method("setup") and level_ref:
		ghost_building.setup(level_ref)
	# ---------------------------------------------------------------

	ghost_building.set_ghost(true)
	placing_building = true


func _process(delta):
	for b in buildings:
		b.building_tick(delta)
	
	if placing_building and ghost_building:
		_update_ghost_position()


func confirm_placement():
	if not placing_building or ghost_building == null:
		return

	var grid_pos = _get_mouse_grid()

	if not _can_place_building(ghost_building, grid_pos):
		return
		
	# Check Economy (Can we afford it?)
	var cost = ghost_building.get_build_cost()
	if not EconomyManager.can_afford(cost):
		print("Cannot afford building! Needed: ", cost)
		# Optional: Play a "buzzer" sound or flash the ghost red
		return

	# Pay the Cost
	EconomyManager.spend_resources(cost)

	ghost_building.set_ghost(false)
	ghost_building.place_at(grid_pos, object_layer)
	
	# --- NEW INJECTION HERE ---
	# If the building script has a 'setup' function, pass the level to it
	if ghost_building.has_method("setup"):
		ghost_building.setup(level_ref)

	buildings.append(ghost_building)
	_register_building(ghost_building)
	_register_occupied_tiles(ghost_building)

	ghost_building = null
	placing_building = false


func cancel_placement():
	if ghost_building:
		ghost_building.queue_free()

	ghost_building = null
	placing_building = false


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
	var mouse_local = object_layer.to_local(mouse_global)
	return object_layer.local_to_map(mouse_local)


func _can_place_building(building: Building, origin: Vector2i) -> bool:
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


func _on_building_hovered(building: Building):
	hover_popup.show_building_info(building)


func _on_building_unhovered(_building):
	hover_popup.hide_popup()
