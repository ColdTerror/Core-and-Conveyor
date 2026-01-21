extends Node2D
class_name Building

signal hovered(building: Building)
signal unhovered(building: Building)

@export var building_name := "Building"
@export var size := Vector2i(1, 1)
@export var max_health := 100
var health := max_health

var occupied_tiles: Array[Vector2i] = []

# --- Ready ---
func _ready():
	if has_node("Area2D"):
		$Area2D.mouse_entered.connect(_on_mouse_entered)
		$Area2D.mouse_exited.connect(_on_mouse_exited)


# --- Ghost / Visuals ---
func set_ghost(enabled: bool):
	if has_node("Area2D"):
		$Area2D.monitoring = not enabled
		$Area2D.visible = not enabled

	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(1, 1, 1, 0.5 if enabled else 1)

func set_valid_placement(valid: bool):
	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(0.6, 1, 0.6, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)


# --- Footprint calculation ---
func get_footprint(origin: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(size.x):
		for y in range(size.y):
			tiles.append(origin + Vector2i(x, y))
	return tiles


# --- Placement ---
func place_at(origin: Vector2i, object_layer: TileMapLayer):
	occupied_tiles = get_footprint(origin)

	var tile_size := Vector2(object_layer.tile_set.tile_size)
	var top_left_world := object_layer.map_to_local(origin)
	var footprint_px := Vector2(size) * tile_size
	global_position = (top_left_world + footprint_px / 2) - (tile_size / 2)

	_update_collision(footprint_px)


func _update_collision(footprint_px: Vector2):
	if not has_node("Area2D/CollisionShape2D"):
		return

	var area := $Area2D
	var collision_shape := $Area2D/CollisionShape2D
	var shape := collision_shape.shape as RectangleShape2D

	shape.size = footprint_px
	area.position = Vector2.ZERO
	collision_shape.position = Vector2.ZERO


# --- Signals ---
func _on_mouse_entered():
	hovered.emit(self)

func _on_mouse_exited():
	unhovered.emit(self)
	
# --- Building Functions ---
func building_tick(delta: float) -> void:
	pass
