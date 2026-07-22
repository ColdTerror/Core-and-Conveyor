# ==============================================================================
# Script: Enemy & Related/flyer_enemy.gd
# Purpose: Specialized flyer enemy (Drone) that displays 3x3 flight animations.
#          Row 0: Fly Right (0-2), flip_h for Left
#          Row 1: Fly Down (3-5)
#          Row 2: Fly Up (6-8)
# Dependencies: Inherits Enemy.
# ==============================================================================
extends Enemy
class_name FlyerEnemy

var _frame_timer: float = 0.0
@export var animation_fps: float = 6.0

func _physics_process(delta):
	super(delta)
	if health <= 0: return
	
	if has_node("Sprite2D"):
		var sprite = $Sprite2D as Sprite2D
		if sprite.hframes > 1 or sprite.vframes > 1:
			_animate_sprite(delta, sprite)

func _animate_sprite(delta: float, sprite: Sprite2D):
	# Row 0: Fly Right (0-2)
	# Row 1: Fly Down (3-5)
	# Row 2: Fly Up (6-8)
	
	var row = 1 # default to Fly Down
	var flip_h = false
	
	if velocity.length() > 0.1:
		if abs(velocity.y) > abs(velocity.x):
			# Vertical movement dominant
			if velocity.y < 0:
				row = 2 # Fly Up
			else:
				row = 1 # Fly Down
		else:
			# Horizontal movement dominant
			row = 0 # Fly Right/Left
			if velocity.x < 0:
				flip_h = true # Flip Right for Left
	else:
		# If stopped, preserve row from current frame
		if sprite.frame >= 6:
			row = 2
		elif sprite.frame >= 3:
			row = 1
		else:
			row = 0
			flip_h = sprite.flip_h
			
	sprite.flip_h = flip_h
	sprite.flip_v = false

	# Drones continuously animate their rotors hovering
	_frame_timer += delta
	var frame_duration = 1.0 / animation_fps
	if _frame_timer >= frame_duration:
		_frame_timer = fmod(_frame_timer, frame_duration)
		
		var start_frame = row * 3
		if sprite.frame < start_frame or sprite.frame >= start_frame + 3:
			sprite.frame = start_frame
		else:
			sprite.frame = start_frame + ((sprite.frame - start_frame + 1) % 3)
