# ==============================================================================
# Script: Enemy & Related/base_enemy.gd
# Purpose: Manages individual enemy unit state, including swarm separation, 
#          pathfinding to priority targets/bots, combat/attack execution,
#          taking damage from towers, and state saving/loading.
# Dependencies: Autoload InputManager. Pathfinder node in scene. Group "Enemies".
#               Group "Bots". Group "PriorityTarget".
# Signals:
#   - died(enemy_instance: Enemy): Emitted when health drops to or below zero.
# ==============================================================================
extends CharacterBody2D
class_name Enemy

# --- CONFIGURATION ---
@export var enemy_name: String = "Enemy"
@export_group("Stats")
@export var max_health: int = 50
var health: int
@export var movement_speed: float = 60.0
@export var damage: int = 10
@export var attack_speed: float = 1.0 

@export_group("Combat")
@export_enum("Melee", "Ranged") var combat_type: int = 0 
@export var attack_range: float = 40.0 
@export var projectile_scene: PackedScene 
@export var is_flying: bool = false
@export var damage_multipliers: Dictionary = {
	"Piercing": 1.0,
	"Crushing": 1.0
}

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
var _flight_time: float = 0.0
var _sprite_original_scale: Vector2 = Vector2(0.25, 0.25)


signal died(enemy_instance: Enemy) 

var is_target_locked: bool = false
var is_selected: bool = false

var separation_update_timer: float = 0.0
var cached_separation: Vector2 = Vector2.ZERO

## Initializes pathfinder references, sets up mouse hover connections, and schedules initial target scan.
func _ready():
	health = max_health
	pathfinder = get_tree().root.find_child("Pathfinder", true, false)
	await get_tree().physics_frame
	_find_target()
	
	separation_update_timer = randf_range(0.0, 0.1)
	_flight_time = randf_range(0.0, 10.0)
	
	if has_node("Sprite2D"):
		_sprite_original_scale = $Sprite2D.scale
	
	# Hover Detection for the InputManager
	input_pickable = true
	mouse_entered.connect(func():
		InputManager.hovered_enemy = self
	)
	mouse_exited.connect(func():
		if InputManager.hovered_enemy == self: InputManager.hovered_enemy = null
	)



## Handles standard frame-by-frame combat checks, attack cooldown updates, and movement orchestration.
func _physics_process(delta):
	if health <= 0: return

	# Flying Bobble Animation
	if is_flying and has_node("Sprite2D"):
		_flight_time += delta
		var base_float_y = -8.0
		var bobble_y = sin(_flight_time * 5.0) * 3.0
		$Sprite2D.position.y = base_float_y + bobble_y

	# Timers
	if attack_cooldown > 0: attack_cooldown -= delta

	# Validate Target
	if not _validate_target(delta): return

	# Decision Logic: Attack or Move?
	var dist = global_position.distance_to(current_target.global_position)
	var required_dist = attack_range + _get_target_radius(current_target)

	if dist <= required_dist:
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
		_process_movement(delta)



## Determines the navigation vector from A* paths or target proximity and drives steering.
func _process_movement(delta):
	# Update Path periodically
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		_recalculate_path()
		path_update_timer = 5

	var move_dir = Vector2.ZERO

	# Determine Direction
	if current_path.is_empty():
		# Final approach (no path, close enough to charge)
		if is_instance_valid(current_target):
			var dist = global_position.distance_to(current_target.global_position)
			# Buffer ensures we don't stop exactly on the edge and miss the swing
			var approach_limit = _get_target_radius(current_target)
			
			if dist < approach_limit:
				move_dir = global_position.direction_to(current_target.global_position)
	else:
		# Normal pathfinding
		var next_point = current_path[0]
		move_dir = global_position.direction_to(next_point)
		
		# Prune waypoint if reached
		if global_position.distance_to(next_point) < 5.0:
			current_path.remove_at(0)

	# Apply Separation Force (Swarm Behavior)
	if move_dir != Vector2.ZERO:
		var separation = _calculate_separation()
		
		# Blend the pathfinding direction with the separation push
		# We normalize it again so they don't move faster when clustered
		var final_dir = (move_dir + separation).normalized()
		
		_execute_movement(final_dir)
	else:
		velocity = Vector2.ZERO



## Manages a throttled rate for updating the swarm separation vector.
func _calculate_separation() -> Vector2:
	separation_update_timer -= get_physics_process_delta_time()
	if separation_update_timer <= 0.0:
		separation_update_timer = 0.1  # recalculate 10 times per second instead of 60
		cached_separation = _do_separation_calculation()
	return cached_separation


## Performs neighbor distance checks and averages repulsion vectors to keep enemies clustered but not overlapping.
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



## Slides the character along velocity and resolves obstacles/buildings impact checks.
func _execute_movement(dir: Vector2):
	velocity = dir * _get_current_speed()
	move_and_slide()
	
	# Unified bump logic
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



## Attempts a melee bump or ranged projectile attack based on unit type and cooldown availability.
func _try_attack(target):
	if attack_cooldown > 0.0: return
	
	attack_cooldown = 1.0 / attack_speed
	
	if combat_type == 0: # Melee
		_animate_bump(target.global_position)
		_animate_squash()
		if target.has_method("take_damage"): target.take_damage(damage)
	else: # Ranged
		_spawn_projectile(target)
		_animate_squash()



## Forces a physical melee attack to chip away at obstructing wall obstacles.
func _try_structure_attack(structure):
	# Force melee attack logic for breaking walls (even for ranged units)
	if attack_cooldown > 0.0: return
	
	attack_cooldown = 1.0 / attack_speed
	
	_animate_bump(structure.global_position)
	_animate_squash()
	if structure.has_method("take_damage"): structure.take_damage(damage)



## Tweens the sprite towards the target point and back to visually represent physical impacts.
func _animate_bump(target_pos: Vector2):
	var tween = create_tween()
	var dir = global_position.direction_to(target_pos)
	tween.tween_property(self, "position", position + (dir * 8.0), 0.1)
	tween.tween_property(self, "position", position, 0.1)



## Applies a quick squash-and-stretch juice tween to the sprite during attacks.
func _animate_squash():
	if has_node("Sprite2D"):
		var sprite = $Sprite2D
		var tween = create_tween()
		tween.tween_property(sprite, "scale", _sprite_original_scale * Vector2(1.2, 0.8), 0.05)
		tween.tween_property(sprite, "scale", _sprite_original_scale, 0.15)



## Spawns a target-seeking projectile at current coordinates if unit is a ranged type.
func _spawn_projectile(target):
	if not projectile_scene: return
	var proj = projectile_scene.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position
	if proj.has_method("setup"):
		var dir = global_position.direction_to(target.global_position)
		proj.setup(global_position, dir, 300.0, damage, null)



## Returns movement speed scaled down if character is currently navigating water cells.
func _get_current_speed() -> float:
	var actual_speed = movement_speed
	
	# Ask the pathfinder's terrain layer what we are standing on
	if pathfinder and pathfinder.main_layer:
		var current_grid_pos = pathfinder.main_layer.local_to_map(global_position)
		var tile_data = pathfinder.main_layer.get_cell_tile_data(current_grid_pos)
		
		# If it's water and we aren't flying, apply the 40% speed penalty
		if not is_flying and tile_data and tile_data.get_custom_data("is_water"):
			actual_speed = movement_speed * 0.4 
			
	return actual_speed



## Queries target size to prevent exact-point overlaps during proximity approaches.
func _get_target_radius(node) -> float:
	if node and node.has_method("get_radius"):
		return node.get_radius()
	return 16.0 # Default fallback (half tile)



## Evaluates if current target is valid, alive, and within leash distances.
func _validate_target(delta) -> bool:
	if is_instance_valid(current_target):
		if current_target is Building and current_target.is_ghost:
			_reset_target()
			return false
			
		# Leash logic
		if current_target.has_method("set_priority"): 
			if global_position.distance_to(current_target.global_position) > bot_leash_radius:
				is_target_locked = false 
				_reset_target()
				return false
		
		if is_target_locked:
			return true
			
		# Active distraction radar: Even if we have a valid building target, scan for bots every 0.5s!
		find_target_timer -= delta
		if find_target_timer <= 0.0:
			find_target_timer = 0.5
			
			# Only scan for distractions if we aren't ALREADY chasing a bot!
			if not current_target.has_method("set_priority"):
				_scan_for_nearby_bots()
		
		return true
		
	# Search cooldown (when we have no target at all)
	find_target_timer -= delta
	if find_target_timer <= 0.0:
		_reset_target()
		find_target_timer = 0.5
	return false



## Wipes target state and instantly triggers a fresh navigation radar scan.
func _reset_target():
	current_target = null
	current_path = []
	path_update_timer = 0.0
	is_target_locked = false
	_find_target()



## Runs a global radar search to find and lock the nearest priority building target.
func _find_target():
	# DISTRACTION CHECK
	if not is_target_locked:
		_scan_for_nearby_bots()
		
		# If the scanner found a bot, stop looking for buildings!
		if current_target != null and current_target.has_method("set_priority"):
			return 

	# Global radar (look for priority targets/buildings) with 8 tiles of perception noise
	var targets = get_tree().get_nodes_in_group("PriorityTarget")
	var nearest: Node2D = null
	var min_dist = INF
	
	for t in targets:
		if not is_instance_valid(t) or (t is Building and t.is_ghost): continue
		
		# Add up to 8 tiles (256 pixels) of random noise to distribute aggro
		var real_dist = global_position.distance_to(t.global_position)
		var noise = randf_range(-256.0, 256.0) 
		var perceived_dist = max(0.0, real_dist + noise)
		var d = perceived_dist * perceived_dist
		
		if d < min_dist:
			min_dist = d
			nearest = t
			
	current_target = nearest



## Scans nearby vicinity for worker bots to distract enemy aggro.
func _scan_for_nearby_bots():
	var bots = get_tree().get_nodes_in_group("Bots")
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



## Requests a fresh path route to current target from global pathfinding systems.
func _recalculate_path():
	if not pathfinder or not is_instance_valid(current_target): return
	
	var target_pos = current_target.global_position
	
	# Smart building targeting
	if current_target is Building:
		var access_points = current_target.get_access_points(pathfinder)
		
		if access_points.is_empty():
			# Building is completely buried/unreachable
			return 
			
		var best_path = PackedVector2Array()
		var best_cost := INF
 
		for pt in access_points:
			var path = pathfinder.get_path_route(global_position, pt, false, is_flying)
			if path.is_empty():
				continue
 
			var total_cost := 0.0
 
			# Convert world positions back to grid coords
			for world_point in path:
				var local = pathfinder.main_layer.to_local(world_point)
				var map_coords = pathfinder.main_layer.local_to_map(local)
 
				var active_astar = pathfinder.flying_astar if is_flying else pathfinder.enemy_astar
				var weight = active_astar.get_point_weight_scale(map_coords)
				total_cost += weight
 
			if best_path.is_empty() or total_cost < best_cost:
				best_cost = total_cost
				best_path = path
 
		current_path = best_path
 
		return
 
	var new_path = pathfinder.get_path_route(global_position, target_pos, false, is_flying)
	
	# Prune start node logic (keeps movement smooth)
	if not new_path.is_empty() and global_position.distance_to(new_path[0]) < 32.0:
		new_path.remove_at(0)
 
	current_path = new_path



## Performs a raycast check to ensure no structural blockades sit between enemy and target.
func _has_line_of_sight(target) -> bool:
	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	
	var exclude_rids = [self.get_rid()]
	if target.has_method("get_rid"):
		exclude_rids.append(target.get_rid())
		
	if target.has_node("AutoCollisionBody"):
		var body = target.get_node("AutoCollisionBody")
		if body.has_method("get_rid"):
			exclude_rids.append(body.get_rid())
			
	query.exclude = exclude_rids
	var res = space.intersect_ray(query)
	
	if res:
		var collider = res.collider
		if collider == target or collider.get_parent() == target:
			return true
			
		var is_struct = collider.is_in_group("Structure") or (collider.get_parent() and collider.get_parent().is_in_group("Structure"))
		if is_struct or collider is TileMapLayer:
			return false
			
	return true



## Redraws debug paths if active at runtime.
func _process(_delta):
	queue_redraw()



## Draws polyline overlay of the current path and selected ranged attack threat ring.
func _draw():
	if is_selected and combat_type == 1:
		var circle_color = Color(1.0, 0.2, 0.2, 0.4) # Subtle red threat ring
		var border_width = 1.5
		draw_arc(Vector2.ZERO, attack_range, 0.0, TAU, 64, circle_color, border_width, true)
		
	if current_path.size() > 0:
		var local_points = PackedVector2Array()
		local_points.append(Vector2.ZERO)
		for point in current_path:
			local_points.append(to_local(point))
		draw_polyline(local_points, Color.CYAN, 2.0)



## Subtracts health points, handles death triggers, and switches target aggro to damage source.
func take_damage(damage: int, source: Node2D = null, damage_type: String = "None"):
	var multiplier := 1.0
	if damage_type != "None" and damage_multipliers.has(damage_type):
		multiplier = damage_multipliers[damage_type]
	var final_damage := roundi(damage * multiplier)
	health -= final_damage
	
	if health <= 0:
		die()
		return # Stop processing if dead
		
	# Revenge aggro logic: If we got shot by a building, and we aren't already locked onto a defender
	if source and not is_target_locked:
		current_target = source
		is_target_locked = true
		
		# Force the enemy to instantly turn around and attack the tower!
		_recalculate_path() 



## Notifies listeners of unit death and schedules node deletion.
func die():
	print_debug("enemy died")
	died.emit(self)
	queue_free()



## Serializes position, modular colors, scale sizes, and health trackers into a dictionary.
func get_save_data() -> Dictionary:
	return {
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"health": health,
		"max_health": max_health,
		"scale_x": scale.x,
		"scale_y": scale.y,
		"modulate": modulate.to_html(), # Save the purple color as a string!
		"is_flying": is_flying,
		"scene_file_path": scene_file_path
	}



## Restores enemy stats, positions, and elite color overlays from dictionary.
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
		
	is_flying = data.get("is_flying", is_flying)
