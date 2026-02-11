extends CharacterBody2D
class_name Enemy

# --- CONFIGURATION ---
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

# --- STATE ---
var pathfinder: Pathfinder 
var current_target: Node2D
var current_path: PackedVector2Array = []

# Timers
var path_update_timer: float = 0.0
var find_target_timer: float = 1.0
var attack_cooldown: float = 0.0


signal enemy_clicked(enemy: Enemy) # REPLACES hovered/unhovered


func _ready():
	pathfinder = get_tree().root.find_child("Pathfinder", true, false)
	await get_tree().physics_frame
	_find_target()
	
	# 1. Enable Physics Clicking
	input_pickable = true 
	
	# 2. Connect the built-in click detector
	input_event.connect(_on_input_event)
	
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
		velocity = Vector2.ZERO
		
		# Ranged LOS Check
		if combat_type == 1 and not _has_line_of_sight(current_target):
			_process_movement(delta) # No LOS? Keep moving to find angle
		else:
			_try_attack(current_target)
	else:
		# --- OUT OF RANGE ---
		_process_movement(delta)

# ---------------------------------------------------------
# MOVEMENT LOGIC
# ---------------------------------------------------------

func _process_movement(delta):
	# 1. Update Path periodically
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		_recalculate_path()
		path_update_timer = 0.5

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

	# 3. Execute
	if move_dir != Vector2.ZERO:
		_execute_movement(move_dir)
	else:
		velocity = Vector2.ZERO

func _execute_movement(dir: Vector2):
	velocity = dir * movement_speed
	move_and_slide()
	
	# --- UNIFIED BUMP LOGIC ---
	# Checks for walls regardless of whether we are pathfinding or charging
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			
			# If we bumped the target OR a random wall, attack it
			if collider == current_target or collider.is_in_group("Structure"):
				_try_structure_attack(collider)

# ---------------------------------------------------------
# COMBAT LOGIC
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# HELPERS
# ---------------------------------------------------------

func _get_target_radius(node) -> float:
	if node and node.has_method("get_radius"):
		return node.get_radius()
	return 16.0 # Default fallback (half tile)

func _validate_target(delta) -> bool:
	if is_instance_valid(current_target):
		if current_target is Building and current_target.is_ghost:
			_reset_target()
			return false
		return true
		
	# Search cooldown
	find_target_timer -= delta
	if find_target_timer <= 0.0:
		_find_target()
		find_target_timer = 1.0
	return false

func _reset_target():
	current_target = null
	current_path = []
	_find_target()

func _find_target():
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

# Enemy.gd

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
			
		# Find the closest point to ME
		var closest_point = Vector2.ZERO
		var min_dist = INF
		
		for pt in access_points:
			var d = global_position.distance_squared_to(pt)
			if d < min_dist:
				min_dist = d
				closest_point = pt
		
		# Override the target destination with this specific tile center
		target_pos = closest_point
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
		

func take_damage(damage: int):
	health -= damage
	
	if (health <= 0):
		die()
		
func die():
	print_debug("enemy died")
	queue_free()
	
# --- THE CLICK LOGIC ---
func _on_input_event(_viewport, event, _shape_idx):
	# Check for Left Click
	if event.is_action_pressed("ui_left"): # Or "click"
		print("Enemy Clicked: ", self)
		
		enemy_clicked.emit(self)
		
		# CRITICAL: This stops the event from bubbling up to the Level.
		# This ensures clicking an enemy DOES NOT trigger "Deselect".
		get_viewport().set_input_as_handled()
