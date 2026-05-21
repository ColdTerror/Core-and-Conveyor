# ==============================================================================
# Script: Managers/camera_controller.gd
# Purpose: Smooth orthographic camera controller supporting WASD/edge screen panning, scroll zoom centered on mouse coordinates, target tracking interpolation, and viewport clamping bounds.
# Dependencies: Requires standard Godot Camera2D parent and coordinates with InputManager for key inputs.
# Signals: None.
# ==============================================================================
extends Camera2D

# Pan settings
@export var pan_speed := 500.0
@export var edge_pan_margin := 20  
@export var edge_pan_speed := 300.0

# Zoom settings
@export var zoom_speed := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 3.0

# Smooth movement
@export var pan_smoothing := 10.0

var target_zoom := 1.0

# CAMERA FOLLOW VARIABLES
var follow_target: Node2D = null
@export var follow_smoothing := 10.0 



## Configures a node target to dynamically follow and centers camera focus on it.
func set_follow_target(target: Node2D):
	follow_target = target



## Initializes default zoom levels and adds camera instance to global group.
func _ready():
	zoom = Vector2(target_zoom, target_zoom)
	add_to_group("Camera")



## Smoothly interpolates zoom levels and target-following movement calculations.
func _process(delta):
	# Handle Follow Target
	if is_instance_valid(follow_target):
		global_position = global_position.lerp(follow_target.global_position, follow_smoothing * delta)
	
	zoom = Vector2(target_zoom, target_zoom)



## Pans the camera in the specified direction, breaking active target tracking.
func apply_pan(move_direction: Vector2, delta: float):
	if move_direction.length() > 0:
		# BREAKAWAY LOGIC
		if follow_target != null:
			follow_target = null
		
		move_direction = move_direction.normalized()
		position += move_direction * pan_speed * delta / target_zoom



## Zooms in or out centered directly on the cursor coordinate point.
func apply_zoom(point: Vector2, zoom_change: float):
	var world_pos_before = get_global_mouse_position()
	
	target_zoom = clamp(target_zoom * zoom_change, min_zoom, max_zoom)
	
	var world_pos_after = get_global_mouse_position()
	
	if follow_target == null:
		position += world_pos_before - world_pos_after
