# ==============================================================================
# Script: projectile.gd
# Purpose: Drives target-seeking and linear physics behavior of arrows/projectiles
#          fired from defensive structures. Handles impact detection and damage.
# Dependencies: Requires a Sprite2D child node. Connects to the Area2D body_entered signal.
# Signals: None.
# ==============================================================================
extends Area2D

var velocity: Vector2 = Vector2.ZERO
var damage: int = 0
var lifetime: float = 10.0

var source_tower: Node2D = null


## Sets up the projectile's initial position, velocity direction, speed, damage, texture, and source tower.
func setup(pos: Vector2, dir: Vector2, speed: float, dmg: int, texture: Texture2D, source: Node2D = null):
	global_position = pos
	rotation = dir.angle() + deg_to_rad(45)
	velocity = dir * speed
	damage = dmg
	source_tower = source
	if texture: $Sprite2D.texture = texture



## Moves the projectile forward linearly and manages its lifetime, freeing it when the time expires.
func _physics_process(delta):
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0: queue_free()



## Detects collision with enemies, applies damage, and frees the projectile.
func _on_body_entered(body):
	if body.is_in_group("Enemies"):
		if body.has_method("take_damage"):
			var valid_source = source_tower if is_instance_valid(source_tower) else null
			body.take_damage(damage, valid_source)
		queue_free()
