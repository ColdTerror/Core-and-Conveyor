extends Node
class_name Pathfinder

var astar = AStarGrid2D.new()
var main_layer: TileMapLayer 

func setup(terrain_layer: TileMapLayer, object_layer: TileMapLayer, map_rect: Rect2i):
	print("Pathfinder: Setup...")
	main_layer = terrain_layer
	
	astar.region = map_rect
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	
	for x in range(map_rect.position.x, map_rect.end.x):
		for y in range(map_rect.position.y, map_rect.end.y):
			var coords = Vector2i(x, y)
			var tile_data = terrain_layer.get_cell_tile_data(coords)
			
			if tile_data == null:
				astar.set_point_solid(coords, true)
				continue
				
			var is_Walkable = tile_data.get_custom_data("is_Walkable")
			if not is_Walkable:
				astar.set_point_solid(coords, true)
				continue

			if object_layer.get_cell_source_id(coords) != -1:
				astar.set_point_solid(coords, true)

func set_obstacle(coords: Vector2i, is_solid: bool):
	if astar.is_in_boundsv(coords):
		astar.set_point_solid(coords, is_solid)

func set_weighted_obstacle(coords: Vector2i, cost: float):
	if astar.is_in_boundsv(coords):
		astar.set_point_solid(coords, false)
		astar.set_point_weight_scale(coords, cost)
		print("Weight:", astar.get_point_weight_scale(coords))
		print("Solid:", astar.is_point_solid(coords))

func get_path_route(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	var start_local = main_layer.to_local(start_world)
	var end_local = main_layer.to_local(end_world)
	
	var start_grid = main_layer.local_to_map(start_local)
	var end_grid = main_layer.local_to_map(end_local)
	
	# Just get the path! The Enemy has already decided the exact "end_grid" tile.
	var path_points = astar.get_point_path(start_grid, end_grid)
	
	var world_path = PackedVector2Array()
	for point in path_points:
		var local_pos = main_layer.map_to_local(point)
		world_path.append(main_layer.to_global(local_pos))
		
	return world_path
