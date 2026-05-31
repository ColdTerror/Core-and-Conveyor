# ItemResource.gd
extends Resource
class_name ItemResource

@export var display_name: String = "Unknown"   # Name of the item              
@export var texture: Texture2D                 # Sprite to display on belt / in inventory
@export var description: String = ""           # Optional: flavor text


@export_group("Combat Stats")
@export var is_ammo: bool = false
@export_enum("None", "Arrow", "BallistaBolt", "Pebble", "Boulder", "Magic") var ammo_type: String = "None" # NEW
@export var damage: int = 0
@export var stack_size: int = 1
@export var projectile_speed: float = 400.0
@export var projectile_lifetime: float = 1.0 # How long it lasts (Range limit)
