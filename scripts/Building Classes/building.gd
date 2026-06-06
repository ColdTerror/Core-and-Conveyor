# ==============================================================================
# Script: Building Classes/building.gd
# Purpose: Base class representing all structures in the game. Handles base parameters (health, level, footprint size, build/upgrade costs, ranges), collision shapes (mouse hov/click Area2D and enemy body StaticBody2D), placement ghost visual effects, damage processing, and virtual method interfaces for saving, loading, item transportation, and resource spending.
# Dependencies: Requires area nodes (Area2D, Area2D/CollisionShape2D), dynamic nodes (AutoCollisionBody), CostData resources, global Autoload InputManager, and references to Pathfinder.
# Signals:
#   - hovered(building: Building): Emitted when cursor hovers over a building.
#   - unhovered(building: Building): Emitted when cursor leaves the building's hitbox.
#   - inventory_changed: Emitted when stockpiled items are consumed/stored.
#   - health_changed(current_hp: int, max_hp: int): Emitted when taking damage.
#   - destroyed(building_instance: Building): Emitted when the building dies.
# ==============================================================================
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
@export var build_costs: Array[CostData] = []

@export_group("Ranges")
# How far this building allows other buildings to be placed from it
@export var build_range: int = 5
@export var corruption_range: int = 6

@export_group("Upgrade Settings")
@export var building_level: int = 1
## The scene this building turns into. Leave blank if max tier!
@export var upgrades_to: PackedScene 
## Upgrade resources required
@export var upgrade_cost: Array[CostData] = []

var grid_origin: Vector2i = Vector2i.ZERO

var is_selected: bool = false



## Initializes structure stats, footprint physics boundaries, and connects mouse collision shapes.
func _ready():
	y_sort_enabled = true
	var footprint_px = Vector2(size.x * 32.0, size.y * 32.0)
	_update_collision(footprint_px)
	
	health = max_health
	if has_node("Area2D"):
		# Connect hover signals if not connected
		if not $Area2D.mouse_entered.is_connected(_on_mouse_entered):
			$Area2D.mouse_entered.connect(_on_mouse_entered)
		if not $Area2D.mouse_exited.is_connected(_on_mouse_exited):
			$Area2D.mouse_exited.connect(_on_mouse_exited)



## Automatically generates or updates Area2D hover meshes and StaticBody2D obstacles.
func _update_collision(footprint_px: Vector2):
	var area: Area2D
	var area_shape: CollisionShape2D
	
	if not has_node("Area2D"):
		# Create dynamically
		area = Area2D.new()
		area.name = "Area2D"
		area_shape = CollisionShape2D.new()
		area_shape.name = "CollisionShape2D"
		area_shape.shape = RectangleShape2D.new()
		
		area.add_child(area_shape)
		add_child(area)
	else:
		# Update existing
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

	var static_body: StaticBody2D
	
	if not has_node("AutoCollisionBody"):
		# Create dynamically
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
		
	# Apply exact pixel size
	var p_shape = static_body.get_child(0) as CollisionShape2D
	p_shape.shape.size = footprint_px
	static_body.position = Vector2.ZERO
	p_shape.position = Vector2.ZERO



## Configures building ghost visuals and disables pathfinder physics layers during placement previews.
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



## Toggles placement preview visual overlays between valid green and blocked red colors.
func set_valid_placement(valid: bool):
	if not is_ghost: return
	modulate = Color(0.6, 1, 0.6, 0.5) if valid else Color(1, 0.4, 0.4, 0.5)



## Maps grid tile bounds spanning from a top-left origin base coordinate.
func get_footprint(origin: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(size.x):
		for y in range(size.y):
			tiles.append(origin + Vector2i(x, y))
	return tiles



## Computes the approximate visual radius enclosing the building's total footprint side boundaries.
func get_radius() -> float:
	if occupied_tiles.is_empty():
		return 16.0
		
	# Get largest dimension
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
	
	# Return half the largest side
	return max(width, height) / 2.0



## Finds map tiles adjacent to the structure boundaries where enemies can stand to deal damage.
func get_access_points(pathfinder_node: Pathfinder) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var grid = pathfinder_node.enemy_astar
	
	# Loop through occupied tiles
	for tile_pos in occupied_tiles:
		# Check neighbor offsets
		var neighbors = [
			Vector2i(0, 1), Vector2i(0, -1), 
			Vector2i(1, 0), Vector2i(-1, 0)
		]
		
		for offset in neighbors:
			var check_pos = tile_pos + offset
			
			# Check bounds
			if not grid.is_in_boundsv(check_pos): continue
			
			# Stand on walkable empty ground
			if not grid.is_point_solid(check_pos):
				# Convert to world position
				var local_pos = pathfinder_node.main_layer.map_to_local(check_pos)
				var global_pos = pathfinder_node.main_layer.to_global(local_pos)
				points.append(global_pos)
				
	return points
	


## Places the structure coordinates at grid coordinates and updates physics footprint shapes.
func place_at(origin: Vector2i, object_layer: TileMapLayer):
	grid_origin = origin
	occupied_tiles = get_footprint(origin)

	var tile_size := Vector2(object_layer.tile_set.tile_size)
	var top_left_world := object_layer.map_to_local(origin)
	var footprint_px := Vector2(size) * tile_size
	global_position = (top_left_world + footprint_px / 2) - (tile_size / 2)

	_update_collision(footprint_px)



## Signals mouse entry events and updates global hovered structures references.
func _on_mouse_entered():
	hovered.emit(self)
	InputManager.hovered_building = self



## Signals mouse exit events and releases global hover structures focus.
func _on_mouse_exited():
	unhovered.emit(self)
	# Clear only if still hovered
	if InputManager and InputManager.hovered_building == self:
		InputManager.hovered_building = null
	


## Virtual method executed every gameplay frame update.
func building_tick(delta: float) -> void:
	pass
	


## Virtual method packing stock capacity numbers into display dictionaries.
func get_inventory_info() -> Dictionary:
	return {}
	


## Helper to bundle build costs into a dictionary for the Manager.
func get_build_cost() -> Dictionary:
	var cost_dict = {}
	
	for cost in build_costs:
		cost_dict[cost.item_name] = cost.amount
		
	return cost_dict
	


## Virtual query verifying if items can enter this building's specified coordinate.
func accepts_item_at(_tile: Vector2i) -> bool:
	return false



## Virtual verification checks if specific item cargo types are allowed.
func can_accept_item(_item: ItemResource) -> bool:
	return false



## Virtual action processing the absorption or processing of an incoming item.
func accept_item(_item: ItemResource) -> bool:
	return false
	


## Virtual check verifying inventory space limits.
func has_space_for(item_name: String) -> bool:
	return false



## Virtual ledger counting secured items stored inside stockpile or core vaults.
func get_economy_assets() -> Dictionary:
	return {}



## Processes incoming damage values and triggers flash feedback and destruction thresholds.
func take_damage(amount: int):
	health -= amount
	
	health_changed.emit(health, max_health)
	
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	
	if health <= 0:
		die()



## Frees the occupied grid bounds and queues node destruction.
func die():
	if is_ghost:
		queue_free()
		return
	destroyed.emit(self)
	occupied_tiles.clear()
	queue_free()
	


## Virtual command draining item quantities to pay construction resource bills.
func consume_resources(remaining_bill: Dictionary):
	pass



## Packs core configurations into dictionary payloads before structural tier upgrades.
func get_upgrade_data() -> Dictionary:
	var data = {}
		
	if "selected_output_name" in self:
		data["selected_output_name"] = self.get("selected_output_name")
		
	if "targeting_mode" in self:
		data["targeting_mode"] = self.get("targeting_mode")
	if "current_targeting_index" in self:
		data["current_targeting_index"] = self.get("current_targeting_index")
	
	if "direction" in self:
		data["direction"] = self.get("direction")
	if "rotation" in self:
		data["rotation"] = self.get("rotation")
	
	if "is_horizontal" in self:
		data["is_horizontal"] = self.get("is_horizontal")
		
	return data



## Restructures and applies historical upgrades data onto newly constructed building tiers.
func apply_upgrade_data(data: Dictionary):
	# Unpacks data into new tier
	if data.has("selected_output_name") and "selected_output_name" in self:
		self.set("selected_output_name", data["selected_output_name"])
	
	if data.has("targeting_mode") and "targeting_mode" in self:
		self.set("targeting_mode", data["targeting_mode"])
	if data.has("current_targeting_index") and "current_targeting_index" in self:
		self.set("current_targeting_index", data["current_targeting_index"])
		
	if data.has("direction") and "direction" in self:
		self.set("direction", data["direction"])
	if data.has("rotation") and "rotation" in self:
		self.set("rotation", data["rotation"])
		
	if data.has("is_horizontal") and "is_horizontal" in self:
		self.set("is_horizontal", data["is_horizontal"])
	


## Packs structural stats and configurations for database save files.
func get_save_data() -> Dictionary:
	var data = {
		"building_name": building_name,
		"health": health
	}
	
	if "is_horizontal" in self: data["is_horizontal"] = self.get("is_horizontal")
		
	return data



## Restructures active values from saved database records.
func load_save_data(data: Dictionary):
	health = data.get("health", max_health)
	
	# Trigger health bar updates
	if health < max_health:
		health_changed.emit(health, max_health)
