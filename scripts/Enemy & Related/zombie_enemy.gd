# ==============================================================================
# Script: Enemy & Related/zombie_enemy.gd
# Purpose: Specialized basic enemy (Zombie Miner) that displays walk animations
#          using a 3x8 sprite sheet with horizontal flip.
# Dependencies: Inherits Enemy.
# ==============================================================================
extends Enemy
class_name ZombieEnemy

var _frame_timer: float = 0.0
@export var animation_fps: float = 4.0

func _physics_process(delta):
	super(delta)
	if health <= 0: return
	
	if has_node("Sprite2D"):
		var sprite = $Sprite2D as Sprite2D
		if sprite.hframes > 1 or sprite.vframes > 1:
			_animate_sprite(delta, sprite)

func _animate_sprite(delta: float, sprite: Sprite2D):
	# Row 0: Walk Right (0-7)
	# Row 1: Walk Up (8-15)
	# Row 2: Walk Down (16-23)
	
	# Determine facing row and horizontal flip based on velocity
	var row = 2 # default to Walk Down
	var flip_h = false
	
	if velocity.length() > 0.1:
		if abs(velocity.y) > abs(velocity.x):
			# Vertical movement dominant
			if velocity.y < 0:
				row = 1 # Walk Up
			else:
				row = 2 # Walk Down
		else:
			# Horizontal movement dominant
			row = 0 # Walk Right/Left
			if velocity.x < 0:
				flip_h = true # Flip Right for Left
	else:
		# If stopped, preserve the row from current frame
		if sprite.frame >= 16:
			row = 2
		elif sprite.frame >= 8:
			row = 1
		else:
			row = 0
			flip_h = sprite.flip_h
			
	sprite.flip_h = flip_h
	sprite.flip_v = false # No vertical flip needed for this layout

	if velocity.length() < 0.1:
		# Idle frame is frame 0 of the current row (e.g., 0, 8, or 16)
		sprite.frame = row * 8
		return
		
	_frame_timer += delta
	var frame_duration = 1.0 / animation_fps
	if _frame_timer >= frame_duration:
		_frame_timer = fmod(_frame_timer, frame_duration)
		
		var start_frame = row * 8
		if sprite.frame < start_frame or sprite.frame >= start_frame + 8:
			sprite.frame = start_frame
		else:
			sprite.frame = start_frame + ((sprite.frame - start_frame + 1) % 8)
