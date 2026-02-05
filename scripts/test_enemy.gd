extends CharacterBody2D

@export var movement_speed: float = 60.0
@export var health: int = 50
@export var attack_range: float = 40.0 # Distance to stop and attack

# References
var pathfinder: Pathfinder 
var current_target: Node2D

# Pathfinding State
var current_path: PackedVector2Array = []
var path_update_timer: float = 0

var find_target_timer: float = 1

func _ready():
	# 1. FIND THE PATHFINDER
	# We search the scene tree for the "Pathfinder" node we created earlier.
	# "true, false" means recursive search, but don't look inside owner-less nodes.
	pathfinder = get_tree().root.find_child("Pathfinder", true, false)
	
	# Wait a frame to let the map generate before looking for targets
	await get_tree().physics_frame
	_find_target()

func _physics_process(delta):
	if health <= 0: return

	# --- 1. TARGET CHECK ---
	# Ensure target is still valid (not deleted, not a ghost)
	if is_instance_valid(current_target):
		if current_target is Building and current_target.is_ghost:
			current_target = null
			current_path = []
			_find_target()
			return
	else:
		find_target_timer -= delta
		if (find_target_timer <= 0.0):
			_find_target()
			find_target_timer = 1
		return # Wait for next frame to find one

	# --- 2. ATTACK CHECK ---
	# Are we close enough to hit the building?
	var dist_to_target = global_position.distance_to(current_target.global_position)
	
	# If targeting a building, we subtract its radius so we stop AT the wall, not inside it
	var stop_distance = attack_range
	if current_target.has_method("get_radius"):
		stop_distance += current_target.get_radius()

	if dist_to_target <= stop_distance:
		# We arrived! Stop and Attack.
		velocity = Vector2.ZERO
		# _perform_attack() # Uncomment when you have attack logic
		return

	# --- 3. PATH UPDATE (Throttled) ---
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		_recalculate_path()
		path_update_timer = 1 # Update 1 times a second

	# --- 4. MOVEMENT ---
	if current_path.is_empty():
		velocity = Vector2.ZERO
		return

	# The path is a list of points. Index 0 is the next tile center we need to hit.
	var next_point = current_path[0]
	var dir = global_position.direction_to(next_point)
	
	velocity = dir * movement_speed
	move_and_slide()
	
	# Check if we reached the waypoint (within 4 pixels)
	if global_position.distance_to(next_point) < 4.0:
		current_path.remove_at(0) # Done with this tile, look at the next one

# --- HELPERS ---

func _recalculate_path():
	if not pathfinder or not is_instance_valid(current_target):
		return
		
	# 1. Print the ACTUAL target location
	print("--- PATH REQUEST ---")
	print("Target Real Position: ", current_target.global_position)
	
	# 2. Ask for the path
	current_path = pathfinder.get_path_route(global_position, current_target.global_position)
	
	# 3. Print where the path actually ends
	if current_path.size() > 0:
		var final_point = current_path[current_path.size() - 1]
		print("Path Final Point: ", final_point)
		
	else:
		print("Path is Empty.")

func _find_target():
	var targets = get_tree().get_nodes_in_group("PriorityTarget")
	var nearest_target: Node2D = null
	var min_dist: float = INF 
	
	for t in targets:
		if not is_instance_valid(t): continue
		
		# Ignore Ghosts
		if t is Building and t.is_ghost: continue
		
		# Ignore things at (0,0) just to be safe
		if t.global_position.length_squared() < 10.0: continue
		
		var dist = global_position.distance_squared_to(t.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest_target = t
			
	current_target = nearest_target
	if current_target:
		print("Enemy: Locked onto ", current_target.name, " at ", current_target.global_position)
	else:
		print("Enemy: No targets found!")

# --- DEBUG DRAWING (Optional) ---
func _process(_delta):
	queue_redraw() # Update line every frame

func _draw():
	if current_path.size() > 0:
		# Draw the path lines relative to the enemy position
		var local_points = PackedVector2Array()
		local_points.append(Vector2.ZERO) # Start at enemy center
		
		for point in current_path:
			local_points.append(to_local(point))
			
		draw_polyline(local_points, Color.CYAN, 2.0)
		draw_circle(local_points[1] if local_points.size() > 1 else Vector2.ZERO, 3.0, Color.GREEN)
		
		# Draw a Red X at the final destination
		var end_point = to_local(current_path[current_path.size() - 1])
		draw_line(end_point - Vector2(5,5), end_point + Vector2(5,5), Color.RED, 2.0)
		draw_line(end_point - Vector2(5,-5), end_point + Vector2(5,-5), Color.RED, 2.0)
