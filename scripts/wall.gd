# Wall.gd
extends StaticBody2D

@export var health: int = 100

func take_damage(amount: int):
	health -= amount
	# Optional: Flash color to show damage
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	
	if health <= 0:
		die()

func die():
	# We need to tell the pathfinder this tile is open again!
	# (We will add a signal for this later, for now just free it)
	queue_free()
