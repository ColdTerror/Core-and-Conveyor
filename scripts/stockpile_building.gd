extends Node2D
class_name StockpileBuilding

@export var size := Vector2i(4, 4)  # 4x4 footprint
var inventory := {}                # ItemResource → amount
var occupied_tiles: Array[Vector2i] = []

func can_place_at(tile_pos: Vector2i, object_layer: TileMapLayer) -> bool:
	for x in range(size.x):
		for y in range(size.y):
			var cell := tile_pos + Vector2i(x, y)
			if object_layer.get_cell_source_id(cell) != -1:
				return false
	return true

func place_at(tile_pos: Vector2i, object_layer: TileMapLayer):
	occupied_tiles.clear()

	# Claim tiles
	for x in range(size.x):
		for y in range(size.y):
			var cell := tile_pos + Vector2i(x, y)
			occupied_tiles.append(cell)

			# Mark tile as occupied (use a dedicated building tile or -1 if visual only)
			object_layer.set_cell(cell, 0)  # 0 = building tile ID (example)

	# Position sprite centered over footprint
	var top_left_world := object_layer.map_to_local(tile_pos)
	var footprint_px = Vector2(size) * Vector2(object_layer.tile_set.tile_size)
	global_position = top_left_world + footprint_px / 2
	
func remove(object_layer: TileMapLayer):
	for cell in occupied_tiles:
		object_layer.set_cell(cell, -1)
	queue_free()
