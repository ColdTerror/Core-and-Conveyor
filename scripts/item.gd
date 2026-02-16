extends Sprite2D
# Item.gd - Now simplified to be a passive object

@export var item_data: ItemResource


func _ready():
	if item_data:
		texture = item_data.texture
