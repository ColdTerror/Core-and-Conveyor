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
	var start_local = main_layer.to_local(start_world)
	var end_local = main_layer.to_local(end_world)
	
	var start_grid = main_layer.local_to_map(start_local)
	var end_grid = main_layer.local_to_map(end_local)
	
	# --- SMART TARGETING (Cost-Aware) ---
	# If the target is a solid building, we need to find the best "Doorstep"
	if astar.is_in_boundsv(end_grid) and astar.is_point_solid(end_grid):
		
		var best_path_ids: Array[Vector2i] = []
		var lowest_cost = INF
		
		# 1. Define Search Area (Perimeter of the building)
		# Use 1 for 1x1 buildings, 2 for larger ones to be safe
		var radius = 2 
		
		for x in range(end_grid.x - radius, end_grid.x + radius + 1):
			for y in range(end_grid.y - radius, end_grid.y + radius + 1):
				var neighbor = Vector2i(x, y)
				
				# Skip invalid tiles or the building center itself
				if not astar.is_in_boundsv(neighbor): continue
				if neighbor == end_grid: continue 
				
				# Optimization: Only check "Solid" neighbors if they are Walls (weighted)
				# If it's a hard obstacle (Water), skip it.
				if astar.is_point_solid(neighbor):
					# If weight is 1.0, it's a generic solid (like water/bedrock), skip.
					# If weight > 1.0, it's a Wall, so it's a valid target to break.
					if astar.get_point_weight_scale(neighbor) <= 1.0:
						continue

				# 2. GENERATE PATH to this candidate
				var potential_path = astar.get_id_path(start_grid, neighbor)
				if potential_path.is_empty(): continue
				
				# 3. CALCULATE TRUE COST
				# Sum the weight of every tile in the path.
				# (Grass = 1, Wall = 50).
				var current_cost = 0.0
				for id in potential_path:
					current_cost += astar.get_point_weight_scale(id)
				
				# 4. Compare
				if current_cost < lowest_cost:
					lowest_cost = current_cost
					best_path_ids = potential_path
					
		# If we found a valid path, convert IDs to World Position
		if not best_path_ids.is_empty():
			var world_path = PackedVector2Array()
			for point in best_path_ids:
				var local_pos = main_layer.map_to_local(point)
				world_path.append(main_layer.to_global(local_pos))
			return world_path
			
		else:
			# Fallback: If absolutely no path found (Target islanded?)
			return []
	# -------------------------------------------

	# Normal movement (Grid to Grid)
	var path_points = astar.get_point_path(start_grid, end_grid)
	var world_path = PackedVector2Array()
	for point in path_points:
		var local_pos = main_layer.map_to_local(point)
		world_path.append(main_layer.to_global(local_pos))
		
	return world_path
