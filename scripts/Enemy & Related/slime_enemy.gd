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
