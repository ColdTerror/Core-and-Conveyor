# ==============================================================================
# Script: Enemy & Related/enemy_projectile.gd
# Purpose: Seek-less linear projectile shot by ranged enemies that damages player
#          buildings and worker bots.
# Dependencies: Requires a Sprite2D child node. Connects to Area2D signals.
# ==============================================================================
extends Area2D

var velocity: Vector2 = Vector2.ZERO
var damage: int = 0
var lifetime: float = 10.0



## Sets up the projectile's initial position, velocity direction, speed, and damage.
func setup(pos: Vector2, dir: Vector2, speed: float, dmg: int, texture: Texture2D, _source: Node2D = null, custom_lifetime: float = 10.0):
	global_position = pos
	rotation = dir.angle() + deg_to_rad(45)
	velocity = dir * speed
	damage = dmg
	lifetime = custom_lifetime
	if texture and has_node("Sprite2D"): 
		$Sprite2D.texture = texture



## Moves the projectile forward linearly and manages its lifetime.
func _physics_process(delta):
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0: 
		queue_free()



## Detects collision with player buildings (PhysicsBody2D), deals damage, and frees the projectile.
func _on_body_entered(body):
	# Damage any non-enemy that can take damage
	if not body.is_in_group("Enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()



## Detects collision with worker bots (Area2D), deals damage, and frees the projectile.
func _on_area_entered(area):
	var parent = area.get_parent()
	if parent and not parent.is_in_group("Enemies") and parent.has_method("take_damage"):
		parent.take_damage(damage)
		queue_free()
