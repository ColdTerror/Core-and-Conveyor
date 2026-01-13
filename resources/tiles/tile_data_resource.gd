# TileDataResource.gd
extends Resource
class_name TileDataResource

@export var display_name: String = "Unknown"
@export var is_object: bool = false
@export var is_conveyor: bool = false # NEW: identifies if this tile moves things
@export var conveyor_direction: Vector2 = Vector2.RIGHT # NEW: the direction it pushes
@export var total_resources: int = 10
@export var amount_per_mine: int = 1
@export var mining_time: float = 1.0 
@export var texture: Texture2D
