extends Building
class_name GateBuilding

# ==========================================
# GATE SPRITES 
# ==========================================
@export var horizontal_closed: Texture2D
@export var horizontal_open: Texture2D
@export var vertical_closed: Texture2D
@export var vertical_open: Texture2D

@onready var sprite = $Sprite2D

var bots_in_gate: int = 0
var is_open: bool = false
var detection_area: Area2D
var level_ref: Node2D

# --- NEW: Setter dynamically updates size when rotated! ---
var is_horizontal: bool = true:
	set(value):
		is_horizontal = value
		size = Vector2i(3, 1) if is_horizontal else Vector2i(1, 3)
		_update_gate_visuals()

func setup(level_instance: Node2D):
	level_ref = level_instance
	
func _ready():
	# Force the correct size BEFORE the base class builds the physics!
	size = Vector2i(3, 1) if is_horizontal else Vector2i(1, 3)
	super()
	
	is_solid_obstacle = false 
	path_cost = float(health)
	
	if level_ref and level_ref.building_manager and (not is_ghost):
		# --- THE ANCHOR TRICK ---
		var anchors: Array[Vector2i] = [occupied_tiles[0], occupied_tiles[-1]]
		level_ref.building_manager.add_wall_visual(anchors)
		
		# --- PATHFINDER FIX ---
		# The two outer pillars are permanently high-cost!
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[0], path_cost, true)
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[-1], path_cost, true)
		
		# The center door starts high-cost, but will toggle!
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[1], path_cost, true)
		
	# --- PHYSICS FIX: 3 SEPARATE BLOCKS ---
	if has_node("AutoCollisionBody"):
		var static_body = $AutoCollisionBody
		
		# 1. Delete the giant shape the base class made
		for child in static_body.get_children():
			child.queue_free()
			
		# 2. Build 3 distinct 1x1 tiles
		for i in range(3):
			var shape = CollisionShape2D.new()
			var rect = RectangleShape2D.new()
			rect.size = Vector2(32, 32)
			shape.shape = rect
			
			# Offset them to form the 3x1 or 1x3 line (local 0,0 is the center tile)
			if is_horizontal:
				shape.position = Vector2((i - 1) * 32.0, 0)
			else:
				shape.position = Vector2(0, (i - 1) * 32.0)
				
			# Name the middle one so we can find it when the gate opens!
			if i == 1:
				shape.name = "DoorCollision"
				
			static_body.add_child(shape)
			
	# Dynamic Motion Sensor
	detection_area = Area2D.new()
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(size.x * 32.0 + 64.0, size.y * 32.0 + 64.0)
	shape.shape = rect
	detection_area.add_child(shape)
	add_child(detection_area)
	
	detection_area.area_entered.connect(_on_bot_entered)
	detection_area.area_exited.connect(_on_bot_exited)
	
	_update_gate_visuals()

func die():
	if level_ref and level_ref.building_manager and (not is_ghost):
		# --- Clean up ONLY the anchors ---
		var anchors: Array[Vector2i] = [occupied_tiles[0], occupied_tiles[-1]]
		level_ref.building_manager.remove_wall_visual(anchors)
	super()
	
# --- Visual Update Function ---
func _update_gate_visuals():
	if not sprite: return
	
	if is_horizontal:
		sprite.texture = horizontal_open if is_open else horizontal_closed
	else:
		sprite.texture = vertical_open if is_open else vertical_closed
		
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
	
	# 1. ONLY drop the physical barrier for the center tile!
	# We use set_deferred because Godot hates changing physics shapes in the middle of a collision calculation.
	if has_node("AutoCollisionBody/DoorCollision"):
		$AutoCollisionBody/DoorCollision.set_deferred("disabled", open)
		
	# 2. ONLY tell the Enemy Pathfinder that the center door is open!
	if level_ref and level_ref.building_manager:
		var center_tile = occupied_tiles[1]
		level_ref.building_manager.pathfinder.set_gate_obstacle(center_tile, path_cost, is_open)
		
	_update_gate_visuals()

# ==========================================
# DAMAGE OVERRIDE
# ==========================================
func take_damage(amount: int):
	super(amount) # Subtracts HP and flashes red
	if health <= 0 or is_ghost: return 
	
	path_cost = float(health)
	
	if level_ref and level_ref.building_manager:
		# Keep the permanent pillars updated
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[0], path_cost, true)
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[-1], path_cost, true)
		
		# Update the center tile's logic based on its current open/closed state
		var center_tile = occupied_tiles[1]
		level_ref.building_manager.pathfinder.set_gate_obstacle(center_tile, path_cost, is_open)
