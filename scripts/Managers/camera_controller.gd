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

# Pan Zone Settings
@export var pan_limits_left := 0
@export var pan_limits_right := 4800
@export var pan_limits_up := 0
@export var pan_limits_down := 4800

# Zoom settings
@export var zoom_speed := 0.25
@export var min_zoom := 0.35
@export var max_zoom := 5.0

# Smooth movement
@export var pan_smoothing := 10.0

var target_zoom := 1.0
var is_dragging := false

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
	
	clamp_camera_to_bounds()



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



## Sets the active dragging state and breaks target following.
func set_drag_state(dragging: bool):
	is_dragging = dragging
	if is_dragging and follow_target != null:
		follow_target = null



## Drag-pans the camera by a relative screen vector, factoring in zoom and breakaway.
func apply_drag_pan(relative: Vector2):
	if follow_target != null:
		follow_target = null
	
	position -= relative / target_zoom 
	
func clamp_camera_to_bounds():
	# 1. Get viewport dimensions in world space
	var viewport_size = get_viewport_rect().size / target_zoom
	var half_width = viewport_size.x / 2.0
	var half_height = viewport_size.y / 2.0
	
	# 2. Define the target bounds (4800 map size + 800px padding = -800 to 5600)
	var min_x = half_width - 800
	var max_x = (pan_limits_right + 800) - half_width
	
	var min_y = half_height - 800
	var max_y = (pan_limits_down + 800) - half_height
	# 3. Clamp camera center coordinates (with a fallback if zoomed out too far)
	if min_x > max_x:
		position.x = (pan_limits_left + pan_limits_right) / 2.0 # Center on map if zoomed way out
	else:
		position.x = clamp(position.x, min_x, max_x)
	if min_y > max_y:
		position.y = (pan_limits_up + pan_limits_down) / 2.0 # Center on map if zoomed way out
	else:
		position.y = clamp(position.y, min_y, max_y)
