extends Node2D
class_name CorruptionManager

@export_group("References")
@export var corruption_layer: TileMapLayer
@export var terrain_layer: TileMapLayer  # The floor (grass, sand)
@export var object_layer: TileMapLayer   # Obstacles (water, rocks)
@export var building_manager: BuildingManager
@export var wave_manager: WaveManager
@export var time_manager: TimeManager   

@export_group("Settings")
@export var tiles_per_tick: int = 5        # How many tiles it infects per tick
@export var corruption_source_id: int = 0  # The TileSet ID for your purple fog
@export var corruption_atlas: Vector2i = Vector2i(0, 0) # The coordinates of the tile

# --- NEW: DYNAMIC SPREAD SPEEDS ---
@export_group("Spread Speeds")
@export var day_spread_time: float = 2.0           # Slow and manageable during the day
@export var normal_night_spread_time: float = 1.0  # Aggressive at night
@export var full_moon_spread_time: float = 3.0     # Extremely slow (gives the player a break)
@export var blood_moon_spread_time: float = 0.5    # Terrifyingly fast!

var active_edges: Array[Vector2i] = []
var is_active: bool = false
var spread_timer: Timer

func _ready():
	spread_timer = Timer.new()
	spread_timer.wait_time = day_spread_time # Default to day speed
	spread_timer.timeout.connect(_on_spread_tick)
	add_child(spread_timer)
	
	# --- NEW: LISTEN TO THE CLOCK ---
	if time_manager:
		time_manager.day_started.connect(_on_day_started)
		time_manager.night_started.connect(_on_night_started)

# ==========================================
# DAY/NIGHT REACTIONS
# ==========================================
func _on_day_started(_day_num: int):
	# The sun is up, slow the corruption down!
	if spread_timer:
		spread_timer.wait_time = day_spread_time
		print("Corruption slows from the sunlight. (Speed: Slow)")

func _on_night_started(_day_num: int):
	if not spread_timer or not time_manager: return
	
	# Ask the TimeManager what phase the moon is in, and set the speed!
	match time_manager.current_moon_phase:
		TimeManager.MoonPhase.NORMAL:
			spread_timer.wait_time = normal_night_spread_time
			print("Corruption strengthens in the dark. (Speed: Fast)")
		TimeManager.MoonPhase.FULL:
			spread_timer.wait_time = full_moon_spread_time
			print("The Full Moon suppresses the Corruption. (Speed: Very Slow)")
		TimeManager.MoonPhase.BLOOD:
			spread_timer.wait_time = blood_moon_spread_time
			print("The Blood Moon enrages the Corruption! (Speed: EXTREME)")

# ==========================================
# CORE SPREAD LOGIC
# ==========================================

# --- INITIAL OUTBREAK ---
func start_outbreak(core_pos: Vector2i):
	print_debug("start outbreak")
	if is_active: return
	
	# FIND THE ABSOLUTE FURTHEST LAND TILE
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
	
	# Plant the seed
	_corrupt_tile(seed_pos)
	
	is_active = true
	spread_timer.start()
	print("Corruption Outbreak Detected at: ", seed_pos)
	
# --- SPREAD LOGIC ---
func _on_spread_tick():
	if active_edges.is_empty(): 
		return
	
	# Shuffle so the growth looks organic and chaotic
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
			
		# 2. Is it in the player's Safe Zone?
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
