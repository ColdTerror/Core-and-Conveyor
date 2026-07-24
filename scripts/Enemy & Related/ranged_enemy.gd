# ==============================================================================
# Script: Enemy & Related/ranged_enemy.gd
# Purpose: Specialized ranged enemy (Tank) that displays 2x3 tread animations.
#          Row 0: Move Right (0-1), flip_h for Left
#          Row 1: Move Down (2-3)
#          Row 2: Move Up (4-5)
# Dependencies: Inherits Enemy.
# ==============================================================================
extends Enemy
class_name RangedEnemy

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
	# Row 0: Move Right (0-1)
	# Row 1: Move Down (2-3)
	# Row 2: Move Up (4-5)
	
	var row = 1 # default to Move Down
	var flip_h = false
	
	if velocity.length() > 0.1:
		if abs(velocity.y) > abs(velocity.x):
			# Vertical movement dominant
			if velocity.y < 0:
				row = 2 # Move Up
			else:
				row = 1 # Move Down
		else:
			# Horizontal movement dominant
			row = 0 # Move Right/Left
			if velocity.x < 0:
				flip_h = true # Flip Right for Left
	else:
		# If stopped, preserve row from current frame
		if sprite.frame >= 4:
			row = 2
		elif sprite.frame >= 2:
			row = 1
		else:
			row = 0
			flip_h = sprite.flip_h
			
	sprite.flip_h = flip_h
	sprite.flip_v = false

	if velocity.length() < 0.1:
		# Idle frame is frame 0 of the current row
		sprite.frame = row * 2
		return
		
	_frame_timer += delta
	var frame_duration = 1.0 / animation_fps
	if _frame_timer >= frame_duration:
		_frame_timer = fmod(_frame_timer, frame_duration)
		
		var start_frame = row * 2
		if sprite.frame < start_frame or sprite.frame >= start_frame + 2:
			sprite.frame = start_frame
		else:
			sprite.frame = start_frame + ((sprite.frame - start_frame + 1) % 2)
