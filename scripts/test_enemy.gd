extends CharacterBody2D

@export var movement_speed: float = 60.0
@export var health: int = 50

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# The target node (The Town Center)
var current_target: Node2D = null

func _ready():
	# Wait one frame for the map to initialize
	await get_tree().physics_frame
	_find_target()

func _physics_process(delta):
	if health <= 0: return

	# 1. Check if we need a target
	if not is_instance_valid(current_target):
		_find_target()
		return
		
	# 2. Set the target position for the pathfinder
	nav_agent.target_position = current_target.global_position
	
	# 3. Get the next step
	if nav_agent.is_navigation_finished():
		# We reached the base! Attack logic goes here later.
		return
		
	var current_agent_position = global_position
	var next_path_position = nav_agent.get_next_path_position()
	
	# 4. Move
	var new_velocity = current_agent_position.direction_to(next_path_position) * movement_speed
	
	# Setup simple collision avoidance (optional)
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(new_velocity)
	else:
		velocity = new_velocity
		move_and_slide()

# This function is called by the agent if Avoidance is ON
func _on_navigation_agent_2d_velocity_computed(safe_velocity):
	velocity = safe_velocity
	move_and_slide()

func _find_target():
	var targets = get_tree().get_nodes_in_group("PriorityTarget")
	
	var nearest_target: Node2D = null
	var min_dist: float = INF # Start with "Infinity" so the first valid target is always closer
	
	for t in targets:
		# 1. Validation Check
		if not is_instance_valid(t): continue
		if t is Building and t.is_ghost: continue
		
		# 2. Distance Check
		# We use distance_squared_to because it's faster (avoids square roots)
		var dist = global_position.distance_squared_to(t.global_position)
		
		if dist < min_dist:
			min_dist = dist
			nearest_target = t
	
	current_target = nearest_target

# --- COMBAT (Existing) ---
func take_damage(amount: int):
	health -= amount
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	if health <= 0: die()

func die():
	queue_free()
