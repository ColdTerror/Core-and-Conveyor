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

# --- SELECTION ---
@export var enemy_popup: Control 
var selected_enemy: Enemy = null

# --- STATE ---
var current_wave: int = 0
var night_enemies_total: int = 0
var enemies_to_spawn: int = 0
var is_wave_active: bool = false
var spawn_accumulator: float = 0.0

func _ready():
	# Listen to the global clock!
	if time_manager:
		time_manager.night_started.connect(_on_night_started)
		time_manager.day_started.connect(_on_day_started)

# --- NIGHT EVENT LOGIC ---

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
	night_enemies_total = round(base_enemies * multiplier)
	enemies_to_spawn = night_enemies_total
	
	print("Night %d [%s]: %d enemies inbound." % [current_wave, night_type, enemies_to_spawn])

func _on_day_started(day_num: int):
	if enemies_to_spawn > 0:
		print("Dawn Rush! Forcing %d stragglers to spawn!" % enemies_to_spawn)
		while enemies_to_spawn > 0:
			_do_spawn()
	
	is_wave_active = false
	print("Sunrise! Night %d survived." % current_wave)

# --- CONTINUOUS CURVE SPAWNING ---

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

	var curve = 1.0 - (x * x)

	var night_duration_sec = (time_manager.real_minutes_per_day * 60.0) / 2.0
	var peak_rate = (1.5 * night_enemies_total) / night_duration_sec
	var current_spawn_rate = peak_rate * curve

	spawn_accumulator += current_spawn_rate * delta
	
	while spawn_accumulator >= 1.0 and enemies_to_spawn > 0:
		spawn_accumulator -= 1.0
		_do_spawn()

# --- SPAWN AND DEATH HANDLERS ---

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
	if enemy.has_signal("enemy_clicked"): 
		enemy.enemy_clicked.connect(_on_enemy_clicked)

func _on_enemy_died(_enemy_instance):
	pass

func _get_best_spawn_position() -> Vector2:
	if corruption_layer:
		var used_cells = corruption_layer.get_used_cells()
		if not used_cells.is_empty():
			return corruption_layer.map_to_local(used_cells.pick_random())
			
	var angle = randf() * TAU
	return fallback_spawn_center + Vector2(cos(angle), sin(angle)) * fallback_spawn_radius

# --- UI HELPER ---
func get_estimated_enemies() -> int:
	if not time_manager: return 0
	
	var upcoming_wave = time_manager.current_day 
	var base_enemies = initial_enemy_count * pow(difficulty_multiplier, upcoming_wave - 1)
	return round(base_enemies)
	
# --- UI CLICKS ---
func _on_enemy_clicked(enemy):
	selected_enemy = enemy
	if enemy_popup: enemy_popup.show_info(enemy)

func deselect_enemy():
	if selected_enemy:
		selected_enemy = null
		if enemy_popup: enemy_popup.hide_info()
