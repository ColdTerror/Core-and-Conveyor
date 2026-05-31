# ==============================================================================
# Script: Enemy & Related/wave_manager.gd
# Purpose: Manages wave pacing and scaling horde spawning during night event phases,
#          applying time-of-day math, elite scaling, and quota penalties.
# Dependencies: Requires TimeManager, CorruptionManager, exports for Level,
#               corruption_layer, and enemy_scene. Group "Enemies".
# Signals: None.
# ==============================================================================
extends Node2D
class_name WaveManager

# --- REFERENCES ---
@export var level_ref: Node2D
@export var corruption_layer: TileMapLayer 
@export var enemy_scene: PackedScene
@export var time_manager: TimeManager
@export var corruption_manager: CorruptionManager

# --- SPAWN SETTINGS ---
@export_group("Spawn Settings")
@export var fallback_spawn_center: Vector2 = Vector2(1600, 1600)
@export var fallback_spawn_radius: float = 800.0

# --- WAVE PACING ---
@export_group("Wave Pacing")
@export var initial_enemy_count: int = 4
@export var difficulty_multiplier: float = 1.2 
@export var corruption_penalty_factor: float = 0.01 # <--- NEW: 1 extra enemy per 100 tiles
var pending_raid_penalty: float = 0.0

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

## Connects dawn and dusk event signals from the TimeManager autoload.
func _ready():
	# Listen to the global clock!
	if time_manager:
		time_manager.night_started.connect(_on_night_started)
		time_manager.day_started.connect(_on_day_started)



## Triggers the start of a night wave, calculating horde scaling and moon multipliers.
func _on_night_started(day_num: int):
	current_wave = day_num
	is_wave_active = true
	spawn_accumulator = 0.0
	
	var night_type = "Normal"
	var multiplier = 1.0
	
	# Look at the TimeManager's Global Moon Phase!
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
		# Add 1 extra enemy for every 5 points of penalty (Adjust this math to your liking!)
		var raid_bonus = int(pending_raid_penalty / 5.0)
		extra_enemies += raid_bonus
		print("!!! ENRAGED HORDE !!! Adding %d extra enemies to the wave!" % raid_bonus)
		
		# Clear the penalty so it only happens once
		pending_raid_penalty = 0.0 
		night_type = "RAID NIGHT"
		
	night_enemies_total = round((base_enemies + extra_enemies) * multiplier)
	enemies_to_spawn = night_enemies_total
	
	print("Night %d [%s]: %d enemies inbound." % [current_wave, night_type, enemies_to_spawn])



## Concludes the active night wave and forces any unspawned horde units to dawn rush.
func _on_day_started(day_num: int):
	# The sun just came up on a new day, which means the night we just survived was "yesterday" (day_num - 1).
	# max(1, ...) just prevents it from saying "Night 0" on the very first skip!
	current_wave = max(1, day_num - 1)
	
	if enemies_to_spawn > 0:
		print("Dawn Rush! Forcing %d stragglers to spawn!" % enemies_to_spawn)
		while enemies_to_spawn > 0:
			_do_spawn()
	
	is_wave_active = false
	print("Sunrise! Night %d survived." % current_wave)



## Drives continuous curve spawning distribution throughout active night waves.
func _process(delta: float):
	if not is_wave_active or enemies_to_spawn <= 0: 
		return

	var time = time_manager.current_time
	var x: float = 0.0
	if time >= 18.0:
		x = (time - 24.0) / 6.0
	elif time < 6.0:
		x = time / 6.0         
	else:
		return 

	var curve: float = 0.0
	if x < 0.0:
		curve = 1.0 - pow(abs(x), spawn_curve_exponent_dusk)
	else:
		curve = 1.0 - pow(abs(x), spawn_curve_exponent_dawn)

	var night_duration_sec = (time_manager.real_minutes_per_day * 60.0) / 2.0
	var area = 2.0 - (1.0 / (spawn_curve_exponent_dusk + 1.0)) - (1.0 / (spawn_curve_exponent_dawn + 1.0))
	var normalization = 2.0 / area
	var peak_rate = (normalization * night_enemies_total) / night_duration_sec
	var current_spawn_rate = peak_rate * curve

	spawn_accumulator += current_spawn_rate * delta
	
	while spawn_accumulator >= 1.0 and enemies_to_spawn > 0:
		spawn_accumulator -= 1.0
		_do_spawn()



## Spawns an individual enemy unit, scales elite mutations, and registers death handlers.
func _do_spawn():
	enemies_to_spawn -= 1
	
	var spawn_pos = _get_best_spawn_position()
	
	if not enemy_scene: return
	var enemy = enemy_scene.instantiate()
	
	enemy.add_to_group("Enemies") 
	
	if corruption_manager:
		# 10% chance per corruption tier (Tier 1 = 10%, Tier 2 = 20%, etc.)
		var elite_chance = corruption_manager.corruption_tier * 0.10
		
		# Roll the dice!
		if randf() < elite_chance:
			
			# Duck-type check just to be safe
			if "max_health" in enemy and "health" in enemy:
				enemy.max_health *= 2
				enemy.health = enemy.max_health
				
			# Visually mutate them so the player knows to panic!
			enemy.modulate = Color(0.8, 0.2, 1.0) # Deep Purple
			enemy.scale = Vector2(1.2, 1.2)       # 20% Larger
	
	if level_ref: level_ref.add_child(enemy)
	else: get_parent().add_child(enemy)
		
	enemy.global_position = spawn_pos
	
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)



## Handles actions needed when an individual enemy dies.
func _on_enemy_died(_enemy_instance):
	pass



## Selects a spawn point within active purple fog zones or along fallback radiuses.
func _get_best_spawn_position() -> Vector2:
	if corruption_layer:
		var used_cells = corruption_layer.get_used_cells()
		if not used_cells.is_empty():
			return corruption_layer.map_to_local(used_cells.pick_random())
			
	var angle = randf() * TAU
	return fallback_spawn_center + Vector2(cos(angle), sin(angle)) * fallback_spawn_radius



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
		"live_enemies": live_enemies_data
	}



## Restores wave progression and spawns saved enemies from game state dictionary.
func load_save_data(data: Dictionary):
	current_wave = data.get("current_wave", 0)
	night_enemies_total = data.get("night_enemies_total", 0)
	enemies_to_spawn = data.get("enemies_to_spawn", 0)
	is_wave_active = data.get("is_wave_active", false)
	spawn_accumulator = data.get("spawn_accumulator", 0.0)
	pending_raid_penalty = data.get("pending_raid_penalty", 0.0)
	
	# Spawn the saved enemies
	if data.has("live_enemies") and enemy_scene:
		var saved_enemies = data["live_enemies"]
		
		for enemy_data in saved_enemies:
			var enemy = enemy_scene.instantiate()
			enemy.add_to_group("Enemies")
			
			# Wire up signals
			if enemy.has_signal("died"):
				enemy.died.connect(_on_enemy_died)
				
			# Add them to the map
			if level_ref: level_ref.add_child(enemy)
			else: get_parent().add_child(enemy)
				
			# INJECT THE DATA (This instantly teleports them to their saved location!)
			if enemy.has_method("load_save_data"):
				enemy.load_save_data(enemy_data)
