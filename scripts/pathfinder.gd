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

# Pathfinder.gd

func get_path_route(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	var start_local = main_layer.to_local(start_world)
	var end_local = main_layer.to_local(end_world)
	var start_grid = main_layer.local_to_map(start_local)
	var end_grid = main_layer.local_to_map(end_local)
	
	# --- SMART TARGETING (Find Closest Doorstep) ---
	if astar.is_in_boundsv(end_grid) and astar.is_point_solid(end_grid):
		
		# We still scan a large area (5x5) to find the building edges...
		var radius = 5 
		
		var best_path_ids: Array[Vector2i] = []
		var lowest_cost = INF
		
		for x in range(end_grid.x - radius, end_grid.x + radius + 1):
			for y in range(end_grid.y - radius, end_grid.y + radius + 1):
				var neighbor = Vector2i(x, y)
				
				# 1. Basic Validity Checks
				if not astar.is_in_boundsv(neighbor): continue
				if neighbor == end_grid: continue 
				
				# If solid (Water/Bedrock), skip. If Weighted (Wall), allow.
				if astar.is_point_solid(neighbor) and astar.get_point_weight_scale(neighbor) <= 1.0:
					continue

				# --- THE FIX: ADJACENCY CHECK ---
				# Only accept this tile if it is DIRECTLY TOUCHING a Solid tile (The Building)
				# This forces the enemy to walk all the way up to the wall.
				if not _is_touching_solid(neighbor):
					continue
				# --------------------------------

				# 2. GENERATE PATH
				var potential_path = astar.get_id_path(start_grid, neighbor)
				if potential_path.is_empty(): continue
				
				# 3. CALCULATE COST
				var current_cost = 0.0
				for id in potential_path:
					current_cost += astar.get_point_weight_scale(id)
				
				# 4. PICK THE WINNER
				if current_cost < lowest_cost:
					lowest_cost = current_cost
					best_path_ids = potential_path
					
		if not best_path_ids.is_empty():
			var world_path = PackedVector2Array()
			for point in best_path_ids:
				var local_pos = main_layer.map_to_local(point)
				world_path.append(main_layer.to_global(local_pos))
			return world_path
		else:
			return []
	# -------------------------------------------

	# Normal movement
	var path_points = astar.get_point_path(start_grid, end_grid)
	var world_path = PackedVector2Array()
	for point in path_points:
		var local_pos = main_layer.map_to_local(point)
		world_path.append(main_layer.to_global(local_pos))
		
	return world_path

# --- NEW HELPER FUNCTION ---
func _is_touching_solid(grid_pos: Vector2i) -> bool:
	# Check Up, Down, Left, Right
	var neighbors = [
		Vector2i(0, 1), Vector2i(0, -1), 
		Vector2i(1, 0), Vector2i(-1, 0)
	]
	
	for offset in neighbors:
		var check_pos = grid_pos + offset
		if astar.is_in_boundsv(check_pos):
			# If we find a solid neighbor, we are "touching" the building!
			if astar.is_point_solid(check_pos):
				return true
				
	return false
