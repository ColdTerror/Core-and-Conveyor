# ItemResource.gd
extends Resource
class_name ItemResource

@export var display_name: String = "Unknown"   # Name of the item
@export var max_stack: int = 50               # How many fit in one stack
@export var texture: Texture2D                 # Sprite to display on belt / in inventory
@export var description: String = ""           # Optional: flavor text
