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



@export var path_cost: float = 10.0

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


var is_selected: bool = false

# --- Ready ---
func _ready():
	var footprint_px = Vector2(size.x * 32.0, size.y * 32.0)
	_update_collision(footprint_px)
	
	health = max_health
	if has_node("Area2D"):
		# Check if they are already connected before connecting!
		if not $Area2D.mouse_entered.is_connected(_on_mouse_entered):
			$Area2D.mouse_entered.connect(_on_mouse_entered)
		if not $Area2D.mouse_exited.is_connected(_on_mouse_exited):
			$Area2D.mouse_exited.connect(_on_mouse_exited)

# ==========================================
# UNIFIED PLACEMENT UPDATER
# ==========================================
func _update_collision(footprint_px: Vector2):
	# --------------------------------------------------
	# 1. Update or Create Area2D (For Mouse Hover/Clicks)
	# --------------------------------------------------
	var area: Area2D
	var area_shape: CollisionShape2D
	
	if not has_node("Area2D"):
		# Create it dynamically!
		area = Area2D.new()
		area.name = "Area2D"
		area_shape = CollisionShape2D.new()
		area_shape.name = "CollisionShape2D"
		area_shape.shape = RectangleShape2D.new()
		
		area.add_child(area_shape)
		add_child(area)
	else:
		# Update the existing one!
		area = $Area2D
		area_shape = $Area2D/CollisionShape2D
		
		if area_shape.shape == null:
			area_shape.shape = RectangleShape2D.new()
		elif not area_shape.shape.is_local_to_scene():
			area_shape.shape = area_shape.shape.duplicate()
			
	var shape := area_shape.shape as RectangleShape2D
	shape.size = footprint_px
	area.position = Vector2.ZERO
	area_shape.position = Vector2.ZERO

	# --------------------------------------------------
	# 2. Update or Create StaticBody2D (For Enemy Physics)
	# --------------------------------------------------
	var static_body: StaticBody2D
	
	if not has_node("AutoCollisionBody"):
		# Create it dynamically!
		static_body = StaticBody2D.new()
		static_body.name = "AutoCollisionBody"
		var phys_shape = CollisionShape2D.new()
		phys_shape.shape = RectangleShape2D.new()
		static_body.add_child(phys_shape)
		add_child(static_body)
	else:
		static_body = $AutoCollisionBody
	
	# Apply ghost physics rules
	if "is_ghost" in self and is_ghost:
		static_body.collision_layer = 0
		static_body.collision_mask = 0
	else:
		static_body.collision_layer = 1
		static_body.collision_mask = 1
		
	# Apply the exact pixel size!
	var p_shape = static_body.get_child(0) as CollisionShape2D
	p_shape.shape.size = footprint_px
	static_body.position = Vector2.ZERO
	p_shape.position = Vector2.ZERO

# --- Ghost / Visuals ---
func set_ghost(enabled: bool):
	is_ghost = enabled
	if has_node("Area2D"):
		$Area2D.monitoring = not enabled
		$Area2D.visible = not enabled
	
	if has_node("AutoCollisionBody"):
		var static_body = $AutoCollisionBody
		static_body.collision_layer = 0 if enabled else 1
		static_body.collision_mask = 0 if enabled else 1
	
	modulate = Color(1, 1, 1, 0.5 if enabled else 1)

func set_valid_placement(valid: bool):
	if not is_ghost: return
	modulate = Color(0.6, 1, 0.6, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)

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
	var grid = pathfinder_node.enemy_astar
	
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



# --- Signals ---
func _on_mouse_entered():
	hovered.emit(self)
	InputManager.hovered_building = self

func _on_mouse_exited():
	unhovered.emit(self)
	# Only clear it if we are still the currently hovered building!
	if  InputManager and InputManager.hovered_building == self:
		InputManager.hovered_building = null
	
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
	
func has_space_for(item_name: String) -> bool:
	return false


# Returns a clean dictionary of { "ResourceName": Amount }
# Default: Empty (Towers/Walls return nothing, so no crash)
func get_economy_assets() -> Dictionary:
	return {}

# --- Health Stuff ---
func take_damage(amount: int):
	health -= amount
	
	health_changed.emit(health, max_health)
	
			
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	
	if health <= 0:
		die()

func die():
	if is_ghost:
		queue_free()
		return
	destroyed.emit(self)
	occupied_tiles.clear()
	queue_free()
	
# --- NEW VIRTUAL FUNCTION ---
# Called by EconomyManager when spending resources.
# 'remaining_bill' is a Dictionary { "Wood": 10 }.
# The building should subtract what it has, and lower the bill.
func consume_resources(remaining_bill: Dictionary):
	pass # Default behavior: Do nothing (Walls/Towers don't hold items)

# ==========================================
# UPGRADE STATE TRANSFER
# ==========================================

# Packs up important data before dying
func get_upgrade_data() -> Dictionary:
	var data = {}
		
	# Save Dedicated Stockpile filters (if you have them)
	if "selected_output_name" in self:
		data["selected_output_name"] = self.get("selected_output_name")
		
	# Save Tower logic
	if "targeting_mode" in self:
		data["targeting_mode"] = self.get("targeting_mode")
	if "current_targeting_index" in self:
		data["current_targeting_index"] = self.get("current_targeting_index")
	
	# --- Save Conveyor / Directional Logic ---
	if "direction" in self:
		data["direction"] = self.get("direction")
	if "rotation" in self:
		data["rotation"] = self.get("rotation")
	
	# --- NEW: Save Gate Rotation Logic ---
	if "is_horizontal" in self:
		data["is_horizontal"] = self.get("is_horizontal")
		
	print("GET UPGRADE DATA")
	print(data)
	return data

# Unpacks the data into the newly spawned building
func apply_upgrade_data(data: Dictionary):
	print("restoring upgrade data")
	print(data)
		
	# Restore Filters
	if data.has("selected_output_name") and "selected_output_name" in self:
		self.set("selected_output_name", data["selected_output_name"])
	
	# Restore Tower logic
	if data.has("targeting_mode") and "targeting_mode" in self:
		self.set("targeting_mode", data["targeting_mode"])
	if data.has("current_targeting_index") and "current_targeting_index" in self:
		self.set("current_targeting_index", data["current_targeting_index"])
		
	# --- Restore Conveyor / Directional Logic ---
	if data.has("direction") and "direction" in self:
		self.set("direction", data["direction"])
	if data.has("rotation") and "rotation" in self:
		self.set("rotation", data["rotation"])
		
	# --- NEW: Restore Gate Rotation Logic ---
	if data.has("is_horizontal") and "is_horizontal" in self:
		# This automatically triggers your setter function to fix the size/sprites!
		self.set("is_horizontal", data["is_horizontal"])
	

# ==========================================
# SAVE / LOAD SYSTEM (Base Class)
# ==========================================
func get_save_data() -> Dictionary:
	var data = {
		"building_name": building_name,
		"health": health
	}
	
	if "is_horizontal" in self: data["is_horizontal"] = self.get("is_horizontal")
		
	return data

func load_save_data(data: Dictionary):
	# 1. Restore the base stats
	health = data.get("health", max_health)
	
	# 2. Trigger the UI to update the health bar if it took damage!
	if health < max_health:
		health_changed.emit(health, max_health)
