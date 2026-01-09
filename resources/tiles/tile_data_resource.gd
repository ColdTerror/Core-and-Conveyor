extends Resource
class_name TileDataResource

@export var display_name: String = "Unknown"
@export var is_object: bool = false # True for Forest/Stone, False for Dirt/Water
@export var total_resources: int = 10
@export var amount_per_mine: int = 1
@export var mining_time: float = 1.0 # Seconds it takes to mine
@export var texture: Texture2D # For future sprite use
