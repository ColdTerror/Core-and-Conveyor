# ==============================================================================
# Script: Building Classes/harvester_building.gd
# Purpose: Class representing specialized harvester buildings (e.g. loggers, miners). Claims surrounding resource tiles in a circular scan radius, fires a laser beam at the closest matching claimed target to harvest it over intervals, stores items in an internal output buffer, pushes items out orthogonally to adjacent conveyors/routers/filters/stockpiles, handles visual range previews, and packages target coordinate vectors and buffer quantities into save/load states.
# Dependencies: Inherits Building. Relies on child beam line node (Line2D), global Autoloads EconomyManager, ResourceManager, expects a TileDataResource representing the target resource tile type, and expects a @export var generic_item_scene to spawn items visually.
# Signals: Inherits signals from Building (such as inventory_changed).
# ==============================================================================
extends Building
class_name HarvesterBuilding

@export_group("Settings")
@export var target_resource: TileDataResource 
@export var generic_item_scene: PackedScene 
@export var scan_radius: int = 4
@export var harvest_damage: int = 2
@export var work_interval: float = 1.0

@export_group("Inventory")
@export var buffer_capacity: int = 10 
var stored_amount: int = 0

@onready var beam_line: Line2D = $Line2D

var level_ref: Node2D
var work_timer: float = 0.0
var current_target: Vector2i = Vector2i.MAX

var show_range_overlay := false:
	set(value):
		show_range_overlay = value
		queue_redraw()

const TILE_SIZE = 32

## Configures the harvester with level node references.
func setup(level_instance: Node2D):
	level_ref = level_instance


## Registers the harvester structure as an active economic production source.
func _ready():
	EconomyManager.register_source(self, false)
	super()
	health = max_health - 10



## Emits item consumption events for any stored buffer quantities upon structure destruction.
func die():
	if stored_amount > 0 and target_resource and target_resource.item_drop:
		EconomyManager.log_item_consumed(target_resource.item_drop.display_name, stored_amount)
		
	stored_amount = 0
	super()


## Discards laser targets when removed from tree, and unregisters the building.
func _exit_tree():
	EconomyManager.unregister_source(self)
	_clear_target_reservation()



## Draws the circular scan range visual overlay bounds when previewed, highlighted, or selected.
func _draw():
	if (show_range_overlay or is_selected) and level_ref:
		var center_tile = level_ref.object_layer.local_to_map(global_position)
		var top_left_tile = center_tile - (size / 2)
		var range_top_left = top_left_tile - Vector2i(scan_radius, scan_radius)
		var total_width = size.x + (scan_radius * 2)
		var total_height = size.y + (scan_radius * 2)
		
		var world_pos = level_ref.object_layer.map_to_local(range_top_left)
		world_pos -= Vector2(TILE_SIZE, TILE_SIZE) / 2.0
		
		var local_pos = to_local(world_pos)
		var size_px = Vector2(total_width, total_height) * TILE_SIZE
		
		var rect = Rect2(local_pos, size_px)
		var fill_alpha = 0.3 if is_ghost else 0.15
		var border_alpha = 1.0 if is_ghost else 0.6
		draw_rect(rect, Color(0.163, 0.162, 0.175, fill_alpha), true)
		draw_rect(rect, Color(0.0, 0.0, 0.0, border_alpha), false, 2.0)



## Configures the placement ghost state and forces scan range visibility overlays.
func set_ghost(enabled: bool):
	super.set_ghost(enabled)
	show_range_overlay = enabled


## Activates the circular scan range overlay on mouse enter.
func _on_mouse_entered():
	super._on_mouse_entered()
	if not get_node("Area2D").monitoring: return 
	show_range_overlay = true


## Deactivates the circular scan range overlay on mouse exit.
func _on_mouse_exited():
	super._on_mouse_exited()
	if not get_node("Area2D").monitoring: return 
	show_range_overlay = false



## Executes the periodic harvesting loop and tries to dispense stored output buffers.
func building_tick(delta: float) -> void:
	if not level_ref or not target_resource: return
	
	if stored_amount > 0:
		_try_output_item()
	
	if stored_amount + harvest_damage > buffer_capacity:
		if beam_line: beam_line.clear_points()
		return
		
	work_timer -= delta
	
	if current_target != Vector2i.MAX:
		_draw_beam(current_target)
	else:
		if beam_line: beam_line.clear_points()

	if work_timer <= 0:
		work_timer = work_interval
		_perform_harvest()



## Executes physical resource damage queries against the currently locked target.
func _perform_harvest():
	if not _is_valid_target(current_target):
		_clear_target_reservation()
		current_target = _find_nearest_target()
		
		if current_target != Vector2i.MAX:
			level_ref.active_grid_objects[current_target]["reserved_by"] = self
	
	if current_target != Vector2i.MAX:
		var info = level_ref.active_grid_objects[current_target]
		var actual_harvested = ResourceManager.request_harvest(current_target, info, harvest_damage)
		
		if actual_harvested > 0:
			stored_amount += actual_harvested
			inventory_changed.emit()
			if target_resource and target_resource.item_drop:
				var item_name = target_resource.item_drop.display_name
				EconomyManager.log_item_produced(item_name, actual_harvested)



## Scans surrounding territory coordinates to identify the closest valid target.
func _find_nearest_target() -> Vector2i:
	var center_tile = level_ref.object_layer.local_to_map(global_position)
	var top_left_tile = center_tile - (size / 2)
	
	var start_x = top_left_tile.x - scan_radius
	var end_x = top_left_tile.x + size.x + scan_radius - 1
	var start_y = top_left_tile.y - scan_radius
	var end_y = top_left_tile.y + size.y + scan_radius - 1
	
	var best_pos = Vector2i.MAX
	var min_dist = 99999.0
	
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var check_pos = Vector2i(x, y)
			if _is_valid_target(check_pos):
				var dist = center_tile.distance_squared_to(check_pos)
				if dist < min_dist:
					min_dist = dist
					best_pos = check_pos
					
	return best_pos



## Verifies if the target grid position holds alive resource nodes matching the target type.
func _is_valid_target(pos: Vector2i) -> bool:
	if pos == Vector2i.MAX: return false
	if not level_ref.active_grid_objects.has(pos): return false
	
	var info = level_ref.active_grid_objects[pos]
	if info["health"] <= 0: return false
	if info["data"] != target_resource: return false
	
	# If another bot or harvester is already locked on, ignore it
	if info.has("reserved_by") and is_instance_valid(info["reserved_by"]) and info["reserved_by"] != self:
		return false
		
	return true



## Configures Line2D points to render a harvesting laser beam leading to target nodes.
func _draw_beam(grid_pos: Vector2i):
	if not beam_line: return
	var target_world = level_ref.object_layer.map_to_local(grid_pos)
	var target_local = to_local(target_world)
	beam_line.clear_points()
	beam_line.add_point(Vector2.ZERO)
	beam_line.add_point(target_local)



## Scans orthogonal neighbors to find matching input entries for buffered items.
func _try_output_item():
	if not level_ref: return
	var manager = level_ref.building_manager

	for my_tile in occupied_tiles:
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			if occupied_tiles.has(target_pos): continue
			
			if manager.occupied_tiles.has(target_pos):
				var neighbor = manager.occupied_tiles[target_pos]
				
				if neighbor.has_method("accept_item_node"):
					var can_output = false
					
					if neighbor is RouterBuilding:
						can_output = true
						
					elif neighbor is ConveyorBuilding or neighbor is FilterBuilding:
						if neighbor.direction == offset:
							can_output = true
							
					else:
						can_output = true
							
					if can_output:
						if _spawn_item_into_conveyor(neighbor, my_tile, offset):
							return



## Instantiates visual item nodes, snaps positions, and deposits them into accepting neighbors.
func _spawn_item_into_conveyor(receiver: Node, source_tile: Vector2i, direction_offset: Vector2i) -> bool:
	if not generic_item_scene or not target_resource.item_drop: return false
	
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = target_resource.item_drop
	
	# PERFECT POSITION SNAPPING
	var tile_center_px = level_ref.object_layer.map_to_local(source_tile)
	var edge_px = tile_center_px + (Vector2(direction_offset) * 16.0)
	new_item_node.global_position = edge_px
	
	if new_item_node.has_method("_ready"): new_item_node._ready() 
	
	if receiver.accept_item_node(new_item_node):
		stored_amount -= 1
		inventory_changed.emit()
		return true
		
	else:
		new_item_node.queue_free()
		return false







## Releases current target lock reservations on grid coordinates.
func _clear_target_reservation():
	if current_target != Vector2i.MAX and level_ref and level_ref.active_grid_objects.has(current_target):
		var info = level_ref.active_grid_objects[current_target]
		if info.has("reserved_by") and info["reserved_by"] == self:
			info["reserved_by"] = null



## Summarizes buffered inventories as simple string-to-quantity assets for upgrades.
func get_economy_assets() -> Dictionary:
	var assets = {}
	if stored_amount > 0 and target_resource and target_resource.item_drop:
		assets[target_resource.item_drop.display_name] = stored_amount
	return assets



## Restores saved or carried resource materials back into output buffers during upgrade.
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	if not target_resource or not target_resource.item_drop: return 0
	if item_res != target_resource.item_drop: return 0
	
	var space_left = buffer_capacity - stored_amount
	if space_left <= 0: return 0
	
	var amount_to_take = min(amount, space_left)
	stored_amount += amount_to_take
	inventory_changed.emit()
	
	return amount_to_take



## Returns raw item-drop capacity values to update info panels.
func get_inventory_info() -> Dictionary:
	if target_resource and target_resource.item_drop and stored_amount > 0:
		return { target_resource.item_drop: stored_amount } 
	return {}



## Packs stored buffers, work tickers, and active target vectors into save dictionaries.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	data["stored_amount"] = stored_amount
	data["work_timer"] = work_timer
	data["current_target"] = var_to_str(current_target)
	
	return data


## Restores stored buffers, work timers, and locks laser beams back onto saved target coordinates.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	stored_amount = data.get("stored_amount", 0)
	work_timer = data.get("work_timer", 0.0)
	
	if data.has("current_target"):
		current_target = str_to_var(data["current_target"])
	else:
		current_target = Vector2i.MAX
		
	inventory_changed.emit()
