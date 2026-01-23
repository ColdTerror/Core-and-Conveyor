# TileDataResource.gd
extends Resource
class_name TileDataResource

@export_group("General")
@export var display_name: String = "Unknown"
@export var is_object: bool = false
@export var is_conveyor: bool = false
@export var conveyor_direction: Vector2 = Vector2.RIGHT

@export_group("Mining & Resources")
@export var total_resources: int = 10
@export var amount_per_mine: int = 1
@export var mining_time: float = 1.0

@export_group("Regrowth")
@export var can_regrow: bool = false
@export var regrow_time: float = 5.0 

@export_group("Visuals (Atlas Coords)")
# Default/Full state coordinates (e.g. The full tree)
@export var atlas_coords_full: Vector2i 
# Depleted/Stump state coordinates (e.g. The stump)
@export var atlas_coords_depleted: Vector2i = Vector2i(-1, -1)
# Optional: Intermediate state (e.g. Leafless tree)
@export var atlas_coords_harvesting: Vector2i = Vector2i(-1, -1)
