extends Node2D
class_name BuildingManager

@export var object_layer: TileMapLayer
@export var hover_popup: Control

var buildings: Array[Building] = []

var ghost_building: Building = null
var placing_building := false


# -------------------------------------------------
# PUBLIC API
# -------------------------------------------------

func start_placing(scene: PackedScene):
	if scene == null:
		return

	if placing_building:
		cancel_placement()

	ghost_building = scene.instantiate() as Building
	add_child(ghost_building)

	ghost_building.set_ghost(true)
	placing_building = true
	


func _process(_delta):
	if placing_building and ghost_building:
		_update_ghost_position()


func confirm_placement():
	if not placing_building or ghost_building == null:
		return

	var grid_pos = _get_mouse_grid()

	if not ghost_building.can_place_at(grid_pos, object_layer):
		return

	ghost_building.set_ghost(false)
	ghost_building.place_at(grid_pos, object_layer)

	buildings.append(ghost_building)
	_register_building(ghost_building)

	ghost_building = null
	placing_building = false


func cancel_placement():
	if ghost_building:
		ghost_building.queue_free()

	ghost_building = null
	placing_building = false


# -------------------------------------------------
# INTERNAL
# -------------------------------------------------

func _update_ghost_position():
	var grid_pos = _get_mouse_grid()

	ghost_building.place_at(grid_pos, object_layer)

	var valid := ghost_building.can_place_at(grid_pos, object_layer)
	ghost_building.set_valid_placement(valid)


func _get_mouse_grid() -> Vector2i:
	var mouse_global := get_global_mouse_position()
	var mouse_local := object_layer.to_local(mouse_global)
	return object_layer.local_to_map(mouse_local)


func _register_building(building: Building):
	building.hovered.connect(_on_building_hovered)
	building.unhovered.connect(_on_building_unhovered)


func _on_building_hovered(building: Building):
	hover_popup.show_building_info(building)


func _on_building_unhovered(_building):
	hover_popup.hide_popup()
