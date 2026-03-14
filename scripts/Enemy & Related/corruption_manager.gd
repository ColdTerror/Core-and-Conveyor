extends Node2D
class_name CorruptionManager

@export_group("References")
@export var corruption_layer: TileMapLayer
@export var terrain_layer: TileMapLayer  # The floor (grass, sand)
@export var object_layer: TileMapLayer   # Obstacles (water, rocks)
@export var building_manager: BuildingManager
@export var wave_manager: WaveManager


@export_group("Settings")
@export var spread_interval: float = 1.0  # How often the corruption ticks
@export var tiles_per_tick: int = 5       # How many tiles it infects per tick
@export var corruption_source_id: int = 0 # The TileSet ID for your purple fog
@export var corruption_atlas: Vector2i = Vector2i(0, 0) # The coordinates of the tile

var active_edges: Array[Vector2i] = []
var is_active: bool = false
var spread_timer: Timer

func _ready():
	spread_timer = Timer.new()
	spread_timer.wait_time = spread_interval
	spread_timer.timeout.connect(_on_spread_tick)
	add_child(spread_timer)

# --- INITIAL OUTBREAK ---
func start_outbreak(core_pos: Vector2i):
	print_debug("start outbreak")
	if is_active: return
	
	# --- FIXED: FIND THE ABSOLUTE FURTHEST LAND TILE ---
	var seed_pos: Vector2i = core_pos
	var max_dist: float = -1.0
	
	# Get every single floor tile currently drawn on the map
	var all_floor_tiles = terrain_layer.get_used_cells()
	
	for tile in all_floor_tiles:
		var tile_data = terrain_layer.get_cell_tile_data(tile)
		
		# ONLY check the distance if the tile is actually buildable land (not water!)
		if tile_data and tile_data.get_custom_data("buildable") == true:
			
			var dist = Vector2(core_pos).distance_squared_to(Vector2(tile))
			if dist > max_dist:
				max_dist = dist
				seed_pos = tile
	# ----------------------------------------------
	
	# 2. Plant the seed
	_corrupt_tile(seed_pos)
	
	is_active = true
	spread_timer.start()
	print("Corruption Outbreak Detected at: ", seed_pos)
	
# --- SPREAD LOGIC ---
func _on_spread_tick():
	if active_edges.is_empty(): 
		return
	
	# Shuffle so the growth looks organic and chaotic, not like a perfect diamond
	active_edges.shuffle()
	
	var edges_processed = 0
	var i = active_edges.size() - 1
	
	# Process from the end of the array backwards so we can safely delete items
	while i >= 0 and edges_processed < tiles_per_tick:
		var edge_tile = active_edges[i]
		
		# Safety check: Did the player build a tower and erase this tile?
		if corruption_layer.get_cell_source_id(edge_tile) == -1:
			active_edges.remove_at(i)
			i -= 1
			continue
			
		var spread_success = _try_infect_neighbors(edge_tile)
		
		# If this tile has no empty neighbors left, it's no longer an "edge"
		if not spread_success:
			active_edges.remove_at(i)
			
		edges_processed += 1
		i -= 1

func _try_infect_neighbors(center_tile: Vector2i) -> bool:
	var directions = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var has_empty_neighbors = false
	
	for dir in directions:
		var neighbor = center_tile + dir
		
		# 1. Is it already corrupted?
		if corruption_layer.get_cell_source_id(neighbor) != -1:
			continue
			
		# 2. Is it in the player's Safe Zone? (O(1) dictionary check!)
		if building_manager.safe_tiles.has(neighbor):
			continue
			
		# 3. Is it valid terrain? (Has floor, but no physical obstacles)
		var has_floor = terrain_layer and terrain_layer.get_cell_source_id(neighbor) != -1
		
		if has_floor:
			# --- RNG OBSTACLE BREACHING ---
			var has_obstacle = object_layer and object_layer.get_cell_source_id(neighbor) != -1
			
			if has_obstacle:
				# Roll the dice! A 75% chance to fail the breach.
				if randf() > 0.25:
					# We failed to breach this tick, but we return true so the 
					# tile stays active and tries again next tick!
					return true 
			# ------------------------------
			
			# If there's no obstacle, OR we hit the lucky 25% chance:
			has_empty_neighbors = true
			_corrupt_tile(neighbor)
			return true
			
	return has_empty_neighbors

func _corrupt_tile(tile: Vector2i):
	corruption_layer.set_cell(tile, corruption_source_id, corruption_atlas)
	active_edges.append(tile)
