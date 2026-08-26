# ==============================================================================
# Script: Enemy & Related/wave_manager.gd
# Purpose: Manages wave pacing and scaling horde spawning during night event phases,
#          applying time-of-day math, elite scaling, quota penalties, and a hybrid
#          50/50 trickle & scheduled group mini-wave spawning system.
# Dependencies: Requires TimeManager, CorruptionManager, exports for Level,
#               corruption_layer, and enemy_scene. Group "Enemies".
# Signals: None.
# ==============================================================================
extends Node2D
class_name WaveManager

# --- REFERENCES ---
@export var level_ref: Node2D
@export var corruption_layer: TileMapLayer 
@export var terrain_layer: TileMapLayer
@export var enemy_scene: PackedScene # Fallback / Regular
@export var fast_scene: PackedScene
@export var ranged_scene: PackedScene
@export var flyer_scene: PackedScene
@export var slime_large_scene: PackedScene
@export var time_manager: TimeManager
@export var corruption_manager: CorruptionManager

# --- SPAWN SETTINGS ---
@export_group("Spawn Settings")
@export var fallback_spawn_center: Vector2 = Vector2(1600, 1600)
@export var fallback_spawn_radius: float = 800.0

# --- WAVE PACING ---
@export_group("Wave Pacing")
@export var initial_enemy_count: int = 15
@export var difficulty_multiplier: float = 1.25 
@export var corruption_penalty_factor: float = 0.005 # 1 extra enemy per 200 tiles
var pending_raid_penalty: float = 0.0

# --- HYBRID SPAWNING SETTINGS ---
@export_group("Hybrid Spawning")
@export var trickle_ratio: float = 0.5 # 50% trickle background pressure, 50% group mini-waves
@export var min_groups_per_night: int = 3
@export var max_groups_per_night: int = 5
@export var min_hours_between_groups: float = 1.0 # Minimum in-game hours between scheduled groups

# --- WAVE SPAWNING CURVE ---
@export_group("Wave Spawning Curve")
@export var spawn_curve_exponent_dusk: float = 3.0
@export var spawn_curve_exponent_dawn: float = 2.0

# --- STATE ---
var current_wave: int = 0
var night_enemies_total: int = 0
var enemies_to_spawn: int = 0
var is_wave_active: bool = false
var spawn_accumulator: float = 0.0

var trickle_enemies_total: int = 0
var trickle_enemies_remaining: int = 0
var group_enemies_total: int = 0
var group_enemies_remaining: int = 0
var scheduled_groups: Array[Dictionary] = []

## Connects dawn and dusk event signals from the TimeManager autoload.
func _ready():
	# Listen to the global clock!
	if time_manager:
		time_manager.night_started.connect(_on_night_started)
		time_manager.day_started.connect(_on_day_started)



## Triggers the start of a night wave, calculating horde scaling and scheduling group mini-waves.
func _on_night_started(day_num: int):
	current_wave = day_num
	is_wave_active = true
	spawn_accumulator = 0.0
	
	var night_type = "Normal"
	var multiplier = 1.0
	
	# Look at the TimeManager's Global Moon Phase!
	if time_manager:
		match time_manager.current_moon_phase:
			TimeManager.MoonPhase.FULL:
				night_type = "Full Moon"
				multiplier = 0.0
			TimeManager.MoonPhase.BLOOD:
				night_type = "Blood Moon"
				multiplier = 2.0
			TimeManager.MoonPhase.NORMAL:
				night_type = "Normal"
				multiplier = randf_range(0.8, 1.2)
		
	# Calculate the horde size
	var base_enemies = initial_enemy_count * pow(difficulty_multiplier, current_wave - 1)
	var extra_enemies = 0
	if corruption_manager:
		var land_size = corruption_manager.get_corruption_size()
		extra_enemies = round(land_size * corruption_penalty_factor)
		
		if extra_enemies > 0:
			print("The spreading Corruption spawned %d extra monsters!" % extra_enemies)
	
	if pending_raid_penalty > 0:
		var raid_bonus = int(pending_raid_penalty / 5.0)
		extra_enemies += raid_bonus
		print("!!! ENRAGED HORDE !!! Adding %d extra enemies to the wave!" % raid_bonus)
		
		pending_raid_penalty = 0.0 
		night_type = "RAID NIGHT"
		
	night_enemies_total = round((base_enemies + extra_enemies) * multiplier)
	enemies_to_spawn = night_enemies_total
	
	# Split enemies between trickle pool and group mini-waves
	trickle_enemies_total = round(night_enemies_total * trickle_ratio)
	trickle_enemies_remaining = trickle_enemies_total
	group_enemies_total = night_enemies_total - trickle_enemies_total
	group_enemies_remaining = group_enemies_total
	
	_schedule_night_groups()
	
	print("Night %d [%s]: %d enemies inbound (%d trickle, %d grouped in %d mini-waves)." % [
		current_wave, night_type, night_enemies_total, trickle_enemies_total, group_enemies_total, scheduled_groups.size()
	])



## Schedules 3 to 5 group spawn times across the night duration with minimum gaps and distributed counts.
func _schedule_night_groups():
	scheduled_groups.clear()
	if group_enemies_total <= 0:
		return
		
	var num_groups = randi_range(min_groups_per_night, max_groups_per_night)
	num_groups = min(num_groups, group_enemies_total) # Cannot have more groups than enemies
	if num_groups <= 0:
		return
		
	var sunset = 18.0
	var sunrise = 6.0
	if time_manager:
		sunset = time_manager.get_sunset_hour()
		sunrise = time_manager.get_sunrise_hour()
		
	var night_duration = (24.0 - sunset) + sunrise
	var start_margin = 0.5
	var end_margin = 0.5
	var usable_duration = night_duration - start_margin - end_margin
	
	if usable_duration <= 0:
		usable_duration = night_duration
		start_margin = 0.0
		
	var req_gap = min_hours_between_groups
	var slack = usable_duration - (num_groups - 1) * req_gap
	if slack < 0:
		req_gap = max(0.2, usable_duration / float(num_groups))
		slack = usable_duration - (num_groups - 1) * req_gap
		
	var raw_parts: Array[float] = []
	var sum_parts: float = 0.0
	for i in range(num_groups + 1):
		var r = randf_range(0.1, 1.0)
		raw_parts.append(r)
		sum_parts += r
		
	var times_since_sunset: Array[float] = []
	var accum_time = start_margin
	for i in range(num_groups):
		var portion = (raw_parts[i] / sum_parts) * slack
		accum_time += portion
		times_since_sunset.append(accum_time)
		accum_time += req_gap
		
	var base_count = group_enemies_total / num_groups
	var remainder = group_enemies_total % num_groups
	var group_counts: Array[int] = []
	for i in range(num_groups):
		var count = base_count
		if i < remainder:
			count += 1
		group_counts.append(count)
		
	if num_groups >= 2 and group_enemies_total >= 10:
		group_counts.shuffle()
		
	for i in range(num_groups):
		var t_since_sunset = times_since_sunset[i]
		var clock_hour = fmod(sunset + t_since_sunset, 24.0)
		scheduled_groups.append({
			"time_since_sunset": t_since_sunset,
			"clock_hour": clock_hour,
			"count": group_counts[i]
		})



## Converts an in-game hour into hours elapsed since sunset.
func _hours_since_sunset(h: float, sunset: float) -> float:
	if h >= sunset:
		return h - sunset
	else:
		return (24.0 - sunset) + h



## Concludes the active night wave and forces any unspawned horde units to dawn rush.
func _on_day_started(day_num: int):
	current_wave = max(1, day_num - 1)
	
	if enemies_to_spawn > 0:
		print("Dawn Rush! Forcing %d stragglers to spawn!" % enemies_to_spawn)
		while enemies_to_spawn > 0:
			if trickle_enemies_remaining > 0:
				_do_trickle_spawn()
			elif not scheduled_groups.is_empty():
				var group_data = scheduled_groups.pop_front()
				_do_group_spawn(group_data.get("count", 1))
			else:
				_do_trickle_spawn()
	
	is_wave_active = false
	scheduled_groups.clear()
	print("Sunrise! Night %d survived." % current_wave)



## Drives continuous curve spawning distribution for trickle pool and triggers scheduled group bursts.
func _process(delta: float):
	if not is_wave_active or enemies_to_spawn <= 0: 
		return

	var sunset = 18.0
	var sunrise = 6.0
	if time_manager:
		sunset = time_manager.get_sunset_hour()
		sunrise = time_manager.get_sunrise_hour()
	
	var time = time_manager.current_time if time_manager else 20.0
	var x: float = 0.0
	if time >= sunset:
		x = (time - 24.0) / (24.0 - sunset)
	elif time < sunrise:
		x = time / sunrise
	else:
		return 

	# --- 1. PROCESS CONTINUOUS TRICKLE SPAWNS ---
	if trickle_enemies_remaining > 0:
		var curve: float = 0.0
		if x < 0.0:
			curve = 1.0 - pow(abs(x), spawn_curve_exponent_dusk)
		else:
			curve = 1.0 - pow(abs(x), spawn_curve_exponent_dawn)

		var night_duration_hours = (24.0 - sunset) + sunrise
		var real_mins = time_manager.real_minutes_per_day if time_manager else 2.0
		var night_duration_sec = (real_mins * 60.0) * (night_duration_hours / 24.0)
		var area = 2.0 - (1.0 / (spawn_curve_exponent_dusk + 1.0)) - (1.0 / (spawn_curve_exponent_dawn + 1.0))
		var normalization = 2.0 / area
		var peak_rate = (normalization * trickle_enemies_total) / night_duration_sec
		var current_spawn_rate = peak_rate * curve

		spawn_accumulator += current_spawn_rate * delta
		
		while spawn_accumulator >= 1.0 and trickle_enemies_remaining > 0:
			spawn_accumulator -= 1.0
			_do_trickle_spawn()

	# --- 2. PROCESS SCHEDULED GROUP MINI-WAVES ---
	if not scheduled_groups.is_empty() and time_manager:
		var now_since_sunset = _hours_since_sunset(time, sunset)
		var i = scheduled_groups.size() - 1
		while i >= 0:
			var group_data = scheduled_groups[i]
			if now_since_sunset >= group_data.get("time_since_sunset", 0.0):
				scheduled_groups.remove_at(i)
				_do_group_spawn(group_data.get("count", 1))
			i -= 1



## Spawns a single trickle enemy along an active corruption edge or map boundary.
func _do_trickle_spawn():
	if enemies_to_spawn <= 0: return
	trickle_enemies_remaining -= 1
	enemies_to_spawn -= 1
	
	var spawn_pos = _get_single_edge_spawn_position()
	_instantiate_and_configure_enemy(spawn_pos)



## Spawns a group mini-wave burst with each enemy assigned its own distinct tile.
func _do_group_spawn(count: int):
	if count <= 0 or enemies_to_spawn <= 0: return
	var actual_count = min(count, enemies_to_spawn)
	group_enemies_remaining -= actual_count
	enemies_to_spawn -= actual_count
	
	var spawn_positions = _get_distinct_group_spawn_positions(actual_count)
	print("Group Mini-Wave Spawning %d monsters across distinct tiles." % spawn_positions.size())
	
	for spawn_pos in spawn_positions:
		_instantiate_and_configure_enemy(spawn_pos)



## Instantiates an enemy unit, scales stats, applies elite mutations, and connects signals.
func _instantiate_and_configure_enemy(spawn_pos: Vector2):
	var chosen_scene = _get_enemy_scene_for_wave(current_wave)
	if not chosen_scene: return
	
	var enemy = chosen_scene.instantiate()
	enemy.add_to_group("Enemies") 
	
	# Day Scaling (2.5% every day)
	var health_scale = 1 + (current_wave * 0.025)
	enemy.max_health *= health_scale
	enemy.health = enemy.max_health
	
	# Elite Mutation
	if corruption_manager:
		var elite_chance = corruption_manager.corruption_tier * 0.10
		if randf() < elite_chance:
			if "max_health" in enemy and "health" in enemy:
				enemy.max_health *= 2
				enemy.health = enemy.max_health
				
			enemy.modulate = Color(0.8, 0.2, 1.0) # Deep Purple
			enemy.scale = Vector2(1.5, 1.5)       # 20% Larger
	
	if level_ref: level_ref.add_child(enemy)
	else: get_parent().add_child(enemy)
		
	enemy.global_position = spawn_pos
	
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)



## Selects a single active corruption edge tile, or falls back to map boundary outer edges.
func _get_single_edge_spawn_position() -> Vector2:
	if corruption_manager and not corruption_manager.active_edges.is_empty():
		var edge_tile = corruption_manager.active_edges.pick_random()
		if corruption_layer:
			return corruption_layer.map_to_local(edge_tile)
			
	if corruption_layer:
		var used_cells = corruption_layer.get_used_cells()
		if not used_cells.is_empty():
			return corruption_layer.map_to_local(used_cells.pick_random())
			
	return _get_map_outer_edge_position()



## Finds N distinct neighboring corruption tiles for a group burst (each enemy gets its own tile).
func _get_distinct_group_spawn_positions(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	
	# Attempt to locate seed tile along active corruption edges
	var seed_tile: Vector2i = Vector2i.MIN
	if corruption_manager and not corruption_manager.active_edges.is_empty():
		seed_tile = corruption_manager.active_edges.pick_random()
	elif corruption_layer and not corruption_layer.get_used_cells().is_empty():
		seed_tile = corruption_layer.get_used_cells().pick_random()
		
	if seed_tile != Vector2i.MIN and corruption_layer:
		# Collect distinct neighboring corruption tiles via BFS
		var selected_tiles: Array[Vector2i] = [seed_tile]
		var visited = {seed_tile: true}
		var queue: Array[Vector2i] = [seed_tile]
		var dirs = [
			Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
		]
		
		while not queue.is_empty() and selected_tiles.size() < count:
			var curr = queue.pop_front()
			dirs.shuffle()
			for d in dirs:
				var n = curr + d
				if visited.has(n): continue
				visited[n] = true
				if corruption_layer.get_cell_source_id(n) != -1:
					selected_tiles.append(n)
					queue.append(n)
					if selected_tiles.size() == count:
						break
						
		for tile in selected_tiles:
			positions.append(corruption_layer.map_to_local(tile))
			
		# If corruption didn't have enough tiles for the full group, fill remaining with map edge fallbacks
		while positions.size() < count:
			positions.append(_get_map_outer_edge_position())
			
		return positions

	# FALLBACK: If no corruption exists at all, generate distinct map outer boundary positions
	for i in range(count):
		positions.append(_get_map_outer_edge_position())
		
	return positions



## Generates a random world position along the outer boundary edges of the terrain map layer.
func _get_map_outer_edge_position() -> Vector2:
	var rect = Rect2i(0, 0, 100, 100)
	if terrain_layer and not terrain_layer.get_used_cells().is_empty():
		rect = terrain_layer.get_used_rect()
		
	var side = randi() % 4
	var edge_tile = Vector2i.ZERO
	match side:
		0: # Top Edge
			edge_tile = Vector2i(randi_range(rect.position.x, rect.position.x + max(0, rect.size.x - 1)), rect.position.y)
		1: # Right Edge
			edge_tile = Vector2i(rect.position.x + max(0, rect.size.x - 1), randi_range(rect.position.y, rect.position.y + max(0, rect.size.y - 1)))
		2: # Bottom Edge
			edge_tile = Vector2i(randi_range(rect.position.x, rect.position.x + max(0, rect.size.x - 1)), rect.position.y + max(0, rect.size.y - 1))
		3: # Left Edge
			edge_tile = Vector2i(rect.position.x, randi_range(rect.position.y, rect.position.y + max(0, rect.size.y - 1)))
			
	if terrain_layer:
		return terrain_layer.map_to_local(edge_tile)
	return fallback_spawn_center + Vector2(cos(randf() * TAU), sin(randf() * TAU)) * fallback_spawn_radius



## Handles actions needed when an individual enemy dies.
func _on_enemy_died(_enemy_instance):
	pass



## Returns the expected number of enemy spawns for the upcoming night's wave.
func get_estimated_enemies() -> int:
	if not time_manager: return 0
	
	var upcoming_wave = time_manager.current_day 
	var base_enemies = initial_enemy_count * pow(difficulty_multiplier, upcoming_wave - 1)
	var extra_enemies = 0
	if corruption_manager:
		var land_size = corruption_manager.get_corruption_size()
		extra_enemies = round(land_size * corruption_penalty_factor)
		
	return round(base_enemies + extra_enemies)



## Records quota failure penalties to scale tomorrow night's wave intensity.
func apply_quota_penalty(penalty_amount: float):
	print("WARNING: Quota failed! The horde is enraged for tomorrow night!")
	pending_raid_penalty += penalty_amount



## Serializes wave states and living enemy data for game save storage.
func get_save_data() -> Dictionary:
	var live_enemies_data = []
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if enemy.has_method("get_save_data"):
			live_enemies_data.append(enemy.get_save_data())
	
	return {
		"current_wave": current_wave,
		"night_enemies_total": night_enemies_total,
		"enemies_to_spawn": enemies_to_spawn,
		"is_wave_active": is_wave_active,
		"spawn_accumulator": spawn_accumulator,
		"pending_raid_penalty": pending_raid_penalty,
		"trickle_enemies_total": trickle_enemies_total,
		"trickle_enemies_remaining": trickle_enemies_remaining,
		"group_enemies_total": group_enemies_total,
		"group_enemies_remaining": group_enemies_remaining,
		"scheduled_groups": scheduled_groups,
		"live_enemies": live_enemies_data
	}



## Selects the appropriate enemy scene to spawn based on progressive wave weights.
func _get_enemy_scene_for_wave(day: int) -> PackedScene:
	# Weights format: [Regular, Fast, Ranged, SlimeLarge, Flyer]
	var weights = [1.0, 0.0, 0.0, 0.0, 0.0]
	
	if time_manager:
		var year = time_manager.get_current_year()
		if year > 1:
			# Year 2+ Challenging Composition
			weights = [0.2, 0.2, 0.20, 0.25, 0.15]
		else:
			# Year 1 Progressive Composition
			if day == 1:
				weights = [1.0, 0.0, 0.0, 0.0, 0.0]
			else:
				match time_manager.get_current_season():
					TimeManager.Season.SPRING:
						weights = [0.7, 0.3, 0.0, 0.0, 0.0]
					TimeManager.Season.SUMMER:
						weights = [0.5, 0.3, 0.2, 0.0, 0.0]
					TimeManager.Season.AUTUMN:
						weights = [0.4, 0.25, 0.2, 0.15, 0.0]
					TimeManager.Season.WINTER:
						weights = [0.3, 0.25, 0.2, 0.15, 0.1]
	else:
		if day == 1:
			weights = [1.0, 0.0, 0.0, 0.0, 0.0]
		elif day == 2:
			weights = [0.7, 0.3, 0.0, 0.0, 0.0]
		elif day == 3:
			weights = [0.5, 0.3, 0.2, 0.0, 0.0]
		elif day == 4:
			weights = [0.4, 0.25, 0.2, 0.15, 0.0]
		else:
			weights = [0.3, 0.25, 0.2, 0.15, 0.1]
			
	var roll = randf()
	var cumulative_weight = 0.0
	var scenes = [enemy_scene, fast_scene, ranged_scene, slime_large_scene, flyer_scene]
	
	for i in range(weights.size()):
		cumulative_weight += weights[i]
		if roll <= cumulative_weight:
			var scene = scenes[i]
			if scene:
				return scene
			break
			
	return enemy_scene



## Restores wave progression and spawns saved enemies from game state dictionary.
func load_save_data(data: Dictionary):
	current_wave = data.get("current_wave", 0)
	night_enemies_total = data.get("night_enemies_total", 0)
	enemies_to_spawn = data.get("enemies_to_spawn", 0)
	is_wave_active = data.get("is_wave_active", false)
	spawn_accumulator = data.get("spawn_accumulator", 0.0)
	pending_raid_penalty = data.get("pending_raid_penalty", 0.0)
	trickle_enemies_total = data.get("trickle_enemies_total", 0)
	trickle_enemies_remaining = data.get("trickle_enemies_remaining", 0)
	group_enemies_total = data.get("group_enemies_total", 0)
	group_enemies_remaining = data.get("group_enemies_remaining", 0)
	
	scheduled_groups.clear()
	if data.has("scheduled_groups"):
		for group_dict in data["scheduled_groups"]:
			scheduled_groups.append(group_dict)
	
	# Spawn the saved enemies
	if data.has("live_enemies"):
		var saved_enemies = data["live_enemies"]
		
		for enemy_data in saved_enemies:
			var scene_to_load = enemy_scene
			var path = enemy_data.get("scene_file_path", "")
			if path != "" and ResourceLoader.exists(path):
				scene_to_load = load(path)
				
			if not scene_to_load:
				continue
				
			var enemy = scene_to_load.instantiate()
			enemy.add_to_group("Enemies")
			
			if enemy.has_signal("died"):
				enemy.died.connect(_on_enemy_died)
				
			if level_ref: level_ref.add_child(enemy)
			else: get_parent().add_child(enemy)
				
			if enemy.has_method("load_save_data"):
				enemy.load_save_data(enemy_data)
