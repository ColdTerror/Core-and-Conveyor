@tool # <--- THIS IS CRITICAL FOR EDITOR DRAWING
extends Node2D
class_name WaveManager

# --- REFERENCES ---
@export var level_ref: Node2D
@export var corruption_layer: TileMapLayer 
@export var enemy_scene: PackedScene

# --- SPAWN SETTINGS (Visible in Editor) ---
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

# --- WAVE SETTINGS ---
@export_group("Wave Settings")
@export var time_between_waves: float = 20.0
@export var initial_enemy_count: int = 4
@export var difficulty_multiplier: float = 1.2 

# --- SELECTION ---
@export var enemy_popup: Control 
var selected_enemy: Enemy = null

# --- STATE ---
var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_alive: int = 0
var is_wave_active: bool = false
var spawn_timer: Timer
var wave_timer: Timer

signal wave_started(wave_num: int)
signal wave_ended(wave_num: int)

func _ready():
	# Tool scripts run _ready in the editor too, so we prevent logic from running there
	if Engine.is_editor_hint(): return
	
	spawn_timer = Timer.new()
	spawn_timer.wait_time = 1.5 
	spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(spawn_timer)
	
	wave_timer = Timer.new()
	wave_timer.wait_time = time_between_waves
	wave_timer.timeout.connect(start_next_wave)
	add_child(wave_timer)
	
	wave_timer.start()

# --- EDITOR DRAWING ---
func _draw():
	if not show_debug_draw: return
	
	# Only draw this circle if we are NOT using corruption 
	# (or just always draw it as a backup reference)
	var col = Color(1, 0, 0, 0.3) # Red transparent
	
	# Draw the Circle
	draw_circle(fallback_spawn_center, fallback_spawn_radius, Color(1, 0, 0, 0.1))
	draw_arc(fallback_spawn_center, fallback_spawn_radius, 0, TAU, 64, Color(1, 0, 0, 0.8), 2.0)
	
	# Draw a cross at the center
	draw_line(fallback_spawn_center - Vector2(20, 0), fallback_spawn_center + Vector2(20, 0), col, 2.0)
	draw_line(fallback_spawn_center - Vector2(0, 20), fallback_spawn_center + Vector2(0, 20), col, 2.0)


# --- LOGIC ---

func _get_best_spawn_position() -> Vector2:
	# 1. Try Corruption
	if corruption_layer:
		var used_cells = corruption_layer.get_used_cells()
		if not used_cells.is_empty():
			var random_tile = used_cells.pick_random()
			return corruption_layer.map_to_local(random_tile)
	
	# 2. Fallback to our exported Circle
	var angle = randf() * TAU
	# Spawn exactly ON the line, or inside? 
	# Usually ON the line is better for "Siege" feel.
	return fallback_spawn_center + Vector2(cos(angle), sin(angle)) * fallback_spawn_radius

# --- UNCHANGED LOGIC BELOW ---

func start_next_wave():
	if is_wave_active: return
	
	current_wave += 1
	enemies_to_spawn = round(initial_enemy_count * pow(difficulty_multiplier, current_wave - 1))
	enemies_alive = enemies_to_spawn
	is_wave_active = true
	
	print("Wave %d Started! Incoming: %d enemies" % [current_wave, enemies_to_spawn])
	wave_started.emit(current_wave)
	
	spawn_timer.start()

func _on_spawn_tick():
	if enemies_to_spawn <= 0:
		spawn_timer.stop()
		wave_timer.stop()
		return
		
	var spawn_pos = _get_best_spawn_position()
	_spawn_unit(spawn_pos)
	enemies_to_spawn -= 1

func _spawn_unit(pos: Vector2):
	if not enemy_scene: return
	
	var enemy = enemy_scene.instantiate()
	
	# Safety check for level_ref
	if level_ref:
		level_ref.add_child(enemy)
	else:
		get_parent().add_child(enemy) # Fallback
		
	enemy.global_position = pos
	
	print("spawned enemy")
	
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	if enemy.has_signal("enemy_clicked"): # Fixed signal name
		enemy.enemy_clicked.connect(_on_enemy_clicked)

func _on_enemy_clicked(enemy):
	selected_enemy = enemy
	if enemy_popup:
		enemy_popup.show_info(enemy)

func deselect_enemy():
	if selected_enemy:
		selected_enemy = null
		if enemy_popup:
			enemy_popup.hide_info()

func _on_enemy_died(_enemy_instance):
	enemies_alive -= 1
	if enemies_alive <= 0 and enemies_to_spawn <= 0:
		_wave_complete()

func _wave_complete():
	is_wave_active = false
	print("Wave %d Complete!" % current_wave)
	wave_ended.emit(current_wave)
	wave_timer.start()
