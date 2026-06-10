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

@export_group("Regrowth")
@export var can_regrow: bool = false
@export var regrow_time: float = 5.0 

@export_group("Visuals (Atlas Coords)")
# Default/Full state coordinates (e.g. The full tree)
@export var atlas_coords_full: Vector2i = Vector2i(-1, -1)
# Depleted/Stump state coordinates (e.g. The stump)
@export var atlas_coords_depleted: Vector2i = Vector2i(-1, -1)
# Optional: Intermediate state (e.g. Leafless tree)
@export var atlas_coords_harvesting: Vector2i = Vector2i(-1, -1)

@export_group("Seasonal Atlas Coords")
@export var atlas_coords_spring: Vector2i = Vector2i(-1, -1)
@export var atlas_coords_summer: Vector2i = Vector2i(-1, -1)
@export var atlas_coords_autumn: Vector2i = Vector2i(-1, -1)
@export var atlas_coords_winter: Vector2i = Vector2i(-1, -1)



## Returns the seasonal atlas coordinates for the given season and state.
func get_seasonal_coords(season: int, state: int) -> Vector2i:
	match state:
		0: # ResourceManager.ResourceState.FULL
			match season:
				0: # TimeManager.Season.SPRING
					return atlas_coords_spring if atlas_coords_spring != Vector2i(-1, -1) else atlas_coords_full
				1: # TimeManager.Season.SUMMER
					return atlas_coords_summer if atlas_coords_summer != Vector2i(-1, -1) else atlas_coords_full
				2: # TimeManager.Season.AUTUMN
					return atlas_coords_autumn if atlas_coords_autumn != Vector2i(-1, -1) else atlas_coords_full
				3: # TimeManager.Season.WINTER
					return atlas_coords_winter if atlas_coords_winter != Vector2i(-1, -1) else atlas_coords_full
		1: # ResourceManager.ResourceState.HARVESTING
			return atlas_coords_harvesting
		2: # ResourceManager.ResourceState.DEPLETED
			return atlas_coords_depleted
	return atlas_coords_full

@export_group("Harvesting Drops")
# LINK: When mined, this tile produces this Item
@export var item_drop: ItemResource 
@export var drop_amount: int = 1
