# ==============================================================================
# Script: Building Classes/gate_building.gd
# Purpose: Class representing security gate structures in defensive walls. Automatically detects worker bots entering its sensor range and slides open the center tile (disabling center physics collision and notifying the A* pathfinder that the center is passable), keeps outer pillars solid and expensive for enemies to attack, tracks damages, and supports dynamic horizontal/vertical orientation resizing.
# Dependencies: Inherits Building. Relies on child sprite node (Sprite2D), child collision body (AutoCollisionBody), creates a dynamic Area2D detection sensor, and expects a class reference WorkerBot to trigger entry/exit callbacks.
# Signals: None.
# ==============================================================================
extends Building
class_name GateBuilding

@export var horizontal_closed: Texture2D
@export var horizontal_open: Texture2D
@export var vertical_closed: Texture2D
@export var vertical_open: Texture2D

@onready var sprite = $Sprite2D

var bots_in_gate: int = 0
var is_open: bool = false
var detection_area: Area2D
var level_ref: Node2D

var is_horizontal: bool = true:
	set(value):
		is_horizontal = value
		size = Vector2i(3, 1) if is_horizontal else Vector2i(1, 3)
		_update_gate_visuals()
		
		if not occupied_tiles.is_empty():
			var obj_layer = null
			if level_ref and level_ref.object_layer:
				obj_layer = level_ref.object_layer
			elif get_parent() and "object_layer" in get_parent():
				obj_layer = get_parent().object_layer
				
			if obj_layer:
				place_at(grid_origin, obj_layer)
		elif has_node("AutoCollisionBody"):
			_update_collision(Vector2(size.x * 32.0, size.y * 32.0))



## Caches the level node instance reference and handles visual and pathfinder anchoring.
func setup(level_instance: Node2D):
	level_ref = level_instance
	
	if level_ref and level_ref.building_manager and (not is_ghost):
		# Anchoring the gate endpoints to visual walls
		var anchors: Array[Vector2i] = [occupied_tiles[0], occupied_tiles[-1]]
		level_ref.building_manager.add_wall_visual(anchors)
		
		# Set high permanent pathfinding weight to outer pillars
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[0], path_cost, true)
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[-1], path_cost, true)
		
		# Center door begins closed and weighted
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[1], path_cost, true)



## Configures gate shapes, dynamic detection areas, custom multi-block physics, and pathfinding weights.
func _ready():
	size = Vector2i(3, 1) if is_horizontal else Vector2i(1, 3)
	super()
	
	is_solid_obstacle = false 
	path_cost = float(health)
	
	_update_gate_visuals()



## Updates the mouse click/hover boundary, custom physical pillars, and bot detection sensor.
func _update_collision(footprint_px: Vector2):
	super(footprint_px)
	
	# Rebuild the 3 separate collision boxes inside AutoCollisionBody
	if has_node("AutoCollisionBody"):
		var static_body = $AutoCollisionBody
		
		for child in static_body.get_children():
			static_body.remove_child(child)
			child.queue_free()
			
		for i in range(3):
			var shape = CollisionShape2D.new()
			var rect = RectangleShape2D.new()
			rect.size = Vector2(32, 32)
			shape.shape = rect
			
			if is_horizontal:
				shape.position = Vector2((i - 1) * 32.0, 0)
			else:
				shape.position = Vector2(0, (i - 1) * 32.0)
				
			if i == 1:
				shape.name = "DoorCollision"
				if is_open:
					shape.disabled = true
					
			static_body.add_child(shape)
			
	# Create or update detection Area2D and its shape size
	if not has_node("DetectionArea"):
		detection_area = Area2D.new()
		detection_area.name = "DetectionArea"
		var det_shape = CollisionShape2D.new()
		det_shape.name = "CollisionShape2D"
		det_shape.shape = RectangleShape2D.new()
		
		detection_area.add_child(det_shape)
		add_child(detection_area)
		
		detection_area.area_entered.connect(_on_bot_entered)
		detection_area.area_exited.connect(_on_bot_exited)
	else:
		detection_area = $DetectionArea
		
	var det_shape = detection_area.get_child(0) as CollisionShape2D
	if det_shape.shape == null:
		det_shape.shape = RectangleShape2D.new()
	var rect = det_shape.shape as RectangleShape2D
	rect.size = Vector2(size.x * 32.0 + 64.0, size.y * 32.0 + 64.0)



## Safely cleans up the wall visuals and pathfinding nodes upon gate destruction.
func die():
	if level_ref and level_ref.building_manager and (not is_ghost):
		var anchors: Array[Vector2i] = [occupied_tiles[0], occupied_tiles[-1]]
		level_ref.building_manager.remove_wall_visual(anchors)
	super()



## Updates the sprite texture to show the gate as open or closed based on orientation.
func _update_gate_visuals():
	if not sprite: return
	
	if is_horizontal:
		sprite.texture = horizontal_open if is_open else horizontal_closed
	else:
		sprite.texture = vertical_open if is_open else vertical_closed



## Opens the gate when a worker bot enters the dynamic motion sensor area.
func _on_bot_entered(area: Area2D):
	if area.get_parent() is WorkerBot:
		bots_in_gate += 1
		if bots_in_gate > 0 and not is_open:
			_set_gate_open(true)



## Closes the gate when the last worker bot exits the dynamic motion sensor area.
func _on_bot_exited(area: Area2D):
	if area.get_parent() is WorkerBot:
		bots_in_gate -= 1
		if bots_in_gate <= 0 and is_open:
			_set_gate_open(false)



## Updates the gate open state, adjusting physical barriers and pathfinding accessibility.
func _set_gate_open(open: bool):
	is_open = open
	
	# Godot requires set_deferred to disable physics shapes during active collision frames
	if has_node("AutoCollisionBody/DoorCollision"):
		$AutoCollisionBody/DoorCollision.set_deferred("disabled", open)
		
	if level_ref and level_ref.building_manager:
		var center_tile = occupied_tiles[1]
		level_ref.building_manager.pathfinder.set_gate_obstacle(center_tile, path_cost, is_open)
		
	_update_gate_visuals()



## Updates the gate pathfinding weights dynamically when taking damage.
func take_damage(amount: int):
	super(amount)
	if health <= 0 or is_ghost: return 
	
	path_cost = float(health)
	
	if level_ref and level_ref.building_manager:
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[0], path_cost, true)
		level_ref.building_manager.pathfinder.set_weighted_obstacle(occupied_tiles[-1], path_cost, true)
		
		var center_tile = occupied_tiles[1]
		level_ref.building_manager.pathfinder.set_gate_obstacle(center_tile, path_cost, is_open)
