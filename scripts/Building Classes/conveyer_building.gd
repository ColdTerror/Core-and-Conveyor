# ==============================================================================
# Script: Building Classes/conveyer_building.gd
# Purpose: Class representing individual conveyor belt nodes that move items through the factory. Operates a two-phase movement loop (moving item from entry edge to exact center, and then center to exit edge), queries adjacent neighbors (belts or buildings) for compatibility/capacity before pushing, applies speed research upgrades dynamically, handles item node creation/cleanups, and packages itself for save/load states.
# Dependencies: Inherits Building. Relies on parent level reference level_ref, global Autoloads ResearchManager, EconomyManager, ItemDatabase, dynamic group "Conveyors", and expects a @export var generic_item_scene to recreate items upon load.
# Signals: Emits item_changed (connected to details panels for updating item displays).
# ==============================================================================
extends Building
class_name ConveyorBuilding

@export var generic_item_scene: PackedScene

@export var base_speed: float = 64.0
var current_speed: float = 64.0

var direction: Vector2i = Vector2i.RIGHT
var held_item: Node2D = null
var level_ref: Node2D

var is_moving_to_edge: bool = false
var is_jammed: bool = false
var push_cooldown: float = 0.0

signal item_changed


## Initializes the conveyor belt structure and registers it into active groups and speed upgrades.
func _ready():
	super()
	add_to_group("Conveyors")
	apply_research_buffs()


## Recalculates conveyor movement speed based on global technology multipliers.
func apply_research_buffs():
	# If the multiplier is 1.5, a 64 speed belt instantly becomes 96!
	current_speed = base_speed * ResearchManager.belt_speed_mult



## Sets up the conveyor's initial direction and visual rotation.
func setup(level_instance: Node2D, dir: Vector2i):
	level_ref = level_instance
	direction = dir if dir != Vector2i.ZERO else Vector2i.RIGHT
	rotation = Vector2(direction).angle()


## Discards the held item safely and updates the economy log when the conveyor is removed.
func _exit_tree():
	if held_item and is_instance_valid(held_item):
		# Tell the economy this item was destroyed for bookkeeping
		if "item_data" in held_item and held_item.item_data:
			EconomyManager.log_item_consumed(held_item.item_data.display_name, 1)
			
		held_item.queue_free()
		held_item = null



## Verifies if the conveyor belt is currently vacant and capable of receiving a new item.
func accepts_item_at(_tile: Vector2i) -> bool:
	return held_item == null



## Welcomes an incoming item node, updating its parent scene hierarchy and snapping its coordinates.
func accept_item_node(item_node: Node2D, source_belt: Node2D = null) -> bool:
	if held_item != null or not level_ref: 
		return false
	
	held_item = item_node
	is_moving_to_edge = false
	
	var old_parent = item_node.get_parent()
	var perpendicular_transfer = false
	var prev_direction = direction
	
	if source_belt:
		if source_belt is RouterBuilding: 
			perpendicular_transfer = true 
			prev_direction = source_belt.direction
		else:
			prev_direction = source_belt.get("direction") if "direction" in source_belt else Vector2i.RIGHT
			if source_belt is ConveyorBridge:
				var manager = level_ref.building_manager
				var my_grid = manager.object_layer.local_to_map(global_position)
				var source_grid = manager.object_layer.local_to_map(source_belt.global_position)
				prev_direction = my_grid - source_grid
			perpendicular_transfer = (Vector2(prev_direction).dot(Vector2(direction)) == 0)
	
	if old_parent and old_parent != level_ref:
		old_parent.remove_child(item_node)
	
	if not item_node.get_parent():
		level_ref.add_child(item_node)
	
	if perpendicular_transfer:
		# Snap exactly to the side it entered from to avoid 0.99 pixel desync that causes stutters
		var entry_edge = global_position - (Vector2(prev_direction) * 16.0)
		item_node.global_position = entry_edge
	else:
		var back_edge = global_position - (Vector2(direction) * 16.0)
		item_node.global_position = back_edge
		
	if held_item != null:
		item_changed.emit()
	return true



## Drives the two-phase item movement loop toward the belt's center and onwards to the neighbor.
func _process(delta):
	if held_item == null: 
		is_jammed = false
		return
	
	if not is_instance_valid(held_item):
		held_item = null
		return
		
	if push_cooldown > 0:
		push_cooldown -= delta
		return

	var target_pos = Vector2.ZERO
	
	# PHASE 1: Moving to Center
	if not is_moving_to_edge:
		target_pos = global_position
		var move_step = current_speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		if held_item.global_position.distance_to(target_pos) < 1.0:
			held_item.global_position = target_pos
			
			if _can_push_to_neighbor():
				is_moving_to_edge = true 
				is_jammed = false
			else:
				is_jammed = true  
				var neighbor = _get_neighbor()
				if not neighbor is ConveyorBuilding:
					push_cooldown = 0.5
	
	# PHASE 2: Moving to Edge
	else:
		target_pos = global_position + (Vector2(direction) * 16.0)
		
		if not _can_push_to_neighbor():
			is_jammed = true  
			var neighbor = _get_neighbor()
			if not neighbor is ConveyorBuilding:
				push_cooldown = 0.5 
			return
		
		is_jammed = false
		var move_step = current_speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		if held_item.global_position.distance_to(target_pos) < 1.0:
			if _push_to_neighbor():
				is_jammed = false
			else:
				is_jammed = true  
				var neighbor = _get_neighbor()
				if not neighbor is ConveyorBuilding:
					push_cooldown = 0.5



## Checks if the adjacent structure or belt has capacity and willingness to receive the item.
func _can_push_to_neighbor() -> bool:
	var neighbor = _get_neighbor()
	if not neighbor: 
		return false
		
	if neighbor.has_method("accepts_item_node_from"):
		return neighbor.accepts_item_node_from(self)
	
	if neighbor is ConveyorBuilding:
		return neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed)
	
	if neighbor.has_method("add_item") and "item_data" in held_item:
		return neighbor.can_accept_item(held_item.item_data)
	
	return false



## Hands over ownership of the held item node directly to the adjacent recipient structure or belt.
func _push_to_neighbor() -> bool:
	var neighbor = _get_neighbor()
	if not neighbor: 
		return false
		
	if neighbor.has_method("accept_item_node") and not (neighbor is ConveyorBuilding):
		if neighbor.accept_item_node(held_item, self):
			held_item = null
			item_changed.emit()
			return true
	
	elif neighbor is ConveyorBuilding:
		if neighbor.accept_item_node(held_item, self):
			held_item = null
			item_changed.emit()
			return true
	
	elif neighbor.has_method("add_item") and "item_data" in held_item:
		if neighbor.add_item(held_item.item_data, 1) > 0:
			held_item.queue_free()
			held_item = null
			item_changed.emit()
			return true
	
	return false



## Queries the building manager to retrieve the structure located at the facing tile coordinate.
func _get_neighbor() -> Node:
	if not level_ref: 
		return null
	
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	var neighbor_grid = my_grid + direction
	var manager = level_ref.building_manager
	
	if manager.occupied_tiles.has(neighbor_grid):
		return manager.occupied_tiles[neighbor_grid]
	
	return null



## Packs the belt's facing direction, movement phases, and held item coordinates for save files.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	data["direction"] = var_to_str(direction)
	data["is_moving_to_edge"] = is_moving_to_edge
	data["push_cooldown"] = push_cooldown
	
	if held_item and is_instance_valid(held_item) and "item_data" in held_item:
		data["held_item_name"] = held_item.item_data.display_name
		data["held_item_x"] = held_item.global_position.x
		data["held_item_y"] = held_item.global_position.y
		
	return data


## Reconstructs the conveyor belt's state, direction, and respawns any saved held items.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	if data.has("direction"):
		direction = str_to_var(data["direction"])
		rotation = Vector2(direction).angle()
		
	is_moving_to_edge = data.get("is_moving_to_edge", false)
	push_cooldown = data.get("push_cooldown", 0.0)
	
	if data.has("held_item_name"):
		if not generic_item_scene:
			print("ERROR: Conveyor cannot load item! Assign generic_item_scene in Inspector.")
			return
			
		var item_res = ItemDatabase.get_item(data["held_item_name"])
		if item_res:
			var new_item = generic_item_scene.instantiate()
			if new_item.has_method("setup"): new_item.setup(level_ref)
			if "item_data" in new_item: new_item.item_data = item_res
			new_item.global_position = Vector2(data["held_item_x"], data["held_item_y"])
			
			if new_item.has_method("_ready"): new_item._ready()
			
			level_ref.add_child(new_item)
			held_item = new_item
