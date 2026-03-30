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
	
	queue_redraw()
	
	queue_redraw() # Tell Godot to run the _draw() function!




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
	
	_check_if_fully_stocked()
	return amount_to_take

func _check_if_fully_stocked():
	for req_name in required_items.keys():
		var amount_we_have = delivered_items.get(req_name, 0)
		if amount_we_have < required_items[req_name]:
			return # Still missing something
			
	is_ready_to_build = true
	print("Construction Site fully stocked! Waiting for Builder Bot.")

# ==========================================
# NEW: DEDICATED BUILD LOGIC
# ==========================================
func add_build_progress(amount: int):
	if not is_ready_to_build: return
	
	health += amount
	
	inventory_changed.emit()
	if has_signal("health_changed"):
		health_changed.emit(health, max_health)
	
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
	
	# --- CLEANUP FIRST ---
	if has_signal("destroyed"):
		destroyed.emit(self)
	# ------------------------------
	
	# --- PROPER PLACEMENT ---
	# Use the official place_at function so the building calculates its 
	# center offsets and generates its own occupied_tiles perfectly!
	new_building.place_at(my_grid, level_ref.object_layer)
	# ---------------------------------
	
	level_ref.object_layer.add_child(new_building)
	
	# 3. Register the new building into the freshly emptied slots
	level_ref.building_manager.register_finished_building(new_building, my_grid)
	
	# 4. Safely destroy the blueprint node!
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
func _draw():
	var w = blueprint_size.x * 32.0
	var h = blueprint_size.y * 32.0
	
	# THE FIX: To center a drawing, you start exactly half the width left, and half the height up.
	var top_left = Vector2(-w / 2.0, -h / 2.0)
	
	var rect = Rect2(top_left, Vector2(w, h))

	# 1. Faint red fill (looks like a hologram)
	draw_rect(rect, Color(1.0, 0.2, 0.2, 0.15), true)
	
	# 2. Solid red border
	draw_rect(rect, Color(1.0, 0.2, 0.2, 0.8), false, 2.0)
	
	# 3. Draw an "X" through it
	draw_line(top_left, top_left + Vector2(w, h), Color(1.0, 0.2, 0.2, 0.4), 2.0)
	draw_line(top_left + Vector2(w, 0), top_left + Vector2(0, h), Color(1.0, 0.2, 0.2, 0.4), 2.0)
