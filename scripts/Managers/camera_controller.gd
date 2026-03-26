# camera_controller.gd
# Attach this to a Camera2D node in your scene

extends Camera2D

# Pan settings
@export var pan_speed := 500.0
@export var edge_pan_margin := 20  # pixels from screen edge
@export var edge_pan_speed := 300.0

# Zoom settings
@export var zoom_speed := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 3.0

# Smooth movement
@export var pan_smoothing := 10.0

var target_zoom := 1.0

# ==========================================
# --- NEW: CAMERA FOLLOW VARIABLES ---
# ==========================================
var follow_target: Node2D = null
@export var follow_smoothing := 10.0 # How "snappy" the camera tracks the bot

func set_follow_target(target: Node2D):
	follow_target = target
# ==========================================

func _ready():
	# Set initial zoom
	zoom = Vector2(target_zoom, target_zoom)
	
	# Add to group so the UI can find this camera blindly!
	add_to_group("Camera")

func _process(delta):
	if GameState.is_menu_open: return
	
	# ==========================================
	# --- NEW: FOLLOW TARGET MATH ---
	# ==========================================
	if is_instance_valid(follow_target):
		global_position = global_position.lerp(follow_target.global_position, follow_smoothing * delta)
	# ==========================================
	
	handle_keyboard_pan(delta)
	#handle_edge_pan(delta)
	
	zoom = Vector2(target_zoom, target_zoom)
	


func handle_keyboard_pan(delta):
	var move_direction := Vector2.ZERO
	
	# WASD or Arrow keys
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_direction.x += 1
	#if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
	if Input.is_key_pressed(KEY_A):
		move_direction.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_direction.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_direction.y -= 1
	
	if move_direction.length() > 0:
		
		# ==========================================
		# --- NEW: BREAKAWAY LOGIC ---
		# If the player touches WASD, cancel the follow target immediately!
		# ==========================================
		if follow_target != null:
			follow_target = null
		
		move_direction = move_direction.normalized()
		# Move slower when zoomed in, faster when zoomed out
		position += move_direction * pan_speed * delta / target_zoom

func handle_edge_pan(delta):
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport_rect().size
	var move_direction := Vector2.ZERO
	
	# Check screen edges
	if mouse_pos.x < edge_pan_margin:
		move_direction.x -= 1
	elif mouse_pos.x > viewport_size.x - edge_pan_margin:
		move_direction.x += 1
	
	if mouse_pos.y < edge_pan_margin:
		move_direction.y -= 1
	elif mouse_pos.y > viewport_size.y - edge_pan_margin:
		move_direction.y += 1
	
	if move_direction.length() > 0:
		
		# (Also break the lock here, just in case you re-enable edge panning later!)
		if follow_target != null:
			follow_target = null
			
		position += move_direction * edge_pan_speed * delta / target_zoom



func _input(event):
	if GameState.is_menu_open: return
	
	# Zoom with mouse wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_at_point(event.position, 1 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_at_point(event.position, 1 - zoom_speed)

func zoom_at_point(point: Vector2, zoom_change: float):
	# Calculate world position before zoom
	var world_pos_before = get_global_mouse_position()
	
	# Apply zoom
	target_zoom = clamp(target_zoom * zoom_change, min_zoom, max_zoom)
	
	# Adjust position to keep mouse point stable
	var world_pos_after = get_global_mouse_position()
	
	# Optional refinement: Only offset the camera position if we ARE NOT following a target. 
	# (Zooming to mouse while tracking a moving bot can cause a slight stutter).
	if follow_target == null:
		position += world_pos_before - world_pos_after
