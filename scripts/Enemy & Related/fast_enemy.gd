# ==============================================================================
# Script: Enemy & Related/fast_enemy.gd
# Purpose: Specialized fast enemy (Spider) that displays 4x3 walk animations.
#          Row 0: Walk Right (0-3), flip_h for Left
#          Row 1: Walk Down (4-7)
#          Row 2: Walk Up (8-11)
# Dependencies: Inherits Enemy.
# ==============================================================================
extends Enemy
class_name FastEnemy

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
	# Row 0: Walk Right (0-3)
	# Row 1: Walk Down (4-7)
	# Row 2: Walk Up (8-11)
	
	var row = 1 # default to Walk Down
	var flip_h = false
	
	if velocity.length() > 0.1:
		if abs(velocity.y) > abs(velocity.x):
			# Vertical movement dominant
			if velocity.y < 0:
				row = 2 # Walk Up
			else:
				row = 1 # Walk Down
		else:
			# Horizontal movement dominant
			row = 0 # Walk Right/Left
			if velocity.x < 0:
				flip_h = true # Flip Right for Left
	else:
		# If stopped, preserve row from current frame
		if sprite.frame >= 8:
			row = 2
		elif sprite.frame >= 4:
			row = 1
		else:
			row = 0
			flip_h = sprite.flip_h
			
	sprite.flip_h = flip_h
	sprite.flip_v = false

	if velocity.length() < 0.1:
		# Idle frame is frame 0 of the current row
		sprite.frame = row * 4
		return
		
	_frame_timer += delta
	var frame_duration = 1.0 / animation_fps
	if _frame_timer >= frame_duration:
		_frame_timer = fmod(_frame_timer, frame_duration)
		
		var start_frame = row * 4
		if sprite.frame < start_frame or sprite.frame >= start_frame + 4:
			sprite.frame = start_frame
		else:
			sprite.frame = start_frame + ((sprite.frame - start_frame + 1) % 4)
