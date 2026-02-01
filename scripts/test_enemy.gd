# test_enemy.gd
extends CharacterBody2D

@export var health: int = 50

# The Tower calls this when the projectile hits
func take_damage(amount: int):
	health -= amount
	print("Ouch! Enemy took %d damage. HP Left: %d" % [amount, health])
	
	# Visual feedback (flash red)
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	
	if health <= 0:
		die()

func die():
	print("Enemy Destroyed!")
	queue_free()
