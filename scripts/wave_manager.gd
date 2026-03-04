@tool
extends Node2D
class_name WaveManager

# --- REFERENCES ---
@export var level_ref: Node2D
@export var corruption_layer: TileMapLayer 
@export var enemy_scene: PackedScene
@export var time_manager: TimeManager # <--- DRAG YOUR TIME MANAGER HERE!

# --- SPAWN SETTINGS ---
@export_group("Spawn Settings")
@export var show_debug_draw: bool = true:
	set(value):
		show_debug_draw = value
		queue_redraw()

@export var fallback_spawn_center: Vector2 = Vector2(1600, 1600):
	set(value):
		fallback_spawn_center = value
		queue_redraw()

@export var fallback_spawn_radius: float = 800.0:
	set(value):
		fallback_spawn_radius = value
		queue_redraw()

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
var active_enemies: int = 0
var is_wave_active: bool = false
var spawn_accumulator: float = 0.0

# Added 'night_type' so your UI can announce Blood Moons!
signal wave_started(wave_num: int, night_type: String) 
signal wave_ended(wave_num: int)
signal wave_stats_updated(to_spawn: int, active: int)

func _ready():
	if Engine.is_editor_hint(): return
	
	# Listen to the global clock!
	if time_manager:
		time_manager.night_started.connect(_on_night_started)
		time_manager.day_started.connect(_on_day_started)

# --- EDITOR DRAWING ---
func _draw():
	if not show_debug_draw: return
	var col = Color(1, 0, 0, 0.3)
	draw_circle(fallback_spawn_center, fallback_spawn_radius, Color(1, 0, 0, 0.1))
	draw_arc(fallback_spawn_center, fallback_spawn_radius, 0, TAU, 64, Color(1, 0, 0, 0.8), 2.0)
	draw_line(fallback_spawn_center - Vector2(20, 0), fallback_spawn_center + Vector2(20, 0), col, 2.0)
	draw_line(fallback_spawn_center - Vector2(0, 20), fallback_spawn_center + Vector2(0, 20), col, 2.0)

# --- NIGHT EVENT LOGIC ---

func _on_night_started(day_num: int):
	current_wave = day_num
	is_wave_active = true
	spawn_accumulator = 0.0
	
	# 1. Roll the Night Type
	var roll = randf()
	var night_type = "Normal"
	var multiplier = 1.0
	
	if roll < 0.15:     # 15% Chance of peace
		night_type = "Full Moon"
		multiplier = 0.0
	elif roll > 0.85:   # 15% Chance of chaos
		night_type = "Blood Moon"
		multiplier = 2.0
		
	else:
		# --- NEW: Organic Variance for Normal Nights ---
		# Multiplier will be a random decimal between 0.8 (-20%) and 1.2 (+20%)
		multiplier = randf_range(0.8, 1.2)
		
	# 2. Calculate the horde size
	var base_enemies = initial_enemy_count * pow(difficulty_multiplier, current_wave - 1)
	night_enemies_total = round(base_enemies * multiplier)
	enemies_to_spawn = night_enemies_total
	
	print("Night %d [%s]: %d enemies inbound." % [current_wave, night_type, enemies_to_spawn])
	
	wave_started.emit(current_wave, night_type)
	wave_stats_updated.emit(enemies_to_spawn, active_enemies)

func _on_day_started(day_num: int):
	is_wave_active = false
	print("Sunrise! Night %d survived." % current_wave)
	wave_ended.emit(current_wave)
	# Note: Any enemies still alive stay on the map for the player to clean up!

# --- CONTINUOUS CURVE SPAWNING ---

func _process(delta: float):
	if Engine.is_editor_hint(): return
	
	# If it's daytime, or we ran out of enemies to spawn, do nothing
	if not is_wave_active or enemies_to_spawn <= 0: 
		return

	# 1. Map current time to an X coordinate between -1.0 and 1.0
	var time = time_manager.current_time
	var x: float = 0.0
	if time >= 18.0:
		x = (time - 24.0) / 6.0 # Maps 18:00 to -1.0, Midnight to 0.0
	elif time < 6.0:
		x = time / 6.0          # Maps Midnight to 0.0, 06:00 to 1.0
	else:
		return 

	# 2. The Bell Curve (Parabola)
	# curve is 0.0 at sunset, peaks at 1.0 exactly at midnight, drops to 0.0 at sunrise
	var curve = 1.0 - (x * x)

	# 3. Calculate dynamic spawn rate
	# To ensure exactly 'night_enemies_total' spawn under this curve, the peak rate at midnight 
	# must be exactly 1.5x the average rate.
	var night_duration_sec = (time_manager.real_minutes_per_day * 60.0) / 2.0
	var peak_rate = (1.5 * night_enemies_total) / night_duration_sec
	var current_spawn_rate = peak_rate * curve

	# 4. Accumulate and Spawn
	spawn_accumulator += current_spawn_rate * delta
	
	while spawn_accumulator >= 1.0 and enemies_to_spawn > 0:
		spawn_accumulator -= 1.0
		_do_spawn()

# --- SPAWN AND DEATH HANDLERS ---

func _do_spawn():
	enemies_to_spawn -= 1
	active_enemies += 1
	
	var spawn_pos = _get_best_spawn_position()
	
	if not enemy_scene: return
	var enemy = enemy_scene.instantiate()
	
	if level_ref: level_ref.add_child(enemy)
	else: get_parent().add_child(enemy)
		
	enemy.global_position = spawn_pos
	
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	if enemy.has_signal("enemy_clicked"): 
		enemy.enemy_clicked.connect(_on_enemy_clicked)
		
	wave_stats_updated.emit(enemies_to_spawn, active_enemies)

func _on_enemy_died(_enemy_instance):
	active_enemies -= 1
	wave_stats_updated.emit(enemies_to_spawn, active_enemies)

func _get_best_spawn_position() -> Vector2:
	if corruption_layer:
		var used_cells = corruption_layer.get_used_cells()
		if not used_cells.is_empty():
			return corruption_layer.map_to_local(used_cells.pick_random())
			
	var angle = randf() * TAU
	return fallback_spawn_center + Vector2(cos(angle), sin(angle)) * fallback_spawn_radius

# --- NEW: UI HELPER ---
func get_estimated_enemies() -> int:
	if not time_manager: return 0
	
	# The upcoming night is always equal to the current day number
	var upcoming_wave = time_manager.current_day 
	
	# Do the exact same base math we do at sunset!
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
