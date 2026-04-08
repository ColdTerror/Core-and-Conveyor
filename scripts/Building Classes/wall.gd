extends Building
class_name WallBuilding


var level_ref: Node2D

func setup(level_instance: Node2D):
	level_ref = level_instance
	
func _ready():
	super()
	
	# 1. Force walls to be walkable obstacles
	is_solid_obstacle = false 
	
	# 2. Set our initial path cost to perfectly match our health
	path_cost = float(health)
	
	if level_ref and level_ref.building_manager and (not is_ghost):
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_weighted_obstacle(tile, path_cost, true)

func take_damage(amount: int):
	# 1. Run the base Building.gd script first! 
	# (This handles the actual HP subtraction, signals, and red flash)
	super(amount)
	
	# If we just died, stop here (the die() function handles clearing the tile)
	if health <= 0 or is_ghost:
		return 
		
	# 2. Update our specific path cost to match the new, lowered health
	path_cost = float(health)
	
	# 3. Immediately tell the pathfinder that this tile is now cheaper to walk on!
	if level_ref and level_ref.building_manager:
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_weighted_obstacle(tile, path_cost, true)
