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

var _claimed_tiles: Array[Vector2i] = []

# --- SETUP ---
func setup(level_instance: Node2D):
	level_ref = level_instance
	_claim_territory()
	

func _ready():
	EconomyManager.register_source(self, false)
	super()
	health = max_health - 10
	
func die():
	# Log the raw resources that burn down with the harvester
	if stored_amount > 0 and target_resource and target_resource.item_drop:
		EconomyManager.log_item_consumed(target_resource.item_drop.display_name, stored_amount)
		
	stored_amount = 0
	super() # Call the base class die() function!
	
func _exit_tree():
	_clear_target_reservation() # Let go of whatever tree we were shooting at
	_unclaim_territory()        # Take down the invisible fence
	
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
		_clear_target_reservation() # Let go of our old target if it died!
		current_target = _find_nearest_target()
		
		# Claim the new target so overlapping buildings don't steal it!
		if current_target != Vector2i.MAX:
			level_ref.active_grid_objects[current_target]["reserved_by"] = self
	
	if current_target != Vector2i.MAX:
		var info = level_ref.active_grid_objects[current_target]
		var actual_harvested = ResourceManager.request_harvest(current_target, info, harvest_damage)
		
		# (Optional safety measure: only add if we actually broke something)
		if actual_harvested > 0:
			stored_amount += actual_harvested
			inventory_changed.emit()
			if target_resource and target_resource.item_drop:
				var item_name = target_resource.item_drop.display_name
				EconomyManager.log_item_produced(item_name, actual_harvested)

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
	
	# --- NEW: OVERLAP CHECK ---
	# If another bot OR another harvester is already swinging at this tree, ignore it!
	if info.has("reserved_by") and is_instance_valid(info["reserved_by"]) and info["reserved_by"] != self:
		return false
		
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
				
				# 1. Ensure the neighbor can physically accept items
				if neighbor.has_method("accept_item_node"):
					var can_output = false
					
					# --- Catch the Router FIRST so it bypasses the Conveyor rules! ---
					if neighbor is RouterBuilding:
						can_output = true
						
					# 2. STRICT CHECK: Belts and Filters must point exactly away!
					elif neighbor is ConveyorBuilding or neighbor is FilterBuilding:
						if neighbor.direction == offset:
							can_output = true
							
					# 3. ANYTHING ELSE: Magic omnidirectional bypass!
					else:
						can_output = true
							
					# 4. If valid, attempt the transfer
					if can_output:
						if _spawn_item_into_conveyor(neighbor, my_tile, offset):
							return # Success! Stop trying other neighbors this tick.

# --- FIXED: Accepts ANY node that has accept_item_node! ---
func _spawn_item_into_conveyor(receiver: Node, source_tile: Vector2i, direction_offset: Vector2i) -> bool:
	if not generic_item_scene or not target_resource.item_drop: return false
	
	# 1. Create the Visual Node
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = target_resource.item_drop
	
	# ========================================
	# FIXED: PERFECT POSITION SNAPPING
	# ========================================
	# 1. Find the exact pixel center of the specific 1x1 tile the item is leaving
	var tile_center_px = level_ref.object_layer.map_to_local(source_tile)
	
	# 2. Push the item exactly 16 pixels (half a tile) in the orthogonal direction
	var edge_px = tile_center_px + (Vector2(direction_offset) * 16.0)
	
	new_item_node.global_position = edge_px
	# ========================================
	
	
	
	if new_item_node.has_method("_ready"): new_item_node._ready() 
	
	# 2. Try to hand it to the Receiver (Belt, Router, Filter)
	if receiver.accept_item_node(new_item_node):
		# Success!
		stored_amount -= 1
		inventory_changed.emit()
		
		return true # RETURN SUCCESS
		
	else:
		# Receiver was full or refused, delete the temp node
		new_item_node.queue_free()
		return false # RETURN FAILURE

# ==========================================
# TERRITORY & DIBS SYSTEM
# ==========================================
func _claim_territory():
	if not level_ref or not level_ref.object_layer: return
	
	var center_tile = level_ref.object_layer.local_to_map(global_position)
	var top_left_tile = center_tile - (size / 2)
	
	var start_x = top_left_tile.x - scan_radius
	var end_x = top_left_tile.x + size.x + scan_radius - 1
	var start_y = top_left_tile.y - scan_radius
	var end_y = top_left_tile.y + size.y + scan_radius - 1
	
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var tile = Vector2i(x, y)
			_claimed_tiles.append(tile)  # ← Cache it
			if level_ref.active_grid_objects.has(tile):
				var info = level_ref.active_grid_objects[tile]
				info["harvester_claim_count"] = info.get("harvester_claim_count", 0) + 1

func _unclaim_territory():
	# Use the cached list instead of recalculating
	for tile in _claimed_tiles:
		if level_ref and level_ref.active_grid_objects.has(tile):
			var info = level_ref.active_grid_objects[tile]
			if info.has("harvester_claim_count"):
				info["harvester_claim_count"] -= 1
				if info["harvester_claim_count"] <= 0:
					info.erase("harvester_claim_count")
	
	_claimed_tiles.clear()

func _clear_target_reservation():
	if current_target != Vector2i.MAX and level_ref and level_ref.active_grid_objects.has(current_target):
		var info = level_ref.active_grid_objects[current_target]
		if info.has("reserved_by") and info["reserved_by"] == self:
			info["reserved_by"] = null

# ==========================================
# HYBRID UPGRADE PIPELINE (Duck Typing)
# ==========================================

# 1. Pack the backpack before upgrading
func get_economy_assets() -> Dictionary:
	var assets = {}
	if stored_amount > 0 and target_resource and target_resource.item_drop:
		assets[target_resource.item_drop.display_name] = stored_amount
	return assets

# 2. Unpack the backpack into the new Mk II Harvester
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	# Filter: Reject if it's not the exact item this harvester produces
	if not target_resource or not target_resource.item_drop: return 0
	if item_res != target_resource.item_drop: return 0
	
	var space_left = buffer_capacity - stored_amount
	if space_left <= 0: return 0
	
	var amount_to_take = min(amount, space_left)
	stored_amount += amount_to_take
	inventory_changed.emit()
	
	return amount_to_take
	
func get_inventory_info() -> Dictionary:
	# Make sure the tile actually has an item_drop assigned
	if target_resource and target_resource.item_drop and stored_amount > 0:
		# Hand the UI the item_drop instead of the target_resource!
		return { target_resource.item_drop: stored_amount } 
	return {}
	
# ==========================================
# SAVE / LOAD SYSTEM (Harvester)
# ==========================================
func get_save_data() -> Dictionary:
	# 1. Grab the base stats (health, building_name)
	var data = super.get_save_data()
	
	# 2. Save the simple variables
	data["stored_amount"] = stored_amount
	data["work_timer"] = work_timer
	
	# 3. Save the exact tree/rock it was shooting at
	data["current_target"] = var_to_str(current_target)
	
	return data

func load_save_data(data: Dictionary):
	# 1. Restore the base stats
	super.load_save_data(data)
	
	# 2. Restore the inventory count
	stored_amount = data.get("stored_amount", 0)
	work_timer = data.get("work_timer", 0.0)
	
	# 3. Restore the target so the laser beam doesn't disconnect!
	if data.has("current_target"):
		current_target = str_to_var(data["current_target"])
	else:
		current_target = Vector2i.MAX
		
	# Tell the UI to update the capacity bar!
	inventory_changed.emit()
	
	
