extends CharacterBody2D
class_name Enemy

# --- STATS ---
@export_group("Stats")
@export var health: int = 50
@export var movement_speed: float = 60.0
@export var damage: int = 10
@export var attack_speed: float = 1.0 # Attacks per second

# --- COMBAT CONFIG ---
@export_group("Combat Type")
@export_enum("Melee", "Ranged") var combat_type: int = 0 
@export var attack_range: float = 40.0 # Melee = ~40, Ranged = ~200
@export var projectile_scene: PackedScene # ASSIGN THIS for Ranged units!

# References
var pathfinder: Pathfinder 
var current_target: Node2D

# State
var current_path: PackedVector2Array = []
var path_update_timer: float = 0.0
var find_target_timer: float = 1.0
var attack_cooldown: float = 0.0

func _ready():
	# 1. FIND THE PATHFINDER
	pathfinder = get_tree().root.find_child("Pathfinder", true, false)
	
	# Wait a frame to let the map generate before looking for targets
	await get_tree().physics_frame
	_find_target()

func _physics_process(delta):
	if health <= 0: return

	# 1. Cooldown Management
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# 2. Target Validation
	if not _validate_target(delta):
		return

	# 3. RANGE CHECK (Attack or Move?)
	var dist_to_target = global_position.distance_to(current_target.global_position)
	
	# Calculate stopping distance (Range + Target Size)
	var stop_distance = attack_range
	if current_target.has_method("get_radius"):
		stop_distance += current_target.get_radius()

	if dist_to_target <= stop_distance:
		# --- IN RANGE ---
		velocity = Vector2.ZERO
		
		# If Ranged: Check Line of Sight (Optional, prevents shooting through walls)
		if combat_type == 1: # Ranged
			if _has_line_of_sight(current_target):
				_perform_attack(current_target)
			else:
				# No LOS? Keep moving to get a better angle (or break the wall)
				_move_along_path(delta)
		else:
			# Melee: Just attack
			_perform_attack(current_target)
			
	else:
		# --- OUT OF RANGE ---
		_move_along_path(delta)

# --- MOVEMENT LOGIC ---
func _move_along_path(delta):
	# 1. Update Path (Throttled)
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		_recalculate_path()
		path_update_timer = 0.5 # Update 2 times a second

	# --- THE FIX: FINAL APPROACH ---
	# If path is empty, but we have a target, move straight towards it!
	if current_path.is_empty():
		if is_instance_valid(current_target):
			var dir = global_position.direction_to(current_target.global_position)
			velocity = dir * movement_speed
			move_and_slide()
			
			# Check for the bump
			if get_slide_collision_count() > 0:
				for i in get_slide_collision_count():
					var collider = get_slide_collision(i).get_collider()
					if collider == current_target or collider.is_in_group("Structure"):
						_perform_structure_attack(collider)
		else:
			velocity = Vector2.ZERO
		return
	# -------------------------------

	# 2. Move towards next point
	var next_point = current_path[0]
	var dir = global_position.direction_to(next_point)
	
	velocity = dir * movement_speed
	move_and_slide()
	
	# 3. WALL BREAKER LOGIC (The "Bump")
	# If we hit a wall while moving, attack it!
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			
			# Check if it's a building/wall (Ensure Walls are in group "Structure" or "Building")
			if collider.is_in_group("Structure") or collider is Building:
				_perform_structure_attack(collider)

	# 4. Waypoint Cleanup (Prune point if close)
	if global_position.distance_to(next_point) < 5.0:
		current_path.remove_at(0)

# --- COMBAT LOGIC ---

func _perform_attack(target):
	if attack_cooldown > 0.0: return
	
	# Reset Timer
	attack_cooldown = 1.0 / attack_speed
	
	if combat_type == 0:
		_attack_melee(target)
	else:
		_attack_ranged(target)

func _perform_structure_attack(structure):
	# Only attack walls if we can melee (or if you want ranged units to bash walls too)
	if attack_cooldown > 0.0: return
	
	attack_cooldown = 1.0 / attack_speed
	_attack_melee(structure) # Always use melee animation for wall bashing

func _attack_melee(target):
	# Visual "Bump" Animation
	var tween = create_tween()
	var dir = global_position.direction_to(target.global_position)
	var bump_pos = position + (dir * 8.0)
	
	tween.tween_property(self, "position", bump_pos, 0.1)
	tween.tween_property(self, "position", position, 0.1)
	
	# Deal Damage
	if target.has_method("take_damage"):
		target.take_damage(damage)

func _attack_ranged(target):
	if not projectile_scene:
		print("Error: Ranged Enemy missing Projectile Scene!")
		return
		
	var proj = projectile_scene.instantiate()
	# Add to main scene (not as child of enemy)
	get_parent().add_child(proj) 
	proj.global_position = global_position
	
	# Configure Projectile
	# Assumes Projectile.gd has 'setup(start_pos, dir, speed, damage, texture)'
	if proj.has_method("setup"):
		var dir = global_position.direction_to(target.global_position)
		proj.setup(global_position, dir, 300.0, damage, null)

# --- HELPER FUNCTIONS ---

func _validate_target(delta) -> bool:
	if is_instance_valid(current_target):
		if current_target is Building and current_target.is_ghost:
			current_target = null
			current_path = []
			_find_target()
			return false
		return true
	else:
		find_target_timer -= delta
		if (find_target_timer <= 0.0):
			_find_target()
			find_target_timer = 1.0
		return false

func _recalculate_path():
	if not pathfinder or not is_instance_valid(current_target):
		return
		
	var new_path = pathfinder.get_path_route(global_position, current_target.global_position)
	
	# Prune start node if we are already close to it
	if not new_path.is_empty():
		if global_position.distance_to(new_path[0]) < 32.0:
			new_path.remove_at(0)

	current_path = new_path

func _find_target():
	var targets = get_tree().get_nodes_in_group("PriorityTarget") # Ensure Stockpile is in this group!
	var nearest_target: Node2D = null
	var min_dist: float = INF 
	
	for t in targets:
		if not is_instance_valid(t): continue
		if t is Building and t.is_ghost: continue
		if t.global_position.length_squared() < 10.0: continue
		
		var dist = global_position.distance_squared_to(t.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest_target = t
			
	current_target = nearest_target
	if current_target:
		# print("Enemy: Locked onto ", current_target.name)
		pass

func _has_line_of_sight(target) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.exclude = [self.get_rid(), target.get_rid()]
	var result = space_state.intersect_ray(query)
	
	if result:
		# If we hit a wall, return false (no LOS)
		if result.collider.is_in_group("Structure") or result.collider is TileMapLayer:
			return false
	return true

# --- DEBUG DRAWING ---
func _process(_delta):
	queue_redraw()

func _draw():
	if current_path.size() > 0:
		var local_points = PackedVector2Array()
		local_points.append(Vector2.ZERO)
		for point in current_path:
			local_points.append(to_local(point))
		draw_polyline(local_points, Color.CYAN, 2.0)
