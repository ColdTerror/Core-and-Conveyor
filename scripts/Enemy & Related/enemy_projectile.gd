# ==============================================================================
# Script: Enemy & Related/enemy_projectile.gd
# Purpose: Parabolic arc boulder projectile shot by ranged enemies that damages player
#          buildings and worker bots upon landing.
# Dependencies: Requires a Sprite2D child node. Connects to Area2D signals.
# ==============================================================================
extends Area2D

var start_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var total_time: float = 1.0
var elapsed_time: float = 0.0
var max_arc_height: float = 40.0
var damage: int = 0
var is_arc: bool = false

# Linear fallback properties
var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 10.0

## Sets up the projectile's initial position, velocity direction, speed, damage, and optional arc destination.
func setup(pos: Vector2, dir: Vector2, speed: float, dmg: int, texture: Texture2D = null, _source: Node2D = null, custom_lifetime: float = 10.0, destination_pos: Vector2 = Vector2.ZERO):
	global_position = pos
	damage = dmg
	lifetime = custom_lifetime
	
	if texture and has_node("Sprite2D"): 
		$Sprite2D.texture = texture
		
	if destination_pos != Vector2.ZERO:
		is_arc = true
		start_pos = pos
		target_pos = destination_pos
		var dist = start_pos.distance_to(target_pos)
		total_time = max(0.2, dist / speed)
		max_arc_height = clamp(dist * 0.35, 20.0, 90.0)
		elapsed_time = 0.0
	else:
		is_arc = false
		rotation = dir.angle() + deg_to_rad(45)
		velocity = dir * speed

## Moves the projectile along an arc or linear path and manages spinning/lifetime.
func _physics_process(delta):
	if is_arc:
		elapsed_time += delta
		var t = clamp(elapsed_time / total_time, 0.0, 1.0)
		
		# Ground position interpolation
		var current_ground_pos = start_pos.lerp(target_pos, t)
		global_position = current_ground_pos
		
		if has_node("Sprite2D"):
			# Parabolic arc height formula: 4 * max_h * t * (1 - t)
			var height = 4.0 * max_arc_height * t * (1.0 - t)
			$Sprite2D.position = Vector2(0, -height)
			$Sprite2D.rotation += 6.0 * delta # Spin the boulder
			
		if t >= 1.0:
			_explode_impact()
	else:
		position += velocity * delta
		lifetime -= delta
		if lifetime <= 0: 
			queue_free()

func _explode_impact():
	# Check overlapping bodies/areas at impact location
	for body in get_overlapping_bodies():
		if not body.is_in_group("Enemies") and body.has_method("take_damage"):
			body.take_damage(damage)
			
	for area in get_overlapping_areas():
		var parent = area.get_parent()
		if parent and not parent.is_in_group("Enemies") and parent.has_method("take_damage"):
			parent.take_damage(damage)
			
	queue_free()

## Detects collision with player buildings (PhysicsBody2D), deals damage, and frees linear projectiles.
func _on_body_entered(body):
	if not is_arc:
		if not body.is_in_group("Enemies") and body.has_method("take_damage"):
			body.take_damage(damage)
			queue_free()

## Detects collision with worker bots (Area2D), deals damage, and frees linear projectiles.
func _on_area_entered(area):
	if not is_arc:
		var parent = area.get_parent()
		if parent and not parent.is_in_group("Enemies") and parent.has_method("take_damage"):
			parent.take_damage(damage)
			queue_free()
