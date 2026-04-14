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

# --- NEW: EVOLUTION & PRESSURE ---
@export_group("Evolution")
var corruption_tier: int = 1
var current_pressure: float = 0.0
@export var base_evolution_threshold: float = 100.0 
@export var evolution_multiplier: float = 3.0 # Tier 2 = 100, Tier 3 = 300, Tier 4 = 900

signal corruption_evolved(new_tier: int)

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
	
	var blocked_attempts = 0
	
	# Process from the end of the array backwards so we can safely delete items
	while i >= 0 and edges_processed < tiles_per_tick:
		var edge_tile = active_edges[i]
		
		# Safety check: Did the player build a tower and erase this tile?
		if corruption_layer.get_cell_source_id(edge_tile) == -1:
			active_edges.remove_at(i)
			i -= 1
			continue
			
		var result = _try_infect_neighbors(edge_tile)
		
		# Did it spread?
		if not result["has_empty"]:
			active_edges.remove_at(i)
			
		# Did it hit a shield?
		blocked_attempts += result["blocked_count"]
			
		edges_processed += 1
		i -= 1
		
	if blocked_attempts > 0:
		_add_pressure(blocked_attempts * 1.0)

# We now return a Dictionary so we can report back IF we spread, AND how many times we were blocked!
func _try_infect_neighbors(center_tile: Vector2i) -> Dictionary:
	var directions = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var has_empty_neighbors = false
	var blocked_count = 0
	
	for dir in directions:
		var neighbor = center_tile + dir
		
		if corruption_layer.get_cell_source_id(neighbor) != -1:
			continue
			
		# --- UPDATED: RESISTANCE CHECK ---
		var resistance = building_manager.safe_tiles.get(neighbor, 0)
		
		if resistance > 0:
			# If the shield is stronger than the corruption, it blocks it!
			if resistance >= corruption_tier:
				blocked_count += 1
				continue # Blocked! Move to the next neighbor.
			else:
				# The Corruption is a higher tier than the shield! It breaks through!
				pass 
		# ---------------------------------
			
		var has_floor = terrain_layer and terrain_layer.get_cell_source_id(neighbor) != -1
		if has_floor:
			var has_obstacle = object_layer and object_layer.get_cell_source_id(neighbor) != -1
			if has_obstacle:
				if randf() > 0.25:
					return {"has_empty": true, "blocked_count": blocked_count} 
			
			has_empty_neighbors = true
			_corrupt_tile(neighbor)
			return {"has_empty": true, "blocked_count": blocked_count}
			
	return {"has_empty": has_empty_neighbors, "blocked_count": blocked_count}

func _add_pressure(amount: float):
	current_pressure += amount
	
	# Calculate the goal for the CURRENT tier using an exponential curve
	# Tier 1 -> 100 * (3.0 ^ 0) = 100
	# Tier 2 -> 100 * (3.0 ^ 1) = 300
	# Tier 3 -> 100 * (3.0 ^ 2) = 900
	var threshold = base_evolution_threshold * pow(evolution_multiplier, corruption_tier - 1)
	
	if current_pressure >= threshold:
		current_pressure -= threshold # Carry over leftover pressure
		corruption_tier += 1
		
		print("!!! CORRUPTION MUTATED TO TIER %d !!!" % corruption_tier)
		corruption_evolved.emit(corruption_tier)

# Returns the total number of infected tiles on the map
func get_corruption_size() -> int:
	if not corruption_layer: return 0
	return corruption_layer.get_used_cells().size()
	
func _corrupt_tile(tile: Vector2i):
	corruption_layer.set_cell(tile, corruption_source_id, corruption_atlas)
	if not active_edges.has(tile):  
		active_edges.append(tile)
		
# ==========================================
# SAVE / LOAD SYSTEM
# ==========================================
func get_save_data() -> Dictionary:
	var active_edges_str = []
	for edge in active_edges:
		active_edges_str.append(var_to_str(edge))
		
	var infected_tiles_str = []
	if corruption_layer:
		for cell in corruption_layer.get_used_cells():
			infected_tiles_str.append(var_to_str(cell))
			
	return {
		"corruption_tier": corruption_tier,
		"current_pressure": current_pressure,
		"is_active": is_active,
		"active_edges": active_edges_str,
		"infected_tiles": infected_tiles_str
	}

func load_save_data(data: Dictionary):
	corruption_tier = data.get("corruption_tier", 1)
	current_pressure = data.get("current_pressure", 0.0)
	is_active = data.get("is_active", false)
	
	# 1. Restore the active growing edges
	active_edges.clear()
	if data.has("active_edges"):
		var saved_edges = data["active_edges"]
		for edge_str in saved_edges:
			active_edges.append(str_to_var(edge_str))
			
	# 2. Visually repaint the purple fog!
	if corruption_layer:
		corruption_layer.clear()
		if data.has("infected_tiles"):
			var saved_tiles = data["infected_tiles"]
			for tile_str in saved_tiles:
				var cell = str_to_var(tile_str)
				corruption_layer.set_cell(cell, corruption_source_id, corruption_atlas)
				
	# 3. Resume the spread timer if the outbreak had already started
	if is_active and spread_timer:
		if spread_timer.is_stopped():
			spread_timer.start()
