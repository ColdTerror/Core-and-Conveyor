extends Node2D
class_name StockpileBuilding


var inventory := {}                # ItemResource → amount
@export var max_capacity := 10
var current_amount := 0

@export var size := Vector2i(4, 4)  # 4x4 footprint
var occupied_tiles: Array[Vector2i] = []

func can_place_at(origin: Vector2i, object_layer: TileMapLayer) -> bool:
	var terrain_layer: TileMapLayer = (object_layer.get_parent() as Node2D).terrain_layer


	for x in size.x:
		for y in size.y:
			var tile := origin + Vector2i(x, y)

			# Block water
			var terr_atlas := terrain_layer.get_cell_atlas_coords(tile)
			if terr_atlas == Vector2i(-1, -1):
				return false

			# Block objects/buildings
			if object_layer.get_cell_source_id(tile) != -1:
				return false

	return true


func place_at(origin: Vector2i, object_layer: TileMapLayer):
	occupied_tiles.clear()

	for x in size.x:
		for y in size.y:
			var tile := origin + Vector2i(x, y)
			occupied_tiles.append(tile)

			# Mark tiles as occupied in the object layer
			object_layer.set_cell(tile, 0, Vector2i.ZERO)

	# Position sprite correctly
	var tile_size := Vector2(object_layer.tile_set.tile_size)
	var top_left_world := object_layer.map_to_local(origin)
	var footprint_px := Vector2(size) * tile_size

	
	global_position = (top_left_world + footprint_px / 2) - (tile_size/2)
	

func remove(object_layer: TileMapLayer):
	for cell in occupied_tiles:
		object_layer.set_cell(cell, -1)
	queue_free()
	

func accepts_item_at(tile: Vector2i) -> bool:
	return tile in occupied_tiles
	
func add_item(item: ItemResource, amount := 1) -> bool:
	if current_amount + amount > max_capacity:
		return false

	inventory[item] = inventory.get(item, 0) + amount
	current_amount += amount

	InventoryManager.add_resources(item.display_name, amount)
	return true
