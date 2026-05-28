# ==============================================================================
# Script: Building Classes/wall.gd
# Purpose: Defensive wall structure that registers as an expensive walkable obstacle with the Pathfinder, paints autotiles dynamically to connect neighboring walls, hides individual sprites on placement, and dynamically alters its path cost weight as health changes.
# Dependencies: Inherits Building. Requires building manager visual painting, Pathfinder connections, and child nodes (Sprite2D).
# Signals: Inherits signals from Building (such as health_changed).
# ==============================================================================
extends Building
class_name WallBuilding

var level_ref: Node2D

@onready var sprite = $Sprite2D



## Links this wall to the active level instance and handles autotile initialization.
func setup(level_instance: Node2D):
	level_ref = level_instance
	
	if level_ref and level_ref.building_manager and (not is_ghost):
		if sprite:
			sprite.hide()
			
		level_ref.building_manager.add_wall_visual(occupied_tiles)
		
		# Set the initial pathfinder weights
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_weighted_obstacle(tile, path_cost, true)


## Sets solid status, sets initial path costs, and connects health signals to dynamically sync path costs.
func _ready():
	super()
	
	# Force walls to be walkable obstacles
	is_solid_obstacle = false 
	
	# Set our initial path cost to perfectly match our health
	path_cost = float(health)
	
	if has_signal("health_changed"):
		health_changed.connect(_on_health_changed)



## Custom death handler that erases the wall visual, updates neighboring wall tiles,
## and runs the base Building destruction routine.
func die():
	if level_ref and level_ref.building_manager and (not is_ghost):
		# Tell the TileMap to erase the visual and update neighbors
		level_ref.building_manager.remove_wall_visual(occupied_tiles)
		
	# Run normal death logic (which will call queue_free)
	super()



## Inflicts damage to the wall, updating active path cost weight.
func take_damage(amount: int):
	# Run the base Building.gd script first! 
	# (This handles the actual HP subtraction, signals, and red flash)
	super(amount)
	
	# If we just died, stop here (the die() function handles clearing the tile)
	if health <= 0 or is_ghost:
		return 
		
	_sync_path_cost()



## Triggered when the wall's health is adjusted (e.g. from repairs), syncing costs.
func _on_health_changed(_current_hp: int, _max_hp: int):
	_sync_path_cost()


## Synchronizes the pathfinder cost weights to perfectly match current health status.
func _sync_path_cost():
	if is_ghost: return
	
	# Update our specific path cost to match the new health
	path_cost = float(health)
	
	# Immediately tell the pathfinder that this tile's weight has changed
	if level_ref and level_ref.building_manager:
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_weighted_obstacle(tile, path_cost, true)
