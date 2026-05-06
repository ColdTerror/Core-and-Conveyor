extends Building
class_name WallBuilding

var level_ref: Node2D

# --- NEW: Grab the sprite so we can hide it! ---
@onready var sprite = $Sprite2D

func setup(level_instance: Node2D):
	level_ref = level_instance
	
func _ready():
	super()
	
	# 1. Force walls to be walkable obstacles
	is_solid_obstacle = false 
	
	# 2. Set our initial path cost to perfectly match our health
	path_cost = float(health)
	
	if level_ref and level_ref.building_manager and (not is_ghost):
		# --- NEW: Hide the standalone sprite and paint the autotile! ---
		if sprite:
			sprite.hide()
			
		level_ref.building_manager.add_wall_visual(occupied_tiles)
		
		# Set the initial pathfinder weights
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_weighted_obstacle(tile, path_cost, true)
			
	# --- NEW: Listen for bot repairs so the path cost goes back UP! ---
	if has_signal("health_changed"):
		health_changed.connect(_on_health_changed)

# --- NEW: Clean up the TileMap when destroyed ---
func die():
	if level_ref and level_ref.building_manager and (not is_ghost):
		# Tell the TileMap to erase the visual and update neighbors
		level_ref.building_manager.remove_wall_visual(occupied_tiles)
		
	# Run normal death logic (which will call queue_free)
	super()

func take_damage(amount: int):
	# 1. Run the base Building.gd script first! 
	# (This handles the actual HP subtraction, signals, and red flash)
	super(amount)
	
	# If we just died, stop here (the die() function handles clearing the tile)
	if health <= 0 or is_ghost:
		return 
		
	# 2. Sync the pathfinder
	_sync_path_cost()

# --- NEW: Keeps the pathfinder accurate when bots repair the wall ---
func _on_health_changed(_current_hp: int, _max_hp: int):
	_sync_path_cost()

func _sync_path_cost():
	if is_ghost: return
	
	# Update our specific path cost to match the new health
	path_cost = float(health)
	
	# Immediately tell the pathfinder that this tile's weight has changed
	if level_ref and level_ref.building_manager:
		for tile in occupied_tiles:
			level_ref.building_manager.pathfinder.set_weighted_obstacle(tile, path_cost, true)
