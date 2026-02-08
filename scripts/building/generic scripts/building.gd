extends Node2D
class_name Building


signal hovered(building: Building)
signal unhovered(building: Building)

signal inventory_changed
signal health_changed(current_hp: int, max_hp: int)

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
	queue_free()
