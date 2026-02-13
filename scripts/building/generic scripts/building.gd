extends Node2D
class_name Building


signal hovered(building: Building)
signal unhovered(building: Building)

signal inventory_changed
signal health_changed(current_hp: int, max_hp: int)

signal destroyed(building_instance: Building)

var is_ghost: bool = false

# True = Stockpile (Blocks path completely)
# False = Wall (Walkable but expensive)
@export var is_solid_obstacle: bool = true 



# If not solid, how expensive is it?
@export var path_cost: float = 10

@export var is_draggable: bool = false

@export var building_name := "Building"
@export var size := Vector2i(1, 1)
@export var max_health := 100
var health := max_health

@export var icon: Texture2D

var occupied_tiles: Array[Vector2i] = []

@export_group("Economy")
@export var cost_wood: int = 10
@export var cost_stone: int = 0


# --- Ready ---
func _ready():
	if has_node("Area2D"):
		$Area2D.mouse_entered.connect(_on_mouse_entered)
		$Area2D.mouse_exited.connect(_on_mouse_exited)


# --- Ghost / Visuals ---
func set_ghost(enabled: bool):
	is_ghost = enabled
	if has_node("Area2D"):
		$Area2D.monitoring = not enabled
		$Area2D.visible = not enabled

	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(1, 1, 1, 0.5 if enabled else 1)

func set_valid_placement(valid: bool):
	if has_node("Sprite2D"):
		$Sprite2D.modulate = Color(0.6, 1, 0.6, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)


# --- Footprint calculation ---
func get_footprint(origin: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(size.x):
		for y in range(size.y):
			tiles.append(origin + Vector2i(x, y))
	return tiles

func get_radius() -> float:
	# Calculate an approximate radius based on occupied tiles.
	# Standard tile is 32x32, so radius is ~16.
	# If we occupy 9 tiles (3x3), the "radius" from center is roughly 48px.
	
	if occupied_tiles.is_empty():
		return 16.0 # Default fallback
		
	# Quick math: Get the largest dimension
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for tile in occupied_tiles:
		min_x = min(min_x, tile.x)
		max_x = max(max_x, tile.x)
		min_y = min(min_y, tile.y)
		max_y = max(max_y, tile.y)
		
	var width = (max_x - min_x + 1) * 32.0
	var height = (max_y - min_y + 1) * 32.0
	
	# Return half the largest side (Radius)
	return max(width, height) / 2.0

# Returns a list of world positions where an enemy can stand to hit this building
func get_access_points(pathfinder_node: Pathfinder) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var grid = pathfinder_node.astar
	
	# Loop through every tile this building occupies
	for tile_pos in occupied_tiles:
		# Check all 4 neighbors of this specific tile
		var neighbors = [
			Vector2i(0, 1), Vector2i(0, -1), 
			Vector2i(1, 0), Vector2i(-1, 0)
		]
		
		for offset in neighbors:
			var check_pos = tile_pos + offset
			
			# 1. Is it inside map bounds?
			if not grid.is_in_boundsv(check_pos): continue
			
			# 2. Is it NOT solid? (i.e., Walkable)
			# We want to stand on empty ground, not inside a wall.
			if not grid.is_point_solid(check_pos):
				# Convert to World Position
				var local_pos = pathfinder_node.main_layer.map_to_local(check_pos)
				var global_pos = pathfinder_node.main_layer.to_global(local_pos)
				points.append(global_pos)
				
	return points
	
# --- Placement ---
func place_at(origin: Vector2i, object_layer: TileMapLayer):
	occupied_tiles = get_footprint(origin)

	var tile_size := Vector2(object_layer.tile_set.tile_size)
	var top_left_world := object_layer.map_to_local(origin)
	var footprint_px := Vector2(size) * tile_size
	global_position = (top_left_world + footprint_px / 2) - (tile_size / 2)

	_update_collision(footprint_px)


func _update_collision(footprint_px: Vector2):
	if not has_node("Area2D/CollisionShape2D"):
		return

	var area := $Area2D
	var collision_shape := $Area2D/CollisionShape2D
	var shape := collision_shape.shape as RectangleShape2D

	shape.size = footprint_px
	area.position = Vector2.ZERO
	collision_shape.position = Vector2.ZERO


# --- Signals ---
func _on_mouse_entered():
	hovered.emit(self)

func _on_mouse_exited():
	unhovered.emit(self)
	
# --- Building Functions ---
func building_tick(delta: float) -> void:
	pass
	
# --- Inventory stuff ---

# Returns a Dictionary where Key = Resource/String, Value = Amount
func get_inventory_info() -> Dictionary:
	return {}
	

# --- Economy stuff ---

# Helper to bundle costs into a dictionary for the Manager
func get_build_cost() -> Dictionary:
	var cost = {}
	if cost_wood > 0: cost["Wood"] = cost_wood
	if cost_stone > 0: cost["Stone"] = cost_stone
	return cost
	
# --- Item Stuff ---

# Can items enter this specific tile of the building?
# Default: NO (Walls, Harvesters, etc. block items)
func accepts_item_at(_tile: Vector2i) -> bool:
	return false

# Is the item type allowed? (e.g. Filter logic)
# Default: NO
func can_accept_item(_item: ItemResource) -> bool:
	return false

# Actually take the item
# Default: Fail safely
func accept_item(_item: ItemResource) -> bool:
	return false
	
	
# NEW FUNCTION:
# Returns a clean dictionary of { "ResourceName": Amount }
# Default: Empty (Towers/Walls return nothing, so no crash)
func get_economy_assets() -> Dictionary:
	return {}

# --- Health Stuff ---
func take_damage(amount: int):
	health -= amount
	
	health_changed.emit(health, max_health)
	# Optional: Flash color to show damage
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	
	if health <= 0:
		die()

func die():
	# We need to tell the pathfinder this tile is open again!
	# (We will add a signal for this later, for now just free it)
	destroyed.emit(self)
	queue_free()
	
# --- NEW VIRTUAL FUNCTION ---
# Called by EconomyManager when spending resources.
# 'remaining_bill' is a Dictionary { "Wood": 10 }.
# The building should subtract what it has, and lower the bill.
func consume_resources(remaining_bill: Dictionary):
	pass # Default behavior: Do nothing (Walls/Towers don't hold items)
