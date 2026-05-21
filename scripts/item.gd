# ==============================================================================
# Script: item.gd
# Purpose: Displays a passive 2D item sprite in the game world, pulling its texture
#          dynamically from the referenced ItemResource.
# Dependencies: ItemResource.
# Signals: None.
# ==============================================================================
extends Sprite2D

@export var item_data: ItemResource


## Initializes the item sprite by setting its texture from the item resource data.
func _ready() -> void:
	if item_data:
		texture = item_data.texture

