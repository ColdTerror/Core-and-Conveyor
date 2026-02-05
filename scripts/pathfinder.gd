# Pathfinder.gd
extends Node
class_name Pathfinder

# The grid brain
var astar = AStarGrid2D.new()
var main_layer: TileMapLayer # Needed for coordinate conversion

# Initialize the grid
func setup(terrain_layer: TileMapLayer, object_layer: TileMapLayer, map_rect: Rect2i):
	print("Pathfinder: Setup started with map size: ", map_rect)
	main_layer = terrain_layer
	
	# 1. Configure the Grid
	astar.region = map_rect # The size of your map (e.g. 0,0 to 100,100)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES # Allows cutting corners cleanly
	astar.update() # Build the internal nodes
	
	# 2. Loop through all tiles to find water and obstacles
	for x in range(map_rect.position.x, map_rect.end.x):
		for y in range(map_rect.position.y, map_rect.end.y):
			var coords = Vector2i(x, y)
			
			# RULE A: Terrain Layer (Water Check)
			# If the cell is empty (-1), it's water/void -> Solid
			if terrain_layer.get_cell_source_id(coords) == -1:
				astar.set_point_solid(coords, true)
				continue # No need to check objects if it's already water
			
			# RULE B: Object Layer (Tree/Rock Check)
			# If the cell has a tile (ID != -1), it's a tree -> Solid
			if object_layer.get_cell_source_id(coords) != -1:
				astar.set_point_solid(coords, true)

# Called when placing a building
func set_obstacle(coords: Vector2i, is_solid: bool):
	if astar.is_in_boundsv(coords):
		astar.set_point_solid(coords, is_solid)

# Add this new function to change tile weights
func set_weighted_obstacle(coords: Vector2i, cost: float):
	if astar.is_in_boundsv(coords):
		# Unlock the tile (so A* considers it a valid path)
		astar.set_point_solid(coords, false)
		# Increase the "Cost" to walk on it
		astar.set_point_weight_scale(coords, cost)

# The function Enemies call to get a path
func get_path_route(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	# 1. TRANSLATION LAYER (World Pixels -> Grid Indices)
	# Converts (800, 896) -> Local (800, 896) -> Grid (25, 28)
	var start_local = main_layer.to_local(start_world)
	var end_local = main_layer.to_local(end_world)
	
	var start_grid = main_layer.local_to_map(start_local)
	var end_grid = main_layer.local_to_map(end_local)
	
	# --- 1. HANDLE SOLID TARGETS (BFS SEARCH) ---
	if astar.is_in_boundsv(end_grid) and astar.is_point_solid(end_grid):
		var found_valid_tile = false
		
		# BFS Variables
		var queue: Array[Vector2i] = [end_grid]
		var visited: Dictionary = { end_grid: true }
		var search_limit = 20 # Don't search more than 20 tiles away
		
		while queue.size() > 0:
			var current = queue.pop_front()
			
			# Check if this tile is walkable
			if astar.is_in_boundsv(current) and not astar.is_point_solid(current):
				end_grid = current # Found our new target!
				found_valid_tile = true
				break
			
			# If we've searched too far, stop
			if visited.size() > search_limit:
				break
			
			# Add neighbors to queue
			var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
			for n in neighbors:
				var next = current + n
				if not visited.has(next) and astar.is_in_boundsv(next):
					visited[next] = true
					queue.append(next)
		
		if not found_valid_tile:
			print("Pathfinder: Target is deeply buried in walls! Cannot reach.")
			return [] # Return empty path
	# -------------------------------------------

	# 2. Get the Path (Grid Indices)
	# AStar returns: [(25, 28), (25, 27), ...]
	var path_points = astar.get_point_path(start_grid, end_grid)
	
	# 3. CONVERT BACK (Grid Indices -> World Pixels)
	var world_path = PackedVector2Array()
	
	for point in path_points:
		var local_pos = main_layer.map_to_local(point) # (25, 28) -> (800, 896)
		var global_pos = main_layer.to_global(local_pos)
		world_path.append(global_pos)
		
	return world_path
