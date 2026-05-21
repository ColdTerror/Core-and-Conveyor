# ==============================================================================
# Script: Enemy & Related/test_enemy.gd
# Purpose: Manages individual enemy unit state, including swarm separation, 
#          pathfinding to priority targets/bots, combat/attack execution,
#          taking damage from towers, and state saving/loading.
# Dependencies: Autoload InputManager. Pathfinder node in scene. Group "Enemies".
#               Group "WorkerBots". Group "PriorityTarget".
# Signals:
#   - died(enemy_instance: Enemy): Emitted when health drops to or below zero.
# ==============================================================================
extends CharacterBody2D
class_name Enemy

# --- CONFIGURATION ---
@export var enemy_name: String = "Enemy"
@export_group("Stats")
@export var max_health: int = 50
var health: int = max_health
@export var movement_speed: float = 60.0
@export var damage: int = 10
@export var attack_speed: float = 1.0 

@export_group("Combat")
@export_enum("Melee", "Ranged") var combat_type: int = 0 
@export var attack_range: float = 40.0 
@export var projectile_scene: PackedScene 

# --- NEW: SEPARATION CONFIG ---
@export_subgroup("Swarm Movement")
@export var separation_radius: float = 24.0 # How close before they push
@export var separation_force: float = 30.0  # How hard they push apart

# --- NEW: AGGRO CONFIG ---
@export_subgroup("Aggro Logic")
@export var bot_aggro_radius: float = 100.0 # How close a bot has to be to distract them
@export var bot_leash_radius: float = 250.0 # How far the bot has to run to make them give up

# --- STATE ---
var pathfinder: Pathfinder 
var current_target: Node2D
var current_path: PackedVector2Array = []

# Timers
var path_update_timer: float = 0.0
var find_target_timer: float = .5
var attack_cooldown: float = 0.0


signal died(enemy_instance: Enemy) 

var is_target_locked: bool = false

var separation_update_timer: float = 0.0
var cached_separation: Vector2 = Vector2.ZERO

func _ready():
	pathfinder = get_tree().root.find_child("Pathfinder", true, false)
	await get_tree().physics_frame
	_find_target()
	
	separation_update_timer = randf_range(0.0, 0.1)
	
	# --- Hover Detection for the InputManager ---
	input_pickable = true
	mouse_entered.connect(func():
		InputManager.hovered_enemy = self
	)
	mouse_exited.connect(func():
		if InputManager.hovered_enemy == self: InputManager.hovered_enemy = null
	)
	
func _physics_process(delta):
	if health <= 0: return

	# 1. Timers
	if attack_cooldown > 0: attack_cooldown -= delta

	# 2. Validate Target
	if not _validate_target(delta): return

	# 3. Decision Logic: Attack or Move?
	var dist = global_position.distance_to(current_target.global_position)
	var required_dist = attack_range + _get_target_radius(current_target)

	if dist <= required_dist:
		# --- IN RANGE ---
		# Instead of completely stopping, let them keep pushing each other!
		var separation = _calculate_separation()
		velocity = separation * _get_current_speed()
		move_and_slide()
		
		# Ranged LOS Check
		if combat_type == 1 and not _has_line_of_sight(current_target):
			_process_movement(delta) 
		else:
			_try_attack(current_target)
	else:
		# --- OUT OF RANGE ---
		_process_movement(delta)

# MOVEMENT LOGIC

func _process_movement(delta):
	# 1. Update Path periodically
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		_recalculate_path()
		path_update_timer = 5

	var move_dir = Vector2.ZERO

	# 2. Determine Direction
	if current_path.is_empty():
		# --- FINAL APPROACH (No Path, but close enough to charge) ---
		if is_instance_valid(current_target):
			var dist = global_position.distance_to(current_target.global_position)
			# Buffer ensures we don't stop exactly on the edge and miss the swing
			var approach_limit = _get_target_radius(current_target)
			
			if dist < approach_limit:
				move_dir = global_position.direction_to(current_target.global_position)
	else:
		# --- NORMAL PATHFINDING ---
		var next_point = current_path[0]
		move_dir = global_position.direction_to(next_point)
		
		# Prune waypoint if reached
		if global_position.distance_to(next_point) < 5.0:
			current_path.remove_at(0)

	# 3. Apply Separation Force (Swarm Behavior)
	if move_dir != Vector2.ZERO:
		var separation = _calculate_separation()
		
		# Blend the pathfinding direction with the separation push
		# We normalize it again so they don't move faster when clustered
		var final_dir = (move_dir + separation).normalized()
		
		_execute_movement(final_dir)
	else:
		velocity = Vector2.ZERO

func _calculate_separation() -> Vector2:
	separation_update_timer -= get_physics_process_delta_time()
	if separation_update_timer <= 0.0:
		separation_update_timer = 0.1  # recalculate 10 times per second instead of 60
		cached_separation = _do_separation_calculation()
	return cached_separation
	
func _do_separation_calculation() -> Vector2:
	var separation_vector = Vector2.ZERO
	var neighbors = 0
	
	# Only check against other units in the Enemies group
	var all_enemies = get_tree().get_nodes_in_group("Enemies")
	
	for other in all_enemies:
		if other == self or not is_instance_valid(other): 
			continue
			
		var dist = global_position.distance_to(other.global_position)
		
		if dist < separation_radius and dist > 0.1:
			# Calculate push direction (from them to us)
			var push_dir = other.global_position.direction_to(global_position)
			
			# The closer they are, the stronger the push!
			var push_strength = 1.0 - (dist / separation_radius)
			separation_vector += push_dir * push_strength
			neighbors += 1
			
	if neighbors > 0:
		# Average the push forces and scale by the configured force weight
		separation_vector = (separation_vector / neighbors) * (separation_force / movement_speed)
		
	return separation_vector
	
func _execute_movement(dir: Vector2):
	velocity = dir * _get_current_speed()
	move_and_slide()
	
	# --- UNIFIED BUMP LOGIC  ---
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			
			# Check if the collider itself has the damage script
			var hit_node = collider
			
			# If it doesn't, check if its parent is the main Building node!
			if not hit_node.has_method("take_damage") and hit_node.get_parent() != null:
				if hit_node.get_parent().has_method("take_damage"):
					hit_node = hit_node.get_parent()
			
			# If whatever we hit can take damage, chew through it!
			if hit_node == current_target or hit_node.has_method("take_damage"):
				_try_structure_attack(hit_node)

# COMBAT LOGIC

func _try_attack(target):
	if attack_cooldown > 0.0: return
	
	attack_cooldown = 1.0 / attack_speed
	
	if combat_type == 0: # Melee
		_animate_bump(target.global_position)
		if target.has_method("take_damage"): target.take_damage(damage)
	else: # Ranged
		_spawn_projectile(target)

func _try_structure_attack(structure):
	# Force melee attack logic for breaking walls (even for ranged units)
	if attack_cooldown > 0.0: return
	
	attack_cooldown = 1.0 / attack_speed
	
	_animate_bump(structure.global_position)
	if structure.has_method("take_damage"): structure.take_damage(damage)

func _animate_bump(target_pos: Vector2):
	var tween = create_tween()
	var dir = global_position.direction_to(target_pos)
	tween.tween_property(self, "position", position + (dir * 8.0), 0.1)
	tween.tween_property(self, "position", position, 0.1)

func _spawn_projectile(target):
	if not projectile_scene: return
	var proj = projectile_scene.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position
	if proj.has_method("setup"):
		var dir = global_position.direction_to(target.global_position)
		proj.setup(global_position, dir, 300.0, damage, null)

# HELPERS
func _get_current_speed() -> float:
	var actual_speed = movement_speed
	
	# Ask the pathfinder's terrain layer what we are standing on
	if pathfinder and pathfinder.main_layer:
		var current_grid_pos = pathfinder.main_layer.local_to_map(global_position)
		var tile_data = pathfinder.main_layer.get_cell_tile_data(current_grid_pos)
		
		# If it's water, apply the 40% speed penalty
		if tile_data and tile_data.get_custom_data("is_water"):
			actual_speed = movement_speed * 0.4 
			
	return actual_speed
	
func _get_target_radius(node) -> float:
	if node and node.has_method("get_radius"):
		return node.get_radius()
	return 16.0 # Default fallback (half tile)

func _validate_target(delta) -> bool:
	if is_instance_valid(current_target):
		if current_target is Building and current_target.is_ghost:
			_reset_target()
			return false
			
		# --- THE LEASH LOGIC ---
		if current_target.has_method("set_priority"): 
			if global_position.distance_to(current_target.global_position) > bot_leash_radius:
				is_target_locked = false 
				_reset_target()
				return false
		# ------------------------------
		
		if is_target_locked:
			return true
			
		# --- THE FIX: ACTIVE DISTRACTION RADAR ---
		# Even if we have a valid building target, scan for bots every 0.5s!
		find_target_timer -= delta
		if find_target_timer <= 0.0:
			find_target_timer = 0.5
			
			# Only scan for distractions if we aren't ALREADY chasing a bot!
			if not current_target.has_method("set_priority"):
				_scan_for_nearby_bots()
		# -----------------------------------------
		
		return true
		
	# Search cooldown (when we have no target at all)
	find_target_timer -= delta
	if find_target_timer <= 0.0:
		_reset_target()
		find_target_timer = 0.5
	return false
func _reset_target():
	current_target = null
	current_path = []
	path_update_timer = 0.0
	is_target_locked = false
	_find_target()
	
func _find_target():
	# 1. DISTRACTION CHECK
	if not is_target_locked:
		_scan_for_nearby_bots()
		
		# If the scanner found a bot, stop looking for buildings!
		if current_target != null and current_target.has_method("set_priority"):
			return 

	# 2. GLOBAL RADAR (Look for priority targets/buildings)
	var targets = get_tree().get_nodes_in_group("PriorityTarget")
	var nearest: Node2D = null
	var min_dist = INF
	
	for t in targets:
		if not is_instance_valid(t) or (t is Building and t.is_ghost): continue
		var d = global_position.distance_squared_to(t.global_position)
		if d < min_dist:
			min_dist = d
			nearest = t
			
	current_target = nearest

func _scan_for_nearby_bots():
	var bots = get_tree().get_nodes_in_group("WorkerBots")
	var nearest_bot: Node2D = null
	var min_bot_dist = bot_aggro_radius * bot_aggro_radius 
	
	for b in bots:
		if not is_instance_valid(b) or b.health <= 0: continue
		
		var d = global_position.distance_squared_to(b.global_position)
		if d < min_bot_dist:
			min_bot_dist = d
			nearest_bot = b
			
	if nearest_bot != null:
		# Distraction successful! Switch target and instantly turn!
		current_target = nearest_bot
		_recalculate_path()

func _recalculate_path():
	if not pathfinder or not is_instance_valid(current_target): return
	
	var target_pos = current_target.global_position
	
	# --- NEW: SMART BUILDING TARGETING ---
	# If the target is a building, ask "Where should I stand?"
	if current_target is Building:
		var access_points = current_target.get_access_points(pathfinder)
		
		if access_points.is_empty():
			# Building is completely buried/unreachable
			return 
			
		var best_path = PackedVector2Array()
		var best_cost := INF

		for pt in access_points:
			var path = pathfinder.get_path_route(global_position, pt)
			if path.is_empty():
				continue

			var total_cost := 0.0

			# Convert world positions back to grid coords
			for world_point in path:
				var local = pathfinder.main_layer.to_local(world_point)
				var map_coords = pathfinder.main_layer.local_to_map(local)

				var weight = pathfinder.enemy_astar.get_point_weight_scale(map_coords)
				total_cost += weight

			if best_path.is_empty() or total_cost < best_cost:
				best_cost = total_cost
				best_path = path

		current_path = best_path

		return

	# -------------------------------------

	var new_path = pathfinder.get_path_route(global_position, target_pos)
	
	# Prune start node logic (keeps movement smooth)
	if not new_path.is_empty() and global_position.distance_to(new_path[0]) < 32.0:
		new_path.remove_at(0)

	current_path = new_path

func _has_line_of_sight(target) -> bool:
	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.exclude = [self.get_rid(), target.get_rid()]
	var res = space.intersect_ray(query)
	if res and (res.collider.is_in_group("Structure") or res.collider is TileMapLayer):
		return false
	return true
	
func _process(_delta):
	queue_redraw()

func _draw():
	if current_path.size() > 0:
		var local_points = PackedVector2Array()
		local_points.append(Vector2.ZERO)
		for point in current_path:
			local_points.append(to_local(point))
		draw_polyline(local_points, Color.CYAN, 2.0)
		

func take_damage(damage: int, source: Node2D = null): # <--- Added 'source'
	health -= damage
	
	if health <= 0:
		die()
		return # Stop processing if dead
		
	# --- NEW: REVENGE AGGRO LOGIC ---
	# If we got shot by a building, and we aren't already locked onto a defender
	if source and not is_target_locked:
		current_target = source
		is_target_locked = true
		
		# Force the enemy to instantly turn around and attack the tower!
		_recalculate_path() 
	# --------------------------------
		
func die():
	print_debug("enemy died")
	died.emit(self)
	queue_free()
	
		
# SAVE / LOAD SYSTEM
func get_save_data() -> Dictionary:
	return {
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"health": health,
		"max_health": max_health,
		"scale_x": scale.x,
		"scale_y": scale.y,
		"modulate": modulate.to_html() # Save the purple color as a string!
	}

func load_save_data(data: Dictionary):
	# Snap to the exact saved position
	global_position = Vector2(data.get("pos_x", 0), data.get("pos_y", 0))
	
	# Restore stats
	max_health = data.get("max_health", max_health)
	health = data.get("health", max_health)
	
	# Restore Elite visuals
	scale = Vector2(data.get("scale_x", 1.0), data.get("scale_y", 1.0))
	if data.has("modulate"):
		modulate = Color(data["modulate"])
