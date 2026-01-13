extends Sprite2D

@export var speed = 100.0
var current_direction = Vector2.ZERO

func _process(delta):
	# Get the tile position of the item
	var map_pos = %ObjectLayer.local_to_map(global_position)
	
	# Get the custom data (direction) from that tile
	var tile_data = %ObjectLayer.get_cell_tile_data(map_pos)
	
	if tile_data:
		current_direction = tile_data.get_custom_data("direction")
	
	# Move the item
	global_position += current_direction * speed * delta
