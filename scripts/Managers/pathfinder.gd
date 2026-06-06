# ==============================================================================
# Script: Managers/pathfinder.gd
# Purpose: Implements two independent AStarGrid2D brains (one for worker bots, one for enemies) to calculate optimal pathways around solid buildings, walls, and water weight costs.
# Dependencies: Requires TileMapLayer references and standard Godot AStarGrid2D resources.
# Signals: None.
# ==============================================================================
extends Node
class_name Pathfinder

# --- THE TRIPLE BRAINS ---
var enemy_astar = AStarGrid2D.new()
var bot_astar = AStarGrid2D.new()
var flying_astar = AStarGrid2D.new()
var main_layer: TileMapLayer 



## Sets up all three AStarGrid2D brains (enemy, bot, and flying) using terrain walkable/water rules.
func setup(terrain_layer: TileMapLayer, object_layer: TileMapLayer, map_rect: Rect2i):
	print("Pathfinder: Setup Triple-Brains...")
	main_layer = terrain_layer
	
	# Setup all three grids exactly the same
	for astar in [enemy_astar, bot_astar, flying_astar]:
		astar.region = map_rect
		astar.cell_size = Vector2(1, 1)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		astar.update()
	
	for x in range(map_rect.position.x, map_rect.end.x):
		for y in range(map_rect.position.y, map_rect.end.y):
			var coords = Vector2i(x, y)
			var tile_data = terrain_layer.get_cell_tile_data(coords)
			
			if tile_data == null or not tile_data.get_custom_data("is_Walkable"):
				enemy_astar.set_point_solid(coords, true)
				bot_astar.set_point_solid(coords, true)
				# Chasms are walkable for flying bots!
				flying_astar.set_point_solid(coords, false)
				continue
				
			var is_water = tile_data.get_custom_data("is_water")
			if is_water:
				enemy_astar.set_point_weight_scale(coords, 10.0)
				bot_astar.set_point_solid(coords, true)
				# Water is walkable for flying bots!
				flying_astar.set_point_solid(coords, false)

			if object_layer.get_cell_source_id(coords) != -1:
				enemy_astar.set_point_solid(coords, true)
				bot_astar.set_point_solid(coords, true)
				# Real placed buildings are still solid for flying bots to prevent overlapping
				flying_astar.set_point_solid(coords, true)



## Toggles the solid/obstacle state of a specific coordinate in all three grids.
func set_obstacle(coords: Vector2i, is_solid: bool):
	if enemy_astar.is_in_boundsv(coords):
		enemy_astar.set_point_solid(coords, is_solid)
		bot_astar.set_point_solid(coords, is_solid)
		flying_astar.set_point_solid(coords, is_solid)



## Configures path weight scale costs for coordinate cells, differentiating enemy and bot behaviors.
func set_weighted_obstacle(coords: Vector2i, cost: float, is_solid_for_bots: bool = false):
	if enemy_astar.is_in_boundsv(coords):
		# Enemies ALWAYS see it as a costly path (so they attack it or wade through it)
		enemy_astar.set_point_solid(coords, false)
		enemy_astar.set_point_weight_scale(coords, cost)
		
		# Bots see it based on what you tell them!
		if is_solid_for_bots:
			# It's a Wall! Completely block the bot.
			bot_astar.set_point_solid(coords, true)
			# Flying bots fly over walls!
			flying_astar.set_point_solid(coords, false)
		else:
			# It's Water/Mud! Let the bot walk through it, but apply the cost penalty.
			bot_astar.set_point_solid(coords, false)
			bot_astar.set_point_weight_scale(coords, cost)
			
			flying_astar.set_point_solid(coords, false)



## Special gate path rules: bots treat gates as walkable, enemies calculate weights based on gate state.
func set_gate_obstacle(coords: Vector2i, cost: float, is_open: bool):
	if enemy_astar.is_in_boundsv(coords):
		# Bots ALWAYS see gates as 1.0 cost (open doors)
		bot_astar.set_point_solid(coords, false)
		bot_astar.set_point_weight_scale(coords, 1.0)
		
		# Flying bots also see gates as open doors
		flying_astar.set_point_solid(coords, false)
		flying_astar.set_point_weight_scale(coords, 1.0)
		
		# Enemies see the truth! 1.0 if open, HP Cost if closed.
		enemy_astar.set_point_solid(coords, false)
		enemy_astar.set_point_weight_scale(coords, 1.0 if is_open else cost)



## Traces and returns a path routing vector array between two world space vectors.
func get_path_route(start_world: Vector2, end_world: Vector2, is_bot: bool = false, is_flying: bool = false) -> PackedVector2Array:
	var active_astar = enemy_astar
	if is_flying:
		active_astar = flying_astar
	elif is_bot:
		active_astar = bot_astar
	
	var start_local = main_layer.to_local(start_world)
	var end_local = main_layer.to_local(end_world)
	var start_grid = main_layer.local_to_map(start_local)
	var end_grid = main_layer.local_to_map(end_local)
	
	var path_points = active_astar.get_point_path(start_grid, end_grid)
	
	var world_path = PackedVector2Array()
	for point in path_points:
		var local_pos = main_layer.map_to_local(point)
		world_path.append(main_layer.to_global(local_pos))
		
	return world_path
