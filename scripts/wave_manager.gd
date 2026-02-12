extends Node2D
class_name WaveManager

# --- REFERENCES ---
@export var level_ref: Node2D
@export var corruption_layer: TileMapLayer # Drag your new layer here!
@export var enemy_scene: PackedScene

# --- WAVE SETTINGS ---
@export var time_between_waves: float = 20.0
@export var initial_enemy_count: int = 4
@export var difficulty_multiplier: float = 1.2 # +20% enemies per wave

# --- STATE ---
var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_alive: int = 0
var is_wave_active: bool = false
var spawn_timer: Timer

signal wave_started(wave_num: int)
signal wave_ended(wave_num: int)

func _ready():
	spawn_timer = Timer.new()
	spawn_timer.wait_time = 1.5 # Time between individual enemy spawns
	spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(spawn_timer)

# --- PUBLIC API ---
func start_next_wave():
	if is_wave_active: return
	
	current_wave += 1
	
	# Calculate count: Wave 1 = 4, Wave 2 = 5, Wave 3 = 6...
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
		return
		
	# 1. Spawn the enemy
	var spawn_pos = _get_best_spawn_position()
	_spawn_unit(spawn_pos)
	
	# 2. Decrement
	enemies_to_spawn -= 1

func _get_best_spawn_position() -> Vector2:
	# STRATEGY A: Corruption Tiles (The "Rise to Ruins" style)
	var used_cells = corruption_layer.get_used_cells()
	
	if not used_cells.is_empty():
		# Future Upgrade: Pick the tile closest to the player base
		# For now: Just pick a random corruption tile
		var random_tile = used_cells.pick_random()
		return corruption_layer.map_to_local(random_tile)
	
	# STRATEGY B: Map Edge Fallback (Classic TD style)
	# If no corruption exists, spawn at a random edge of the map (approx 50x50 size)
	var center = Vector2(800, 600) # Replace with your actual map center
	var angle = randf() * TAU
	var distance = 800.0 # Far enough away
	return center + Vector2(cos(angle), sin(angle)) * distance

func _spawn_unit(pos: Vector2):
	if not enemy_scene: return
	
	var enemy = enemy_scene.instantiate()
	level_ref.add_child(enemy) # Add to Level so it sorts correctly
	enemy.global_position = pos
	
	# Connect death signal to track wave progress
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)

# --- WAVE TRACKING ---
func _on_enemy_died(_enemy_instance):
	enemies_alive -= 1
	
	if enemies_alive <= 0 and enemies_to_spawn <= 0:
		_wave_complete()

func _wave_complete():
	is_wave_active = false
	print("Wave %d Complete!" % current_wave)
	wave_ended.emit(current_wave)
	
	# Optional: Auto-start next wave after delay?
	# await get_tree().create_timer(time_between_waves).timeout
	# start_next_wave()
