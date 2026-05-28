# ==============================================================================
# Script: Building Classes/conveyer_bridge.gd
# Purpose: Class representing high-capacity conveyor bridge intersections (crossovers).
#          Operates two completely independent horizontal and vertical item transit channels
#          simultaneously in parallel, allowing crossing lines to flow smoothly at the
#          same time without mixing or jamming.
# Dependencies: Inherits ConveyorBuilding.
# ==============================================================================
extends ConveyorBuilding
class_name ConveyorBridge

# --- HORIZONTAL CHANNEL ---
var horizontal_held_item: Node2D = null
var h_moving_to_edge: bool = false
var h_jammed: bool = false
var h_dir: Vector2i = Vector2i.RIGHT
var h_cooldown: float = 0.0

# --- VERTICAL CHANNEL ---
var vertical_held_item: Node2D = null
var v_moving_to_edge: bool = false
var v_jammed: bool = false
var v_dir: Vector2i = Vector2i.DOWN
var v_cooldown: float = 0.0



## Initializes the bridge structure.
func _ready():
	super()
	building_name = "Conveyor Bridge"



## Overrides node setup.
func setup(level_instance: Node2D, _dir: Vector2i = Vector2i.RIGHT):
	level_ref = level_instance



## Discards both held items safely upon structure removal.
func _exit_tree():
	_discard_item(horizontal_held_item)
	_discard_item(vertical_held_item)
	horizontal_held_item = null
	vertical_held_item = null
	super()



## Safely cleans up and decrements economy logs for discarded items.
func _discard_item(item: Node2D):
	if item and is_instance_valid(item):
		if "item_data" in item and item.item_data:
			EconomyManager.log_item_consumed(item.item_data.display_name, 1)
		item.queue_free()



## Verifies if the corresponding channel axis has capacity to accept a new item.
func accepts_item_node_from(source_belt: Node2D) -> bool:
	if not source_belt: return false
	
	var dir = source_belt.get("direction") if "direction" in source_belt else Vector2i.RIGHT
	if dir.y == 0: # Horizontal
		return horizontal_held_item == null
	else: # Vertical
		return vertical_held_item == null



## Snaps and routes the incoming item node along its entering axis direction.
func accept_item_node(item_node: Node2D, source_belt: Node2D = null) -> bool:
	if not level_ref or not item_node: return false
	
	var is_horizontal = true
	var entry_dir = Vector2i.RIGHT
	
	if source_belt:
		if source_belt is ConveyorBridge:
			var manager = level_ref.building_manager
			var my_grid = manager.object_layer.local_to_map(global_position)
			var source_grid = manager.object_layer.local_to_map(source_belt.global_position)
			entry_dir = my_grid - source_grid
		else:
			entry_dir = source_belt.get("direction") if "direction" in source_belt else Vector2i.RIGHT
		is_horizontal = (entry_dir.y == 0)
		
	if is_horizontal:
		if horizontal_held_item != null: return false
		horizontal_held_item = item_node
		h_dir = entry_dir
		h_moving_to_edge = false
		h_jammed = false
	else:
		if vertical_held_item != null: return false
		vertical_held_item = item_node
		v_dir = entry_dir
		v_moving_to_edge = false
		v_jammed = false
		
	var old_parent = item_node.get_parent()
	if old_parent and old_parent != level_ref:
		old_parent.remove_child(item_node)
		
	if not item_node.get_parent():
		level_ref.add_child(item_node)
		
	# Snap the item to the entry edge of the bridge on the correct axis
	var entry_edge = global_position - (Vector2(entry_dir) * 16.0)
	item_node.global_position = entry_edge
	
	item_changed.emit()
	return true



## Separately drives the two-phase item movement loop for both transit channels.
func _process(delta):
	_process_channel(delta, true)  # Process Horizontal Channel
	_process_channel(delta, false) # Process Vertical Channel



## Traces and handles the two-phase translation steps for a single transit channel.
func _process_channel(delta: float, is_h: bool):
	var item = horizontal_held_item if is_h else vertical_held_item
	if item == null:
		if is_h: h_jammed = false
		else: v_jammed = false
		return
		
	if not is_instance_valid(item):
		if is_h: horizontal_held_item = null
		else: vertical_held_item = null
		return
		
	var cooldown = h_cooldown if is_h else v_cooldown
	if cooldown > 0.0:
		cooldown -= delta
		if is_h: h_cooldown = max(0.0, cooldown)
		else: v_cooldown = max(0.0, cooldown)
		return
		
	var moving_to_edge = h_moving_to_edge if is_h else v_moving_to_edge
	var dir = h_dir if is_h else v_dir
	var target_pos = Vector2.ZERO
	
	# PHASE 1: Moving to Center
	if not moving_to_edge:
		target_pos = global_position
		var move_step = current_speed * delta
		item.global_position = item.global_position.move_toward(target_pos, move_step)
		
		if item.global_position.distance_to(target_pos) < 1.0:
			item.global_position = target_pos
			
			if _bridge_can_push_to_neighbor(is_h):
				if is_h: h_moving_to_edge = true
				else: v_moving_to_edge = true
				if is_h: h_jammed = false
				else: v_jammed = false
			else:
				if is_h: h_jammed = true
				else: v_jammed = true
				var neighbor = _bridge_get_neighbor(is_h)
				if not neighbor is ConveyorBuilding:
					if is_h: h_cooldown = 0.5
					else: v_cooldown = 0.5
					
	# PHASE 2: Moving to Edge
	else:
		target_pos = global_position + (Vector2(dir) * 16.0)
		
		if not _bridge_can_push_to_neighbor(is_h):
			if is_h: h_jammed = true
			else: v_jammed = true
			var neighbor = _bridge_get_neighbor(is_h)
			if not neighbor is ConveyorBuilding:
				if is_h: h_cooldown = 0.5
				else: v_cooldown = 0.5
			return
			
		if is_h: h_jammed = false
		else: v_jammed = false
		var move_step = current_speed * delta
		item.global_position = item.global_position.move_toward(target_pos, move_step)
		
		if item.global_position.distance_to(target_pos) < 1.0:
			if _bridge_push_to_neighbor(is_h):
				if is_h: h_jammed = false
				else: v_jammed = false
			else:
				if is_h: h_jammed = true
				else: v_jammed = true
				var neighbor = _bridge_get_neighbor(is_h)
				if not neighbor is ConveyorBuilding:
					if is_h: h_cooldown = 0.5
					else: v_cooldown = 0.5



## Checks if the facing neighbor coordinate has room to receive the crossing item.
func _bridge_can_push_to_neighbor(is_h: bool) -> bool:
	var neighbor = _bridge_get_neighbor(is_h)
	if not neighbor: return false
	
	var item = horizontal_held_item if is_h else vertical_held_item
	if item == null or not is_instance_valid(item): return false
	
	if neighbor.has_method("accepts_item_node_from"):
		return neighbor.accepts_item_node_from(self)
		
	if neighbor is ConveyorBuilding:
		return neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed)
		
	if neighbor.has_method("add_item") and "item_data" in item:
		return neighbor.can_accept_item(item.item_data)
		
	return false



## Hands over item ownership directly to the facing neighbor.
func _bridge_push_to_neighbor(is_h: bool) -> bool:
	var neighbor = _bridge_get_neighbor(is_h)
	if not neighbor: return false
	
	var item = horizontal_held_item if is_h else vertical_held_item
	if item == null or not is_instance_valid(item): return false
	
	if neighbor.has_method("accept_item_node") and not (neighbor is ConveyorBuilding):
		if neighbor.accept_item_node(item, self):
			if is_h: horizontal_held_item = null
			else: vertical_held_item = null
			item_changed.emit()
			return true
			
	elif neighbor is ConveyorBuilding:
		if neighbor.accept_item_node(item, self):
			if is_h: horizontal_held_item = null
			else: vertical_held_item = null
			item_changed.emit()
			return true
			
	elif neighbor.has_method("add_item") and "item_data" in item:
		if neighbor.add_item(item.item_data, 1) > 0:
			item.queue_free()
			if is_h: horizontal_held_item = null
			else: vertical_held_item = null
			item_changed.emit()
			return true
			
	return false



## Queries the building manager to retrieve the structure located at the facing tile coordinate.
func _bridge_get_neighbor(is_h: bool) -> Node:
	if not level_ref: return null
	
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	var dir = h_dir if is_h else v_dir
	var neighbor_grid = my_grid + dir
	var manager = level_ref.building_manager
	
	if manager.occupied_tiles.has(neighbor_grid):
		return manager.occupied_tiles[neighbor_grid]
		
	return null



## Returns descriptions of any items currently crossing the bridge slots for the details panel.
func get_inventory_info() -> Dictionary:
	var info = {}
	if horizontal_held_item and is_instance_valid(horizontal_held_item):
		info["Horizontal Channel"] = horizontal_held_item.item_data.display_name
	else:
		info["Horizontal Channel"] = "Empty"
		
	if vertical_held_item and is_instance_valid(vertical_held_item):
		info["Vertical Channel"] = vertical_held_item.item_data.display_name
	else:
		info["Vertical Channel"] = "Empty"
		
	return info



## Packs all bridge transit states and items cleanly into save dictionaries.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	data["h_moving_to_edge"] = h_moving_to_edge
	data["h_dir_x"] = h_dir.x
	data["h_dir_y"] = h_dir.y
	data["h_cooldown"] = h_cooldown
	if horizontal_held_item and is_instance_valid(horizontal_held_item) and "item_data" in horizontal_held_item:
		data["h_held_item_name"] = horizontal_held_item.item_data.display_name
		data["h_held_item_x"] = horizontal_held_item.global_position.x
		data["h_held_item_y"] = horizontal_held_item.global_position.y
		
	data["v_moving_to_edge"] = v_moving_to_edge
	data["v_dir_x"] = v_dir.x
	data["v_dir_y"] = v_dir.y
	data["v_cooldown"] = v_cooldown
	if vertical_held_item and is_instance_valid(vertical_held_item) and "item_data" in vertical_held_item:
		data["v_held_item_name"] = vertical_held_item.item_data.display_name
		data["v_held_item_x"] = vertical_held_item.global_position.x
		data["v_held_item_y"] = vertical_held_item.global_position.y
		
	return data



## Restores both channels and respawns active transit items cleanly.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	h_moving_to_edge = data.get("h_moving_to_edge", false)
	h_dir = Vector2i(data.get("h_dir_x", 1), data.get("h_dir_y", 0))
	h_cooldown = data.get("h_cooldown", 0.0)
	
	v_moving_to_edge = data.get("v_moving_to_edge", false)
	v_dir = Vector2i(data.get("v_dir_x", 0), data.get("v_dir_y", 1))
	v_cooldown = data.get("v_cooldown", 0.0)
	
	if data.has("h_held_item_name"):
		var item_res = ItemDatabase.get_item(data["h_held_item_name"])
		if item_res and generic_item_scene:
			var new_item = generic_item_scene.instantiate()
			if new_item.has_method("setup"): new_item.setup(level_ref)
			if "item_data" in new_item: new_item.item_data = item_res
			new_item.global_position = Vector2(data["h_held_item_x"], data["h_held_item_y"])
			if new_item.has_method("_ready"): new_item._ready()
			level_ref.add_child(new_item)
			horizontal_held_item = new_item
			
	if data.has("v_held_item_name"):
		var item_res = ItemDatabase.get_item(data["v_held_item_name"])
		if item_res and generic_item_scene:
			var new_item = generic_item_scene.instantiate()
			if new_item.has_method("setup"): new_item.setup(level_ref)
			if "item_data" in new_item: new_item.item_data = item_res
			new_item.global_position = Vector2(data["v_held_item_x"], data["v_held_item_y"])
			if new_item.has_method("_ready"): new_item._ready()
			level_ref.add_child(new_item)
			vertical_held_item = new_item
