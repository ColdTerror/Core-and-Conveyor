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
var health: int

@export var icon: Texture2D

var occupied_tiles: Array[Vector2i] = []

@export_group("Economy")
# We export a dictionary. We can give it a default value of just Wood so new buildings aren't free!
@export var build_costs: Array[CostData] = []

@export_group("Ranges")
# How far this building allows other buildings to be placed from it
@export var build_range: float = 5.0
@export var corruption_range: float = 6.0

@export_group("Upgrade Settings")
@export var building_level: int = 1 # 
## The scene this building turns into. Leave blank if max tier!
@export var upgrades_to: PackedScene 
## The resources required to upgrade (e.g. {"Wooden Planks": 5, "Raw Stone": 2})
@export var upgrade_cost: Array[CostData] = []

var grid_origin: Vector2i = Vector2i.ZERO

# --- Ready ---
func _ready():
	_generate_collision_box()
	health = max_health
	if has_node("Area2D"):
		$Area2D.mouse_entered.connect(_on_mouse_entered)
		$Area2D.mouse_exited.connect(_on_mouse_exited)

# ==========================================
# AUTO-GENERATED PHYSICS
# ==========================================
func _generate_collision_box():
	# 1. Create the Physics Body
	var static_body = StaticBody2D.new()
	static_body.name = "AutoCollisionBody"
	
	# 2. Create the Shape
	var collision_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	
	# 3. Calculate the exact pixel size based on grid footprint!
	rect.size = Vector2(size.x * 32, size.y * 32)
	collision_shape.shape = rect
	
	
	# 4. Assemble the nodes
	static_body.add_child(collision_shape)
	add_child(static_body)
	
	# 5. Ghost Safety: Disable collision if this is a placement preview!
	if "is_ghost" in self and is_ghost:
		static_body.collision_layer = 0
		static_body.collision_mask = 0
	else:
		# Standard physics layer
		static_body.collision_layer = 1
		static_body.collision_mask = 1

func update_collision_size(new_grid_size: Vector2i):
	size = new_grid_size
	
	var static_body = get_node_or_null("AutoCollisionBody")
	if static_body and static_body.get_child_count() > 0:
		var collision_shape = static_body.get_child(0) as CollisionShape2D
		
		# Update the size of the rectangle
		if collision_shape and collision_shape.shape is RectangleShape2D:
			collision_shape.shape.size = Vector2(size.x * 32, size.y * 32)
			
			# (If you uncommented the offset line earlier, uncomment this one too!)
			# collision_shape.position = collision_shape.shape.size / 2.0

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
	grid_origin = origin
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
	var cost_dict = {}
	
	for cost in build_costs:
		cost_dict[cost.item_name] = cost.amount
		
	return cost_dict
	
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
	if is_ghost:
		queue_free()
		return
	# We need to tell the pathfinder this tile is open again!
	# (We will add a signal for this later, for now just free it)
	destroyed.emit(self)
	occupied_tiles.clear()
	queue_free()
	
# --- NEW VIRTUAL FUNCTION ---
# Called by EconomyManager when spending resources.
# 'remaining_bill' is a Dictionary { "Wood": 10 }.
# The building should subtract what it has, and lower the bill.
func consume_resources(remaining_bill: Dictionary):
	pass # Default behavior: Do nothing (Walls/Towers don't hold items)
