# ==============================================================================
# Script: Enemy & Related/slime_enemy.gd
# Purpose: Specialized enemy unit representing slimes that split into smaller
#          versions of themselves upon death.
# Dependencies: Inherits Enemy.
# ==============================================================================
extends Enemy
class_name SlimeEnemy

@export_group("Slime Settings")
@export var slime_tier: int = 3 # 3 = Large, 2 = Medium, 1 = Small
@export var child_slime_scene: PackedScene

var _frame_timer: float = 0.0
@export var animation_fps: float = 2.0


func _physics_process(delta):
	super(delta)
	if health <= 0: return
	
	if has_node("Sprite2D"):
		var sprite = $Sprite2D as Sprite2D
		if sprite.hframes > 1 or sprite.vframes > 1:
			_animate_sprite(delta, sprite)


func _animate_sprite(delta: float, sprite: Sprite2D):
	# Determine facing row based on current velocity or last velocity
	var walk_up_row = false
	if velocity.length() > 0.1:
		walk_up_row = (abs(velocity.y) > abs(velocity.x))
		if walk_up_row:
			sprite.flip_h = false
			sprite.flip_v = (velocity.y > 0)
		else:
			sprite.flip_h = (velocity.x < 0) # Flip when walking left (since sheet is drawn facing right)
			sprite.flip_v = false
	else:
		# If stopped, we can check based on current flips
		walk_up_row = (sprite.frame >= 4)
		
	if velocity.length() < 0.1:
		# Idle frame
		sprite.frame = 4 if walk_up_row else 0
		return
		
	_frame_timer += delta
	var frame_duration = 1.0 / animation_fps
	if _frame_timer >= frame_duration:
		_frame_timer = fmod(_frame_timer, frame_duration)
		
		var start_frame = 4 if walk_up_row else 0
		if sprite.frame < start_frame or sprite.frame >= start_frame + 4:
			sprite.frame = start_frame
		else:
			sprite.frame = start_frame + ((sprite.frame - start_frame + 1) % 4)



## Overrides base die() to spawn two smaller slime instances if tier > 1.
func die():
	if slime_tier > 1 and child_slime_scene:
		for i in range(2):
			# Spawn offset to prevent exact stacking
			var offset = Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
			var child = child_slime_scene.instantiate()
			
			child.add_to_group("Enemies")
			
			# Setup child stats
			child.slime_tier = slime_tier - 1
			child.max_health = max_health / 2
			child.health = child.max_health
			child.damage = max(1, int(damage / 2.0))
			child.movement_speed = movement_speed * 1.25 # Gets faster as it shrinks!
			
			# Shrink visual scale
			child.scale = scale * 0.7
			
			# Setup pathfinder reference for child
			child.pathfinder = pathfinder
			
			# Add to the level scene tree
			if get_parent():
				get_parent().add_child(child)
				child.global_position = global_position + offset
				
				# Triggers the initial target scan on next physics frame
				child._find_target()
	
	super.die()
