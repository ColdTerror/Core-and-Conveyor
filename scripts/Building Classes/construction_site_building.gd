extends Building
class_name ConstructionSite

# --- INTERNAL STATE (Passed dynamically!) ---
var target_building_scene: PackedScene
var required_items: Dictionary = {} 
var delivered_items: Dictionary = {} 

var is_ready_to_build: bool = false
var level_ref: Node2D
var blueprint_size: Vector2i = Vector2i(1, 1)

# ==========================================
# 1. THE DYNAMIC SETUP
# ==========================================
func setup_blueprint(level_instance: Node2D, target_scene: PackedScene, costs: Dictionary, b_size: Vector2i, target_name: String = ""):
	level_ref = level_instance
	target_building_scene = target_scene
	required_items = costs.duplicate()
	
	blueprint_size = b_size
	size = b_size # Critical: Updates the base Building class size!
	
	# Instantly stretch the collision and hover boxes!
	var footprint_px = Vector2(size.x * 32.0, size.y * 32.0)
	_update_collision(footprint_px)
	
	if target_name != "":
		building_name = "Building: " + target_name
	else:
		building_name = "Construction Site"
		
	health = 0 
	max_health = 100 
	
	if "build_range" in self: build_range = 0
	if "corruption_range" in self: corruption_range = 0
	
	queue_redraw()

# ==========================================
# THE UNIFIED DOOR
# ==========================================
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	var item_name = item_res.display_name # <-- TRANSLATE RESOURCE TO STRING
	
	if is_ready_to_build: return 0
	if not required_items.has(item_name): return 0
	
	var amount_needed = required_items[item_name]
	var amount_we_have = delivered_items.get(item_name, 0)
	var space_left = amount_needed - amount_we_have
	
	if space_left <= 0: return 0
	
	var amount_to_take = min(amount, space_left)
	delivered_items[item_name] = amount_we_have + amount_to_take # Save it under the String!
	inventory_changed.emit()
	
	queue_redraw()
	_check_if_fully_stocked()
	return amount_to_take

func _check_if_fully_stocked():
	for req_name in required_items.keys():
		var amount_we_have = delivered_items.get(req_name, 0)
		if amount_we_have < required_items[req_name]:
			return # Still missing something
			
	is_ready_to_build = true

# ==========================================
# NEW: DEDICATED BUILD LOGIC
# ==========================================
func add_build_progress(amount: int):
	if not is_ready_to_build: return
	
	health += amount
	
	inventory_changed.emit()
	if has_signal("health_changed"):
		health_changed.emit(health, max_health)
	
	queue_redraw()
	
	if health >= max_health:
		_finish_construction()

func _finish_construction():
	if not level_ref or not target_building_scene: return
	
	# 1. Spawn the real building
	var new_building = target_building_scene.instantiate()
	if new_building.has_method("setup"):
		new_building.setup(level_ref)
	
	
	# 2. Get our exact grid coordinate before we delete ourselves
	var my_grid = occupied_tiles[0]
	
	# --- PROPER PLACEMENT ---
	# Use the official place_at function so the building calculates its 
	# center offsets and generates its own occupied_tiles perfectly!
	new_building.place_at(my_grid, level_ref.object_layer)
	# ---------------------------------
	
	level_ref.building_manager.add_child(new_building)
	
	# 3. Register the new building into the freshly emptied slots
	level_ref.building_manager.register_finished_building(new_building, my_grid)
	
	# 4. Safely destroy the blueprint node!
	if has_signal("destroyed"):
		destroyed.emit(self)
	queue_free()

# ==========================================
# UI HELPERS
# ==========================================
func get_inventory_info() -> Dictionary:
	var info = {}
	if is_ready_to_build:
		info["Status"] = "Ready to Build!"
		info["Progress"] = "%d%%" % [(float(health) / max_health) * 100]
	else:
		info["Status"] = "Waiting for Materials"
		for item_name in required_items.keys():
			var needed = required_items[item_name]
			var have = delivered_items.get(item_name, 0)
			info[item_name] = "%d / %d" % [have, needed]
			
	return info
	
# ==========================================
# VISUALS
# ==========================================
# ==========================================
# VISUALS
# ==========================================
func _draw():
	var w = blueprint_size.x * 32.0
	var h = blueprint_size.y * 32.0
	var top_left = Vector2(-w / 2.0, -h / 2.0)
	var full_rect = Rect2(top_left, Vector2(w, h))

	if not is_ready_to_build:
		# --- PHASE 1: WAITING FOR MATERIALS ---
		
		# 1. Base hologram (faint red)
		draw_rect(full_rect, Color(1.0, 0.2, 0.2, 0.15), true)
		
		# 2. Calculate Delivery Percentage
		var total_req = 0.0
		var total_del = 0.0
		for item in required_items.keys():
			total_req += required_items[item]
			total_del += delivered_items.get(item, 0)
			
		var delivery_pct = 0.0
		if total_req > 0:
			delivery_pct = float(total_del) / total_req
			
		# 3. Draw Delivery Progress (Orange fill rising from bottom)
		if delivery_pct > 0:
			var fill_h = h * delivery_pct
			var fill_rect = Rect2(Vector2(top_left.x, top_left.y + h - fill_h), Vector2(w, fill_h))
			draw_rect(fill_rect, Color(1.0, 0.6, 0.0, 0.4), true) 

		# 4. Draw the "X" and border
		draw_line(top_left, top_left + Vector2(w, h), Color(1.0, 0.2, 0.2, 0.4), 2.0)
		draw_line(top_left + Vector2(w, 0), top_left + Vector2(0, h), Color(1.0, 0.2, 0.2, 0.4), 2.0)
		draw_rect(full_rect, Color(1.0, 0.2, 0.2, 0.8), false, 2.0)

	else:
		# --- PHASE 2: ACTIVELY BEING BUILT ---
		
		# 1. Base background (faint yellow to show it's stocked)
		draw_rect(full_rect, Color(1.0, 0.8, 0.2, 0.15), true)
		
		# 2. Calculate Build Percentage
		var build_pct = clamp(float(health) / float(max_health), 0.0, 1.0)
		
		# 3. Draw Build Progress (Green fill rising from bottom)
		if build_pct > 0:
			var fill_h = h * build_pct
			var fill_rect = Rect2(Vector2(top_left.x, top_left.y + h - fill_h), Vector2(w, fill_h))
			draw_rect(fill_rect, Color(0.2, 1.0, 0.2, 0.5), true)
			
		# 4. Draw border (Transitions from Yellow to Green as it builds!)
		var border_color = Color(1.0, 0.8, 0.2, 0.8).lerp(Color(0.2, 1.0, 0.2, 0.8), build_pct)
		draw_rect(full_rect, border_color, false, 2.0)

# ==========================================
# SAVE / LOAD SYSTEM (Construction Site)
# ==========================================
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	data["building_name"] = building_name
	
	# 1. Save what we are building
	if target_building_scene:
		data["target_scene_path"] = target_building_scene.resource_path
	
	# 2. Save the string dictionaries directly! (No translation needed)
	data["required_items"] = required_items
	data["delivered_items"] = delivered_items
	data["is_ready_to_build"] = is_ready_to_build
	
	# 3. Save size (for footprint calculations)
	data["size_x"] = size.x
	data["size_y"] = size.y

	
	return data

func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	if data.has("building_name"):
		building_name = data["building_name"]
		
	# 1. Restore the blueprint
	if data.has("target_scene_path"):
		target_building_scene = load(data["target_scene_path"]) as PackedScene
		
	size = Vector2i(data.get("size_x", 1), data.get("size_y", 1))
	blueprint_size = size # Keep the hologram visual in sync!
	
	# 2. Restore the dictionaries directly
	
	if data.has("required_items"):
		required_items = data["required_items"]
	if data.has("delivered_items"):
		delivered_items = data["delivered_items"]
		
	is_ready_to_build = data.get("is_ready_to_build", false)
	
				
	# Tell the UI to update the progress bar!
	inventory_changed.emit()
