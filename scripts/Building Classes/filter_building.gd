# ==============================================================================
# Script: Building Classes/filter_building.gd
# Purpose: Class representing individual Filter Belt structures. Extends RouterBuilding but restricts item entry exclusively to the back side, matches items against a selected filter option or split mode, routes filtered items to the left/right sides alternately and non-matching items forward (or vice versa), and handles filter index saving/loading.
# Dependencies: Inherits RouterBuilding. Relies on parent class attributes, global Autoload ItemDatabase, and manages direction and rotation properties.
# Signals: None.
# ==============================================================================
extends RouterBuilding
class_name FilterBuilding

var filter_options: Array[String] = ["None"] 
var current_filter_index: int = 0
var is_split_mode: bool = true 
var side_toggle: int = 0

# True orientation is stored because the base class temporarily 
# changes 'direction' to slide items sideways during transfer.
var facing_direction: Vector2i = Vector2i.RIGHT 


## Initializes filter structures, populating item options dynamically from the database.
func _ready():
	super()
	for item_name in ItemDatabase.items.keys():
		if not filter_options.has(item_name):
			filter_options.append(item_name)



## Sets up the filter's true orientation and rotation.
func setup(level_instance: Node2D, dir: Vector2i):
	level_ref = level_instance
	facing_direction = dir if dir != Vector2i.ZERO else Vector2i.RIGHT
	direction = facing_direction
	rotation = Vector2(facing_direction).angle()



## Restricts item receipt strictly to the rear entry side of the filter structure.
func accept_item_node(item_node: Node2D, source_belt: ConveyorBuilding = null) -> bool:
	if source_belt:
		var manager = level_ref.building_manager
		var my_grid = manager.object_layer.local_to_map(global_position)
		var source_grid = manager.object_layer.local_to_map(source_belt.global_position)
		
		# Calculate the tile exactly 1 space behind the filter
		var expected_input_grid = my_grid - facing_direction
		
		# If the belt is NOT at the back door, reject the item!
		if source_grid != expected_input_grid:
			return false 
			
	return super.accept_item_node(item_node, source_belt)



## Cycles the current item filter selection forward to the next index.
func cycle_filter():
	current_filter_index = (current_filter_index + 1) % filter_options.size()


## Toggles the split mode mapping between sorting filtered items sideways or forward.
func toggle_filter_mode():
	is_split_mode = not is_split_mode



## Evaluates held item matching status to compute appropriate output directions.
func _try_route():
	if not held_item or not "item_data" in held_item: return
	
	var manager = level_ref.building_manager
	var my_grid = manager.object_layer.local_to_map(global_position)
	
	var current_filter = filter_options[current_filter_index]
	var item_name = held_item.item_data.display_name
	var matches_filter = (item_name == current_filter)
	
	var forward_dir = facing_direction
	var right_dir = Vector2i(-facing_direction.y, facing_direction.x)
	var left_dir = Vector2i(facing_direction.y, -facing_direction.x)
	
	var target_dirs = []
	var should_go_to_sides = false
	
	if current_filter == "None":
		target_dirs = [forward_dir]
	else:
		should_go_to_sides = (matches_filter == is_split_mode)
		
		if should_go_to_sides:
			if side_toggle == 0:
				target_dirs = [right_dir, left_dir]
			else:
				target_dirs = [left_dir, right_dir]
		else:
			target_dirs = [forward_dir]

	for offset in target_dirs:
		var target_pos = my_grid + offset
		var can_push = false
		
		if manager.occupied_tiles.has(target_pos):
			var neighbor = manager.occupied_tiles[target_pos]
			
			if neighbor is ConveyorBuilding and not neighbor is RouterBuilding:
				if neighbor.direction == offset and (neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed)):
					can_push = true
					
			elif neighbor is RouterBuilding:
				if neighbor.held_item == null or (neighbor.is_moving_to_edge and not neighbor.is_jammed):
					can_push = true
					
			elif neighbor.has_method("can_accept_item") and "item_data" in held_item:
				if neighbor.can_accept_item(held_item.item_data):
					can_push = true

		if can_push:
			if should_go_to_sides and offset == target_dirs[0]:
				side_toggle = 1 if side_toggle == 0 else 0
				
			direction = offset 
			is_moving_to_edge = true 
			return
			
	push_cooldown = 0.1



## Packs current filter item names, toggle states, and facing directions for save files.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	data["facing_direction"] = var_to_str(facing_direction)
	data["active_filter_name"] = filter_options[current_filter_index]
	data["is_split_mode"] = is_split_mode
	data["side_toggle"] = side_toggle
	
	return data


## Restores saved filter item names, toggle states, and true orientations.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	if data.has("facing_direction"):
		facing_direction = str_to_var(data["facing_direction"])
	else:
		facing_direction = direction
		
	direction = facing_direction
	
	is_split_mode = data.get("is_split_mode", true)
	side_toggle = data.get("side_toggle", 0)
	
	var saved_filter = data.get("active_filter_name", "None")
	var found_index = filter_options.find(saved_filter)
	
	if found_index != -1:
		current_filter_index = found_index
	else:
		current_filter_index = 0
