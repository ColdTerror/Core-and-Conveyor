# Projectile.gd
extends Area2D

var velocity: Vector2 = Vector2.ZERO
var damage: int = 0
var lifetime: float = 10.0

var source_tower: Node2D = null

func setup(pos: Vector2, dir: Vector2, speed: float, dmg: int, texture: Texture2D, source: Node2D = null ):
	global_position = pos
	rotation = dir.angle() + deg_to_rad(45)
	velocity = dir * speed
	damage = dmg
	source_tower = source
	if texture: $Sprite2D.texture = texture
	
func _physics_process(delta):
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0: queue_free()

func _on_body_entered(body):
	if body.is_in_group("Enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage, source_tower)
		queue_free() # Destroy arrow on impact
		
