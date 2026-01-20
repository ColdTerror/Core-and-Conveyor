extends Node2D
class_name Building


signal hovered(building: Building)
signal unhovered(building: Building)

@export var building_name := "Building"
@export var size := Vector2i(1, 1)
@export var max_health := 100
var health := max_health

var occupied_tiles: Array[Vector2i] = []

#Assume whatever extends this has an area2d node
func _ready():
	$Area2D.mouse_entered.connect(_on_mouse_entered)
	$Area2D.mouse_exited.connect(_on_mouse_exited)


func can_place_at(origin: Vector2i, object_layer: TileMapLayer) -> bool:
	for x in range(size.x):
		for y in range(size.y):
			var pos = origin + Vector2i(x, y)
			if object_layer.get_cell_source_id(pos) != -1:
				return false
	return true

func place_at(origin: Vector2i, object_layer: TileMapLayer):
	occupied_tiles.clear()
	for x in range(size.x):
		for y in range(size.y):
			occupied_tiles.append(origin + Vector2i(x, y))

	# Places with mouse at center
	#global_position = object_layer.map_to_local(origin)
	
	# Places with mouse at top left
	var tile_size := Vector2(object_layer.tile_set.tile_size)
	var top_left_world := object_layer.map_to_local(origin)
	var footprint_px := Vector2(size) * tile_size
	global_position = (top_left_world + footprint_px / 2) - (tile_size/2)
	
	
	_update_collision(footprint_px)

func _update_collision(footprint_px: Vector2):
	var area := $Area2D
	var shape := $Area2D/CollisionShape2D.shape as RectangleShape2D
	shape.size = footprint_px
	area.position = footprint_px / 2

# ---- Item hooks (to be overrriden) ----
func accepts_item_at(_tile: Vector2i) -> bool:
	return false

func can_accept_item(_item) -> bool:
	return false

func accept_item(_item) -> bool:
	return false
	
# ---- Signals ----
func _on_mouse_entered():
	hovered.emit(self)

func _on_mouse_exited():
	unhovered.emit(self)
