# ItemResource.gd
extends Resource
class_name ItemResource

@export var display_name: String = "Unknown"   # Name of the item              
@export var texture: Texture2D                 # Sprite to display on belt / in inventory
@export var description: String = ""           # Optional: flavor text


@export_group("Combat Stats")
@export var is_ammo: bool = false
@export var damage: int = 0
@export var stack_size: int = 1 # How much ammo per item
@export var projectile_speed: float = 400.0 # How fast it flies
