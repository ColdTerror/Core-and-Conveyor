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

# Visuals
@onready var beam_line: Line2D = $Line2D

var level_ref: Node2D
var work_timer: float = 0.0
var current_target: Vector2i = Vector2i.MAX

# Range Visuals
var show_range_overlay := false:
	set(value):
		show_range_overlay = value
		queue_redraw()

const TILE_SIZE = 32

# Implement Consumption Logic
func consume_resources(remaining_bill: Dictionary):
	if not target_resource or not target_resource.item_drop: return
	
	var res_name = target_resource.item_drop.display_name
	
	if remaining_bill.has(res_name):
		var amount_needed = remaining_bill[res_name]
		var amount_we_have = stored_amount
		
		var amount_to_take = min(amount_needed, amount_we_have)
		
		# A. Remove from Internal Buffer
		stored_amount -= amount_to_take
		
		# B. Update the Bill
		remaining_bill[res_name] -= amount_to_take
		if remaining_bill[res_name] <= 0:
			remaining_bill.erase(res_name)
			
		inventory_changed.emit()

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance

# --- DRAWING THE RANGE ---
func _draw():
	if show_range_overlay and level_ref:
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
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.2), true)
		draw_rect(rect, Color(0.2, 1.0, 0.2, 0.5), false, 2.0)

# --- OVERRIDES FOR VISIBILITY ---
func set_ghost(enabled: bool):
	super.set_ghost(enabled)
	show_range_overlay = enabled

func _on_mouse_entered():
	super._on_mouse_entered()
	if not get_node("Area2D").monitoring: return 
	show_range_overlay = true

func _on_mouse_exited():
	super._on_mouse_exited()
	if not get_node("Area2D").monitoring: return 
	show_range_overlay = false

# --- MAIN LOOP ---
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

func _perform_harvest():
	if not _is_valid_target(current_target):
		current_target = _find_nearest_target()
	
	if current_target != Vector2i.MAX:
		var info = level_ref.active_grid_objects[current_target]
		ResourceManager.request_harvest(current_target, info, harvest_damage)
		
		stored_amount += harvest_damage
		
		
		
		inventory_changed.emit()

# --- TARGET FINDING ---
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

func _is_valid_target(pos: Vector2i) -> bool:
	if pos == Vector2i.MAX: return false
	if not level_ref.active_grid_objects.has(pos): return false
	var info = level_ref.active_grid_objects[pos]
	if info["health"] <= 0: return false
	if info["data"] != target_resource: return false
	return true

func _draw_beam(grid_pos: Vector2i):
	if not beam_line: return
	var target_world = level_ref.object_layer.map_to_local(grid_pos)
	var target_local = to_local(target_world)
	beam_line.clear_points()
	beam_line.add_point(Vector2.ZERO)
	beam_line.add_point(target_local)

# =================================================================
# NEW: OUTPUT LOGIC (Unified with Processor/Stockpile)
# =================================================================

func _try_output_item():
	if not level_ref: return
	var manager = level_ref.building_manager

	# Loop through all tiles we occupy
	for my_tile in occupied_tiles:
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			# Don't output into ourself
			if occupied_tiles.has(target_pos): continue
			
			# Check BuildingManager for neighbors
			if manager.occupied_tiles.has(target_pos):
				var neighbor = manager.occupied_tiles[target_pos]
				
				# Is it a Conveyor?
				if neighbor is ConveyorBuilding:
					# Only output if the belt is pointing exactly AWAY from us
					if neighbor.direction == offset:
						# Try to spawn. This function returns TRUE if successful
						if _spawn_item_into_conveyor(neighbor):
							return # Success! Stop trying other belts this tick.
# Now returns BOOL (True = Success, False = Failed)
func _spawn_item_into_conveyor(conveyor: ConveyorBuilding) -> bool:
	if not generic_item_scene or not target_resource.item_drop: return false
	
	# 1. Create the Visual Node
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = target_resource.item_drop
	
	# Position the item at the harvester's location before handoff
	new_item_node.global_position = global_position
	
	if new_item_node.has_method("_ready"): new_item_node._ready() 
	
	# 2. Try to hand it to the Conveyor
	if conveyor.accept_item_node(new_item_node):
		# Success!
		stored_amount -= 1
		inventory_changed.emit()
		
		return true # RETURN SUCCESS
		
	else:
		# Belt was full or refused, delete the temp node
		new_item_node.queue_free()
		return false # RETURN FAILURE

# =================================================================

# =================================================================
# ECONOMY ASSETS (Called when destroyed)
# =================================================================
func get_economy_assets() -> Dictionary:
	var assets = {}
	if target_resource and target_resource.item_drop and stored_amount > 0:
		assets[target_resource.item_drop.display_name] = stored_amount
	return assets


func get_inventory_info() -> Dictionary:
	# Make sure the tile actually has an item_drop assigned
	if target_resource and target_resource.item_drop and stored_amount > 0:
		# Hand the UI the item_drop instead of the target_resource!
		return { target_resource.item_drop: stored_amount } 
	return {}
	
	
