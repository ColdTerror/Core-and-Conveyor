# ==============================================================================
# Script: Building Classes/construction_site_building.gd
# Purpose: Dictates the blueprint state of a building under construction, accepting and storing items until 100% funded, transitioning to a buildable state where bots can build it, and spawning the finalized building while copying over metadata (upgrades, rotations, items in inventory).
# Dependencies: Inherits Building. Needs global Autoloads EconomyManager and ItemDatabase. Uses blueprint_size, size, and updates area shapes.
# Signals: Inherits signals from Building (such as inventory_changed, health_changed, destroyed).
# ==============================================================================
extends Building
class_name ConstructionSite

var target_building_scene: PackedScene
var required_items: Dictionary = {} 
var delivered_items: Dictionary = {} 

var is_ready_to_build: bool = false
var level_ref: Node2D
var blueprint_size: Vector2i = Vector2i(1, 1)


## Registers the parent level instance reference for the blueprint.
func setup(level_instance: Node2D):
	level_ref = level_instance


## Configures blueprint settings, target building scenes, resource costs, and dimensions.
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



## Determines if the blueprint currently accepts a specific item type for its construction.
func can_accept_item(item_res: ItemResource) -> bool:
	if is_ready_to_build: 
		return false
		
	var item_name = item_res.display_name 
	if not required_items.has(item_name): 
		return false
		
	var amount_needed = required_items[item_name]
	var amount_we_have = delivered_items.get(item_name, 0)
	
	return amount_we_have < amount_needed


## Deposits construction resources into the blueprint, updating the remaining bills.
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	var item_name = item_res.display_name
	
	if is_ready_to_build: return 0
	if not required_items.has(item_name): return 0
	
	var amount_needed = required_items[item_name]
	var amount_we_have = delivered_items.get(item_name, 0)
	var space_left = amount_needed - amount_we_have
	
	if space_left <= 0: return 0
	
	var amount_to_take = min(amount, space_left)
	delivered_items[item_name] = amount_we_have + amount_to_take
	EconomyManager.log_item_consumed(item_name, amount_to_take)
	inventory_changed.emit()
	
	queue_redraw()
	evaluate_requirements()
	return amount_to_take



## Validates the blueprint's current resources against required costs to trigger a buildable state.
func evaluate_requirements():
	var all_met = true
	
	for item_name in required_items.keys():
		var needed = required_items[item_name]
		var current = delivered_items.get(item_name, 0)
		
		if current < needed:
			all_met = false
			break
			
	if all_met and not is_ready_to_build:
		is_ready_to_build = true
		print("Site fully funded! Ready for builders.")
		
		queue_redraw() 
		
	if has_signal("inventory_changed"):
		inventory_changed.emit()



## Increments build progress and triggers completion when construction health is full.
func add_build_progress(amount: int):
	if not is_ready_to_build: return
	
	health += amount
	
	inventory_changed.emit()
	if has_signal("health_changed"):
		health_changed.emit(health, max_health)
	
	queue_redraw()
	
	if health >= max_health:
		_finish_construction()



## Spawns the completed building structure, transferring metadata, inventory, and positioning.
func _finish_construction():
	if not level_ref or not target_building_scene: return
	
	var new_building = target_building_scene.instantiate()

	var my_grid = occupied_tiles[0]
	
	# Use the official place_at function so the building calculates its 
	# center offsets and generates its own occupied_tiles perfectly!
	new_building.place_at(my_grid, level_ref.object_layer)
	
	level_ref.building_manager.add_child(new_building)
	
	if has_meta("blueprint_data"):
		var saved_data = get_meta("blueprint_data")
		
		if new_building.has_method("apply_upgrade_data"):
			new_building.apply_upgrade_data(saved_data)
			
		if saved_data.has("saved_inventory") and new_building.has_method("add_item"):
			var limbo_items = saved_data["saved_inventory"]
			
			for item_name in limbo_items.keys():
				var amount = limbo_items[item_name]
				var item_res = ItemDatabase.get_item(item_name)
				if item_res:
					new_building.add_item(item_res, amount)
			
	if new_building.has_method("setup"):
		new_building.setup(level_ref)
		
	level_ref.building_manager.register_finished_building(new_building, my_grid)
	
	if has_signal("destroyed"):
		destroyed.emit(self)
	queue_free()



## Returns structured current construction status and item deliveries for the inspect menu.
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



## Draws the blueprint's hologram boundaries and rising visual construction progress.
func _draw():
	var w = blueprint_size.x * 32.0
	var h = blueprint_size.y * 32.0
	var top_left = Vector2(-w / 2.0, -h / 2.0)
	var full_rect = Rect2(top_left, Vector2(w, h))

	if not is_ready_to_build:
		draw_rect(full_rect, Color(1.0, 0.2, 0.2, 0.15), true)
		
		var total_req = 0.0
		var total_del = 0.0
		for item in required_items.keys():
			total_req += required_items[item]
			total_del += delivered_items.get(item, 0)
			
		var delivery_pct = 0.0
		if total_req > 0:
			delivery_pct = float(total_del) / total_req
			
		if delivery_pct > 0:
			var fill_h = h * delivery_pct
			var fill_rect = Rect2(Vector2(top_left.x, top_left.y + h - fill_h), Vector2(w, fill_h))
			draw_rect(fill_rect, Color(1.0, 0.6, 0.0, 0.4), true) 

		draw_line(top_left, top_left + Vector2(w, h), Color(1.0, 0.2, 0.2, 0.4), 2.0)
		draw_line(top_left + Vector2(w, 0), top_left + Vector2(0, h), Color(1.0, 0.2, 0.2, 0.4), 2.0)
		draw_rect(full_rect, Color(1.0, 0.2, 0.2, 0.8), false, 2.0)

	else:
		draw_rect(full_rect, Color(1.0, 0.8, 0.2, 0.15), true)
		
		var build_pct = clamp(float(health) / float(max_health), 0.0, 1.0)
		
		if build_pct > 0:
			var fill_h = h * build_pct
			var fill_rect = Rect2(Vector2(top_left.x, top_left.y + h - fill_h), Vector2(w, fill_h))
			draw_rect(fill_rect, Color(0.2, 1.0, 0.2, 0.5), true)
			
		var border_color = Color(1.0, 0.8, 0.2, 0.8).lerp(Color(0.2, 1.0, 0.2, 0.8), build_pct)
		draw_rect(full_rect, border_color, false, 2.0)



## Serializes construction progress, resource delivery logs, and metadata for saving.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	data["building_name"] = building_name
	
	if target_building_scene:
		data["target_scene_path"] = target_building_scene.resource_path
	
	data["required_items"] = required_items
	data["delivered_items"] = delivered_items
	data["is_ready_to_build"] = is_ready_to_build
	
	data["size_x"] = size.x
	data["size_y"] = size.y
	
	if has_meta("blueprint_data"):
		data["blueprint_data"] = get_meta("blueprint_data")

	return data


## Deserializes saved construction, hologram sizes, and resource delivery logs.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	max_health = 100
	if "build_range" in self: build_range = 0
	if "corruption_range" in self: corruption_range = 0
	
	if data.has("building_name"):
		building_name = data["building_name"]
		
	if data.has("target_scene_path"):
		target_building_scene = load(data["target_scene_path"]) as PackedScene
		
	size = Vector2i(data.get("size_x", 1), data.get("size_y", 1))
	blueprint_size = size
	
	if data.has("required_items"):
		required_items = data["required_items"]
	if data.has("delivered_items"):
		delivered_items = data["delivered_items"]
		
	is_ready_to_build = data.get("is_ready_to_build", false)
	
	if data.has("blueprint_data"):
		set_meta("blueprint_data", data["blueprint_data"])
	
	inventory_changed.emit()
