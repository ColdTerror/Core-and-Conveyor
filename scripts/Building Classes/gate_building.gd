extends Building
class_name GateBuilding

var bots_in_gate: int = 0
var is_open: bool = false
var detection_area: Area2D


var level_ref: Node2D

func setup(level_instance: Node2D):
	level_ref = level_instance
	
func _ready():
	super()
	is_solid_obstacle = false 
	path_cost = float(health)
	
	# 1. Create a "Motion Sensor" aura for bots!
	detection_area = Area2D.new()
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 48.0 # Opens when a bot is 1.5 tiles away
	shape.shape = circle
	detection_area.add_child(shape)
	add_child(detection_area)
	
	# Listen for bodies entering the aura
	detection_area.area_entered.connect(_on_bot_entered)
	detection_area.area_exited.connect(_on_bot_exited)

# ==========================================
# DYNAMIC OPEN / CLOSE LOGIC
# ==========================================

func _on_bot_entered(area: Area2D):
	# WorkerBots have an Area2D for clicking. We detect that!
	if area.get_parent() is WorkerBot:
		bots_in_gate += 1
		if bots_in_gate > 0 and not is_open:
			_set_gate_open(true)

func _on_bot_exited(area: Area2D):
	if area.get_parent() is WorkerBot:
		bots_in_gate -= 1
		if bots_in_gate <= 0 and is_open:
			_set_gate_open(false)

func _set_gate_open(open: bool):
	is_open = open
	
	# 1. Drop the physical barrier so enemies/items/bots can phase through
	if has_node("AutoCollisionBody"):
		var static_body = $AutoCollisionBody
		static_body.collision_layer = 0 if open else 1
		static_body.collision_mask = 0 if open else 1
		
	# 2. Tell the Enemy Pathfinder that the door is open!
	if level_ref and level_ref.building_manager:
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_gate_obstacle(tile, path_cost, is_open)
			
	# 3. Visual Feedback (Fade out slightly so the player knows it's open)
	modulate = Color(1, 1, 1, 0.4) if open else Color(1, 1, 1, 1.0)

# ==========================================
# DAMAGE OVERRIDE
# ==========================================
func take_damage(amount: int):
	super(amount) # Subtracts HP and flashes red
	if health <= 0 or is_ghost: return 
	
	path_cost = float(health)
	
	# Update the pathfinder with the new HP if it's currently closed!
	if level_ref and level_ref.building_manager:
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_gate_obstacle(tile, path_cost, is_open)
