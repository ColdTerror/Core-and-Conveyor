extends Node

@export var forest_regrow_time := 5.0

# Key: Vector2i (tile position)
# Value: float (seconds until regrown)
var regrowing_forests := {}

signal forest_regrown(tile: Vector2i)

func harvest_forest(tile: Vector2i):
	if regrowing_forests.has(tile):
		return

	print('harvesting')
	regrowing_forests[tile] = forest_regrow_time

func _process(delta):
	var finished := []

	for tile in regrowing_forests.keys():
		regrowing_forests[tile] -= delta
		if regrowing_forests[tile] <= 0:
			finished.append(tile)

	for tile in finished:
		regrowing_forests.erase(tile)
		forest_regrown.emit(tile)
