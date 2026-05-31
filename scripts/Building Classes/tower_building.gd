# ==============================================================================
# Script: Building Classes/tower_building.gd
# Purpose: Defensive combat tower that requests specific ammo items from worker bots or belts, scans for local targets based on targeting priorities (Closest, Strongest, Weakest, Furthest), fires damage-scaled projectiles over fire-rate cooldown intervals, applies recoil tweens, and serializes magazine ammo arrays.
# Dependencies: Inherits Building. Requires global Autoloads ResearchManager, EconomyManager, ItemDatabase, child nodes (Sprite2D), and communicates with projectiles.
# Signals:
#   - fired_projectile: Emitted when launching a projectile.
# ==============================================================================
extends Building
class_name TowerBuilding

@export_group("Tower Configuration")
@export_enum("Arrow", "BallistaBolt", "Pebble", "Boulder", "Magic") var preferred_ammo_type: String = "Arrow"
@export var compatible_ammo_types: Array[String] = ["Arrow"]
@export var ammo_capacity: int = 20

@export_group("Combat Stats")
@export var attack_range: int = 7
@export var fire_rate: float = 1.0 
@export var damage_multiplier: float = 1.0 

@export_subgroup("Primary Multi-Shot")
@export var projectiles_per_shot: int = 1
@export var spread_degrees: float = 0.0 

@export_subgroup("Alternate Ammo Override")
@export var alternate_damage_scale: float = 0.5

var base_damage_multiplier: float = 1.0
var ammo_inventory: Array[ItemResource] = []
var attack_cooldown: float = 0.0
var current_target: Node2D = null
var level_ref: Node2D

var targeting_modes: Array[String] = ["Closest", "Strongest", "Weakest", "Furthest"]
var current_targeting_index: int = 0
var targeting_mode: String = "Closest"

var _cached_range_tiles: Dictionary = {}

var show_range_overlay := false:
	set(value):
		show_range_overlay = value
		queue_redraw()

signal fired_projectile(source_tower, start_pos, target_node, item_data, final_damage, speed, angle_offset)



## Initializes base stats, caches range tiles, registers with the economy manager,
## and applies any research damage multiplier upgrades.
func _ready():
	super()
	add_to_group("PriorityTarget")
	base_damage_multiplier = damage_multiplier
	_cached_range_tiles = _get_local_range_tiles()
	add_to_group("Towers")
	apply_research_buffs()
	EconomyManager.register_source(self, false)



## Custom destruction logic that empties the magazine, destroys all stored ammo
## in the global economy tracking, and triggers base building cleanup.
func die():
	var assets = get_economy_assets()
	
	if not assets.is_empty():
		EconomyManager.remove_resources_from_global(assets)
		
		for item_name in assets.keys():
			var amount_lost = assets[item_name]
			EconomyManager.log_item_consumed(item_name, amount_lost)
			
	ammo_inventory.clear()
	
	super()

## Unregisters the core structure from the global economy registries when removed.
func _exit_tree():
	EconomyManager.unregister_source(self)

## Links this tower to the active level instance.
func setup(level_instance: Node2D):
	level_ref = level_instance



## Calculates and applies upgraded damage multipliers based on technology research levels.
func apply_research_buffs():
	damage_multiplier = base_damage_multiplier + (ResearchManager.tower_damage_mult - 1.0)



## Draws the grid-based attack range outline when show_range_overlay is enabled or selected.
func _draw():
	if not (show_range_overlay or is_selected):
		return
		
	var tiles = _cached_range_tiles
	var tile_size = 32.0
	var half_offset = Vector2(tile_size / 2.0, tile_size / 2.0)
	
	var fill_color = Color(1.0, 0.2, 0.2, 0.15)
	var border_color = Color(1.0, 0.2, 0.2, 0.8)
	var b_width = 2.0
	
	for t in tiles.keys():
		var center_px = tiles[t]
		var top_left_px = center_px - half_offset
		draw_rect(Rect2(top_left_px, Vector2(tile_size, tile_size)), fill_color)
		
	for t in tiles.keys():
		var center_px = tiles[t]
		var pos = center_px - half_offset
		
		var tl = pos
		var tr = pos + Vector2(tile_size, 0)
		var bl = pos + Vector2(0, tile_size)
		var br = pos + Vector2(tile_size, tile_size)
		
		if not tiles.has(t + Vector2i.UP): draw_line(tl, tr, border_color, b_width)
		if not tiles.has(t + Vector2i.DOWN): draw_line(bl, br, border_color, b_width)
		if not tiles.has(t + Vector2i.LEFT): draw_line(tl, bl, border_color, b_width)
		if not tiles.has(t + Vector2i.RIGHT): draw_line(tr, br, border_color, b_width)



## Computes a local grid map of tiles falling within the tower's radial attack range.
func _get_local_range_tiles() -> Dictionary:
	var tiles = {}
	var tile_size = 32.0 
	
	var b_size = size if "size" in self else Vector2i(1, 1) 
	
	var half_w = (b_size.x * tile_size) / 2.0
	var half_h = (b_size.y * tile_size) / 2.0
	
	var rect_x_min = -half_w
	var rect_x_max = half_w
	var rect_y_min = -half_h
	var rect_y_max = half_h
	
	var max_dist_px = attack_range * tile_size
	var search_radius = attack_range + max(b_size.x, b_size.y)
	
	for x in range(-search_radius, search_radius + 1):
		for y in range(-search_radius, search_radius + 1):
			var tile_center_x = x * tile_size
			var tile_center_y = y * tile_size
			
			if int(b_size.x) % 2 == 0: tile_center_x += tile_size / 2.0
			if int(b_size.y) % 2 == 0: tile_center_y += tile_size / 2.0
			
			var dx = max(0.0, max(rect_x_min - tile_center_x, tile_center_x - rect_x_max))
			var dy = max(0.0, max(rect_y_min - tile_center_y, tile_center_y - rect_y_max))
			
			var dist_px = Vector2(dx, dy).length()
			
			if dist_px <= max_dist_px:
				tiles[Vector2i(x, y)] = Vector2(tile_center_x, tile_center_y)
				
	return tiles



## Overrides ghost state activation and controls range overlay visibility.
func set_ghost(enabled: bool):
	super.set_ghost(enabled)
	show_range_overlay = enabled 



## Shows the range overlay when the cursor enters the building bounding box.
func _on_mouse_entered():
	super._on_mouse_entered()
	if has_node("Area2D") and $Area2D.monitoring:
		show_range_overlay = true


## Hides the range overlay when the cursor leaves the building bounding box.
func _on_mouse_exited():
	super._on_mouse_exited()
	if has_node("Area2D") and $Area2D.monitoring:
		show_range_overlay = false



## Determines which grid tile an enemy occupies relative to this tower's center.
func _get_enemy_tile(enemy: Node2D) -> Vector2i:
	var local_pos = enemy.global_position - global_position
	var tile_size = 32.0
	var b_size = size if "size" in self else Vector2i(1, 1)
	var offset_x = (tile_size / 2.0) if int(b_size.x) % 2 == 0 else 0.0
	var offset_y = (tile_size / 2.0) if int(b_size.y) % 2 == 0 else 0.0
	return Vector2i(
		floor((local_pos.x - offset_x) / tile_size + 0.5),
		floor((local_pos.y - offset_y) / tile_size + 0.5)
	)



## Validates and appends delivered ammo items into the tower's ammunition inventory.
## Rejects items if they do not match required ammo specifications.
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	if not item_res.is_ammo: return 0
	if not compatible_ammo_types.has(item_res.ammo_type): return 0
	if not ammo_inventory.is_empty() and ammo_inventory[0].display_name != item_res.display_name:
		return 0
	
	var shots_to_add = 0
	var return_val = 0
	
	# Hybrid pipeline logic:
	if amount == 1:
		# Scenario A: Bot/Belt Delivery!
		# If completely full, reject delivery.
		if ammo_inventory.size() >= ammo_capacity: 
			return 0 
			
		# If any space exists, accept the whole stack to prevent stuck worker bots.
		shots_to_add = item_res.stack_size if "stack_size" in item_res else 1
		return_val = 1 
	else:
		# Scenario B: Saved State Injection!
		# Accept the exact amount saved to perfectly restore game state.
		shots_to_add = amount
		return_val = amount 
		
	for i in range(shots_to_add):
		ammo_inventory.append(item_res)
		
	inventory_changed.emit()
	return return_val



## Checks whether this tower has space in its magazine to accept the specified ammo.
func can_accept_item(item_res: ItemResource) -> bool:
	if not item_res.is_ammo: return false
	if not compatible_ammo_types.has(item_res.ammo_type): return false
	if not ammo_inventory.is_empty() and ammo_inventory[0].display_name != item_res.display_name:
		return false
	
	return ammo_inventory.size() < ammo_capacity



func void_inventory():
	var assets = get_economy_assets()
	if not assets.is_empty():
		EconomyManager.remove_resources_from_global(assets)
		for item_name in assets.keys():
			var amount_lost = assets[item_name]
			EconomyManager.log_item_consumed(item_name, amount_lost)
	ammo_inventory.clear()
	inventory_changed.emit()



## Ticks combat logic, managing weapon reload cooldowns and searching for targets.
func building_tick(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta
	
	if attack_cooldown <= 0 and ammo_inventory.size() > 0:
		_try_find_target()
		if current_target:
			_shoot()


## Scans for targets, utilizing sticky targeting rules if set to "Closest".
func _try_find_target():
	if targeting_mode == "Closest":
		if _is_valid_target(current_target): return 
		
	# For Strongest/Weakest, always scan right before shooting to guarantee best target priority.
	current_target = _find_best_enemy()


## Searches the active enemy pool to locate the optimal target matching the active priority mode.
func _find_best_enemy() -> Node2D:
	if not level_ref: return null
	
	var best_enemy: Node2D = null
	var best_value = INF if targeting_mode in ["Closest", "Weakest"] else -INF
	
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if _cached_range_tiles.has(_get_enemy_tile(enemy)):
			
			if targeting_mode == "Closest":
				var dist = global_position.distance_to(enemy.global_position)
				if dist < best_value:
					best_value = dist
					best_enemy = enemy
					
			elif targeting_mode == "Weakest":
				if "health" in enemy:
					if enemy.health < best_value:
						best_value = enemy.health
						best_enemy = enemy
						
			elif targeting_mode == "Strongest":
				if "health" in enemy:
					if enemy.health > best_value:
						best_value = enemy.health
						best_enemy = enemy

			elif targeting_mode == "Furthest":
				var dist = global_position.distance_to(enemy.global_position)
				if dist > best_value:
					best_value = dist
					best_enemy = enemy

	return best_enemy


## Validates whether a target is healthy, active, and remains in attack range.
func _is_valid_target(target) -> bool:
	if not is_instance_valid(target): return false
	if target.is_queued_for_deletion(): return false
	return _cached_range_tiles.has(_get_enemy_tile(target))



## Fires projectiles at the designated target, applying spread modifiers and a juice squash tween.
func _shoot():
	if ammo_inventory.is_empty(): return
	
	var sample_ammo = ammo_inventory[0]
	var is_preferred = sample_ammo.ammo_type == preferred_ammo_type
	
	var requested_count = projectiles_per_shot
	var spread = spread_degrees
	var damage_scale = 1.0
	
	if not is_preferred:
		damage_scale = alternate_damage_scale
		
	var actual_count = min(requested_count, ammo_inventory.size())
	if actual_count <= 0: return
	
	# Consume actual ammo from the inventory
	var ammo_data = sample_ammo
	for i in range(actual_count):
		var popped = ammo_inventory.pop_front()
		if popped:
			EconomyManager.log_item_consumed(popped.display_name, 1)
			
	inventory_changed.emit()
	
	attack_cooldown = 1.0 / fire_rate
	var final_damage = roundi(ammo_data.damage * damage_multiplier * damage_scale)
	
	var spawn_pos = global_position
	
	# Only offset spawn if target is fully valid
	if is_instance_valid(current_target):
		var direction_to_enemy = global_position.direction_to(current_target.global_position)
		var spawn_radius = 16.0 
		spawn_pos = global_position + (direction_to_enemy * spawn_radius)
	
	for i in range(actual_count):
		var angle_offset = 0.0
		if actual_count > 1:
			var spread_rad = deg_to_rad(spread)
			var step = spread_rad / (actual_count - 1)
			angle_offset = - (spread_rad / 2.0) + (i * step)
		
		fired_projectile.emit(
			self,
			spawn_pos,
			current_target, 
			ammo_data, 
			final_damage, 
			ammo_data.projectile_speed, 
			angle_offset
		)
		
	if has_node("Sprite2D"):
		var tween = create_tween()
		tween.tween_property($Sprite2D, "scale", Vector2(1.1, 0.9), 0.05)
		tween.tween_property($Sprite2D, "scale", Vector2(1.0, 1.0), 0.15)



## Returns descriptive UI dictionary containing current ammo counts and target specs.
func get_inventory_info() -> Dictionary:
	if ammo_inventory.is_empty():
		return {}
	return { ammo_inventory[0]: ammo_inventory.size() }



## Summarizes stored ammunition counts for game-wide economics tracking.
func get_economy_assets() -> Dictionary:
	var assets = {}
	
	for ammo_res in ammo_inventory:
		var item_name = ammo_res.display_name
		assets[item_name] = assets.get(item_name, 0) + 1
		
	return assets



## Cycles through targeting priorities (Closest, Strongest, Weakest, Furthest)
## and clears active target to force immediate snap-to-new-priority.
func cycle_targeting_mode():
	current_targeting_index = (current_targeting_index + 1) % targeting_modes.size()
	targeting_mode = targeting_modes[current_targeting_index]
	current_target = null 
	
	print("Tower targeting set to: ", targeting_mode)



## Serializes internal combat state and ammunition counts into a dictionary for saves.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	var saved_ammo = []
	for ammo_res in ammo_inventory:
		saved_ammo.append(ammo_res.display_name)
	data["ammo_inventory"] = saved_ammo
	
	data["targeting_mode"] = targeting_mode
	data["current_targeting_index"] = current_targeting_index
	data["attack_cooldown"] = attack_cooldown
	
	return data


## Deserializes combat state, restoring ammunition inventory from saved strings.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	targeting_mode = data.get("targeting_mode", "Closest")
	current_targeting_index = data.get("current_targeting_index", 0)
	attack_cooldown = data.get("attack_cooldown", 0.0)
	
	ammo_inventory.clear()
	if data.has("ammo_inventory"):
		var saved_ammo_strings = data["ammo_inventory"]
		for item_name in saved_ammo_strings:
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				ammo_inventory.append(item_res)
				
	current_target = null
	inventory_changed.emit()
