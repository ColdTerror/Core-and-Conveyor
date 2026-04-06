extends Building
class_name TowerBuilding

@export_group("Tower Configuration")
@export_enum("Arrow", "Rock", "Magic") var required_ammo_type: String = "Arrow"
@export var ammo_capacity: int = 20

@export_group("Combat Stats")
@export var attack_range: float = 200.0
@export var fire_rate: float = 1.0 
@export var damage_multiplier: float = 1.0 

@export_subgroup("Multi-Shot (Shotgun)")
@export var projectiles_per_shot: int = 1 
@export var spread_degrees: float = 0.0 

# Internal State
var ammo_inventory: Array[ItemResource] = []
var attack_cooldown: float = 0.0
var current_target: Node2D = null
var level_ref: Node2D

var targeting_modes: Array[String] = ["Closest", "Strongest", "Weakest", "Furthest"]
var current_targeting_index: int = 0
var targeting_mode: String = "Closest"

# Cached range tiles - used by both visualization and targeting
var _cached_range_tiles: Dictionary = {}

# Signal: Source, Position, Target, ItemData, FinalDamage, Speed, SpreadOffset
signal fired_projectile(source_tower, start_pos, target_node, item_data, final_damage, speed, angle_offset)

# --- VISUALIZATION VARIABLES ---
var show_range_overlay := false:
	set(value):
		show_range_overlay = value
		queue_redraw()

func _ready():
	super()
	_cached_range_tiles = _get_local_range_tiles()
	add_to_group("Towers")

func setup(level_instance: Node2D):
	level_ref = level_instance



func apply_research_buffs():
	damage_multiplier = ResearchManager.tower_damage_mult


# ============================================================
#  RANGE VISUALIZATION (Grid-Based)
# ============================================================

func _draw():
	if not show_range_overlay:
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
	
	var max_dist_px = attack_range
	var search_radius = ceil(attack_range / tile_size) + max(b_size.x, b_size.y)
	
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


# Override Base Building functions to toggle range
func set_ghost(enabled: bool):
	super.set_ghost(enabled)
	show_range_overlay = enabled 

func _on_mouse_entered():
	super._on_mouse_entered()
	if has_node("Area2D") and $Area2D.monitoring:
		show_range_overlay = true

func _on_mouse_exited():
	super._on_mouse_exited()
	if has_node("Area2D") and $Area2D.monitoring:
		show_range_overlay = false


# ============================================================
#  TARGETING HELPERS
# ============================================================

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


# ============================================================
# ============================================================

# --- 1. FILTERED INPUT ---

func accepts_item_at(tile: Vector2i) -> bool:
	return tile in occupied_tiles

# --- THE "SOFT CAP" ADD ITEM LOGIC ---
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	# 1. Filter: Reject if it's not the right ammo
	if not item_res.is_ammo: return 0
	if item_res.ammo_type != required_ammo_type: return 0
	
	# 2. Capacity Check: Are we already completely full?
	if ammo_inventory.size() >= ammo_capacity: 
		return 0 # Reject it!
		
	# 3. Soft Cap: If we have ANY space left, we will take EXACTLY 1 physical item!
	# (Even if that item contains 5 shots and pushes us over 20)
	var stack_sz = item_res.stack_size if "stack_size" in item_res else 1
	
	# Load all the shots from that single item into the magazine
	for i in range(stack_sz):
		ammo_inventory.append(item_res)
		
	inventory_changed.emit()
	
	# We successfully took 1 physical item out of the bot's hands or off the belt!
	return 1

# --- 2. COMBAT LOOP ---

func building_tick(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta
	
	if attack_cooldown <= 0 and ammo_inventory.size() > 0:
		_try_find_target()
		if current_target:
			_shoot()

func _try_find_target():
	# If mode is Closest, 'Sticky Targeting' is usually good so it finishes off 
	# the enemy it started shooting at.
	if targeting_mode == "Closest":
		if _is_valid_target(current_target): return 
		
	# For Strongest/Weakest, we ALWAYS want to scan the area right before we 
	# shoot to ensure we are hitting the absolute best target!
	current_target = _find_best_enemy()

func _find_best_enemy() -> Node2D:
	if not level_ref: return null
	
	var best_enemy: Node2D = null
	
	# Setup our starting comparisons based on the mode
	var best_value = INF if targeting_mode in ["Closest", "Weakest"] else -INF
	
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if _cached_range_tiles.has(_get_enemy_tile(enemy)):
			
			# Mode 1: Closest
			if targeting_mode == "Closest":
				var dist = global_position.distance_to(enemy.global_position)
				if dist < best_value:
					best_value = dist
					best_enemy = enemy
					
			# Mode 2: Weakest (Lowest HP)
			elif targeting_mode == "Weakest":
				if "health" in enemy:
					if enemy.health < best_value:
						best_value = enemy.health
						best_enemy = enemy
						
			# Mode 3: Strongest (Highest HP)
			elif targeting_mode == "Strongest":
				if "health" in enemy:
					if enemy.health > best_value:
						best_value = enemy.health
						best_enemy = enemy
			# --- NEW: Mode 4: Furthest ---
			elif targeting_mode == "Furthest":
				var dist = global_position.distance_to(enemy.global_position)
				if dist > best_value:
					best_value = dist
					best_enemy = enemy
			# -----------------------------

	return best_enemy

func _is_valid_target(target) -> bool:
	if not is_instance_valid(target): return false
	if target.is_queued_for_deletion(): return false
	return _cached_range_tiles.has(_get_enemy_tile(target))


# --- 3. FIRING LOGIC ---

func _shoot():
	var ammo_data = ammo_inventory.pop_front()
	inventory_changed.emit()
	
	attack_cooldown = 1.0 / fire_rate
	var final_damage = roundi(ammo_data.damage * damage_multiplier)
	
	# --- FIXED: EDGE SPAWN CALCULATION ---
	var spawn_pos = global_position
	
	# Only offset if the target hasn't been deleted in the last millisecond
	if is_instance_valid(current_target):
		var direction_to_enemy = global_position.direction_to(current_target.global_position)
		# Push the arrow out by half a tile (adjust this if your tower is wider!)
		var spawn_radius = 16.0 
		spawn_pos = global_position + (direction_to_enemy * spawn_radius)
	# -------------------------------------
	
	for i in range(projectiles_per_shot):
		var angle_offset = 0.0
		if projectiles_per_shot > 1:
			var spread_rad = deg_to_rad(spread_degrees)
			var step = spread_rad / (projectiles_per_shot - 1)
			angle_offset = - (spread_rad / 2.0) + (i * step)
		
		fired_projectile.emit(
			self,
			spawn_pos, # <--- Tell the Level to spawn it here!
			current_target, 
			ammo_data, 
			final_damage, 
			ammo_data.projectile_speed, 
			angle_offset
		)
		
	# --- JUICE: SQUISH RECOIL ---
	if has_node("Sprite2D"):
		var tween = create_tween()
		# Instantly squish down and slightly wide
		tween.tween_property($Sprite2D, "scale", Vector2(1.1, 0.9), 0.05)
		# Smoothly pop back to normal
		tween.tween_property($Sprite2D, "scale", Vector2(1.0, 1.0), 0.15)

# --- UI ---
func get_inventory_info() -> Dictionary:
	return { 
		"Ammo": ammo_inventory.size(),
		"Type": required_ammo_type
	}

# --- ECONOMY ---
func get_economy_assets() -> Dictionary:
	return {}
	
func cycle_targeting_mode():
	current_targeting_index = (current_targeting_index + 1) % targeting_modes.size()
	targeting_mode = targeting_modes[current_targeting_index]
	
	# Clear the current target so the tower immediately snaps to the new priority!
	current_target = null 
	
	print("Tower targeting set to: ", targeting_mode)
