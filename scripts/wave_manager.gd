extends Node2D
class_name WaveManager

# --- REFERENCES ---
@export var level_ref: Node2D
@export var corruption_layer: TileMapLayer 
@export var enemy_scene: PackedScene

# --- NEW: SELECTION LOGIC ---
@export var enemy_popup: Control # Drag CanvasLayer/Popup_Layer/EnemyPopup here!
var selected_enemy: Enemy = null
# ----------------------------

# --- WAVE SETTINGS ---
@export var time_between_waves: float = 20.0
@export var initial_enemy_count: int = 4
@export var difficulty_multiplier: float = 1.2 

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
	spawn_timer = Timer.new()
	spawn_timer.wait_time = 1.5 
	spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(spawn_timer)
	
	wave_timer = Timer.new()
	wave_timer.wait_time = time_between_waves
	wave_timer.timeout.connect(start_next_wave)
	add_child(wave_timer)
	
	wave_timer.start()

# --- PUBLIC API ---
func start_next_wave():
	print_debug("starting next wave")
	if is_wave_active: return
	
	current_wave += 1
	enemies_to_spawn = round(initial_enemy_count * pow(difficulty_multiplier, current_wave - 1))
	enemies_alive = enemies_to_spawn
	is_wave_active = true
	
	print("Wave %d Started! Incoming: %d enemies" % [current_wave, enemies_to_spawn])
	wave_started.emit(current_wave)
	
	spawn_timer.start()

# --- SPAWNING LOGIC ---
func _on_spawn_tick():
	if enemies_to_spawn <= 0:
		spawn_timer.stop()
		wave_timer.stop() # Wait for completion before starting timer again
		return
		
	var spawn_pos = _get_best_spawn_position()
	_spawn_unit(spawn_pos)
	enemies_to_spawn -= 1

func _get_best_spawn_position() -> Vector2:
	var used_cells = corruption_layer.get_used_cells()
	
	if not used_cells.is_empty():
		var random_tile = used_cells.pick_random()
		return corruption_layer.map_to_local(random_tile)
	
	var center = Vector2(1600,1600) 
	var angle = randf() * TAU
	var distance = 100.0 
	return center + Vector2(cos(angle), sin(angle)) * distance

func _spawn_unit(pos: Vector2):
	if not enemy_scene: return
	
	var enemy = enemy_scene.instantiate()
	level_ref.add_child(enemy) 
	enemy.global_position = pos
	
	# Connect death signal
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
		
	# Connect click signal
	if enemy.has_signal("enemy_clicked"):
		enemy.enemy_clicked.connect(_on_enemy_clicked)


# ==========================================
# ENEMY SELECTION LOGIC

# ==========================================

func _on_enemy_clicked(enemy):
	selected_enemy = enemy
	if enemy_popup:
		enemy_popup.show_info(enemy)

# Called by Level.gd when the player clicks the ground
func deselect_enemy():
	if selected_enemy:
		selected_enemy = null
		if enemy_popup:
			enemy_popup.hide_info()

# ==========================================


# --- WAVE TRACKING ---
func _on_enemy_died(_enemy_instance):
	enemies_alive -= 1
	
	if enemies_alive <= 0 and enemies_to_spawn <= 0:
		_wave_complete()

func _wave_complete():
	is_wave_active = false
	print("Wave %d Complete!" % current_wave)
	wave_ended.emit(current_wave)
	
	# Restart the waiting timer for the next wave
	wave_timer.start()
