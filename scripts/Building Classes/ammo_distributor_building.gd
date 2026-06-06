# ==============================================================================
# Script: Building Classes/ammo_distributor_building.gd
# Purpose: Defensive logistical building that accepts mixed ammo types from belts
#          or worker bots and distributes them to nearby towers in its range.
# Dependencies: Inherits Building. Requires a reference to Level.
# Signals: Inherits signals from Building (such as inventory_changed).
# ==============================================================================
class_name AmmoDistributorBuilding
extends Building

var level_ref: Node2D
var inventory: Dictionary = {} # ItemResource -> int

@export var distribution_range: float = 160.0 # 5 tiles
@export var transfer_interval: float = 1.0 # 1.0 second
var check_timer: float = 0.0

var show_range_overlay := false:
	set(val):
		show_range_overlay = val
		queue_redraw()



## Configures the level reference and enables range drawing hooks on selection.
func setup(level_instance: Node2D):
	level_ref = level_instance

## Increments transfer timers and triggers range redraws.
func _physics_process(delta):
	if is_ghost:
		return
		
	check_timer += delta
	if check_timer >= transfer_interval:
		check_timer = 0.0
		_distribute_ammo()



## Checks whether this distributor accepts items entering through the specified tile.
func accepts_item_at(_tile: Vector2i) -> bool:
	return true



## Validates if the item type is ammunition and there is space (up to 10 of each type).
func can_accept_item(item_res: ItemResource) -> bool:
	if not item_res or not item_res.is_ammo:
		return false
		
	var count = 0
	for key in inventory.keys():
		if key.display_name == item_res.display_name:
			count = inventory[key]
			break
			
	return count < 10



## Adds ammunition into the distributor's inventory, capping at 10.
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	if not item_res or not item_res.is_ammo:
		return 0
		
	var target_key: ItemResource = null
	for key in inventory.keys():
		if key.display_name == item_res.display_name:
			target_key = key
			break
			
	if not target_key:
		# If we don't have this key yet, create a new one using the passed resource
		target_key = item_res
		inventory[target_key] = 0
		
	var current_amount = inventory[target_key]
	if current_amount >= 10:
		return 0
		
	var added = min(amount, 10 - current_amount)
	inventory[target_key] = current_amount + added
	
	inventory_changed.emit()
	return added



## Returns the active inventory dictionary of ammo types and counts.
func get_inventory_info() -> Dictionary:
	return inventory



## Clears all stored ammunition and notifies UI lists.
func void_inventory():
	inventory.clear()
	inventory_changed.emit()



## Draws a light blue range indicator on the map when highlighted or selected.
func _draw():
	if not (show_range_overlay or is_selected):
		return
		
	var circle_color = Color(0.2, 0.8, 1.0, 0.15) # Light blue fill
	var border_color = Color(0.2, 0.8, 1.0, 0.8)  # Light blue border
	var border_width = 1.5
	
	draw_circle(Vector2.ZERO, distribution_range, circle_color)
	draw_arc(Vector2.ZERO, distribution_range, 0.0, TAU, 64, border_color, border_width, true)



## Scans for nearby towers and prioritizes sending ammo to the tower with the lowest magazine percentage.
func _distribute_ammo():
	if not level_ref or not level_ref.building_manager:
		return
		
	var best_tower: TowerBuilding = null
	var best_item_res: ItemResource = null
	var lowest_percentage := INF
	
	# Find all towers within range
	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion() or b.is_ghost:
			continue
			
		if not (b is TowerBuilding):
			continue
			
		var dist = global_position.distance_to(b.global_position)
		if dist > distribution_range:
			continue
			
		# Check if the tower needs ammo
		if b.ammo_inventory.size() >= b.ammo_capacity:
			continue
			
		# Check if we have compatible ammo for this tower
		var candidate_res: ItemResource = null
		
		# If the tower is not empty, we MUST match the exact type it currently has
		if not b.ammo_inventory.is_empty():
			var active_name = b.ammo_inventory[0].display_name
			for key in inventory.keys():
				if key.display_name == active_name and inventory[key] > 0:
					candidate_res = key
					break
		else:
			# Tower is empty: first see if we hold its preferred ammo type
			var preferred_res: ItemResource = null
			for key in inventory.keys():
				if inventory[key] > 0 and key.ammo_type == b.preferred_ammo_type:
					preferred_res = key
					break
					
			if preferred_res:
				candidate_res = preferred_res
			else:
				# No preferred type available: find ANY compatible ammo we hold
				for key in inventory.keys():
					if inventory[key] > 0 and b.compatible_ammo_types.has(key.ammo_type):
						candidate_res = key
						break
					
		if not candidate_res:
			continue
			
		# Calculate ammo percentage on the tower
		var pct = float(b.ammo_inventory.size()) / float(b.ammo_capacity)
		if pct < lowest_percentage:
			lowest_percentage = pct
			best_tower = b
			best_item_res = candidate_res
			
	if best_tower and best_item_res:
		# Deduct 1 ammo from distributor
		inventory[best_item_res] -= 1
		if inventory[best_item_res] <= 0:
			inventory.erase(best_item_res)
			
		inventory_changed.emit()
		
		# Spawn visual flying supply package
		_spawn_delivery_projectile(best_item_res, best_tower)



## Animates a Godot logo package tweening smoothly to the target tower.
func _spawn_delivery_projectile(item_res: ItemResource, target_tower: TowerBuilding):
	var sprite = Sprite2D.new()
	sprite.texture = load("res://icon.svg")
	sprite.scale = Vector2(0.25, 0.25)
	sprite.global_position = global_position
	
	# Add to the level's object layer or parent so it draws correctly
	get_parent().add_child(sprite)
	
	var dist = global_position.distance_to(target_tower.global_position)
	var speed = 200.0 # px/sec
	var duration = dist / speed
	
	var tween = sprite.create_tween()
	tween.tween_property(sprite, "global_position", target_tower.global_position, duration)
	tween.tween_callback(func():
		if is_instance_valid(target_tower) and not target_tower.is_queued_for_deletion():
			target_tower.add_item(item_res, 1)
		sprite.queue_free()
	)



## Turns on the range indicator bounds overlay.
func _on_mouse_entered():
	show_range_overlay = true



## Turns off the range indicator bounds overlay.
func _on_mouse_exited():
	show_range_overlay = false



## Packs distributor inventory arrays into saved database dictionaries.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	var saved_inventory = {}
	for item_res in inventory.keys():
		saved_inventory[item_res.display_name] = inventory[item_res]
		
	data["inventory"] = saved_inventory
	return data



## Restores distributor inventory lists from loaded game saves.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	inventory.clear()
	if data.has("inventory"):
		var saved_inv = data["inventory"]
		for item_name in saved_inv.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				inventory[item_res] = int(saved_inv[item_name])
				
	inventory_changed.emit()
