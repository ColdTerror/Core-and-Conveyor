extends Building
class_name TowerBuilding

@export_group("Tower Configuration")
@export_enum("Arrow", "Rock", "Magic") var required_ammo_type: String = "Arrow"
@export var ammo_capacity: int = 20

@export_group("Combat Stats")
@export var attack_range: float = 200.0
@export var fire_rate: float = 1.0 # Volleys per second
@export var damage_multiplier: float = 1.0 # 2.0 = Double damage (Ballista)

@export_subgroup("Multi-Shot (Shotgun)")
@export var projectiles_per_shot: int = 1 # 1 = Bow, 5 = Rock Shotgun
@export var spread_degrees: float = 0.0 # 30.0 = Wide cone

# Internal State
var ammo_inventory: Array[ItemResource] = []
var attack_cooldown: float = 0.0
var current_target: Node2D = null
var level_ref: Node2D

# Signal: Position, Target, ItemData, FinalDamage, Speed, SpreadOffset
signal fired_projectile(start_pos, target_node, item_data, final_damage, speed, angle_offset)

func setup(level_instance: Node2D):
	level_ref = level_instance

# --- 1. FILTERED INPUT ---

func accepts_item_at(tile: Vector2i) -> bool:
	return tile in occupied_tiles

func can_accept_item(item: ItemResource) -> bool:
	# 1. Must be ammo
	if not item.is_ammo: return false
	
	# 2. Must match my specific type (No Rocks in Bow Towers!)
	if item.ammo_type != required_ammo_type: return false
	
	# 3. Must have space
	if ammo_inventory.size() >= ammo_capacity: return false
	
	return true

func accept_item(item: ItemResource) -> bool:
	if not can_accept_item(item): return false
	ammo_inventory.append(item)
	inventory_changed.emit()
	return true

# --- 2. COMBAT LOOP ---

func building_tick(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta
	
	if attack_cooldown <= 0 and ammo_inventory.size() > 0:
		_try_find_target()
		if current_target:
			_shoot()

func _try_find_target():
	if _is_valid_target(current_target): return
	current_target = _find_nearest_enemy()

func _is_valid_target(target) -> bool:
	if not is_instance_valid(target): return false
	if target.is_queued_for_deletion(): return false
	if global_position.distance_to(target.global_position) > attack_range: return false
	return true

func _find_nearest_enemy() -> Node2D:
	if not level_ref: return null
	
	var nearest: Node2D = null
	var min_dist = attack_range
	var enemies = get_tree().get_nodes_in_group("Enemies")
	
	for enemy in enemies:
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
	return nearest

# --- 3. FIRING LOGIC ---

func _shoot():
	# Consume 1 Ammo item per volley
	var ammo_data = ammo_inventory.pop_front()
	inventory_changed.emit()
	
	# Reset Cooldown
	attack_cooldown = 1.0 / fire_rate
	
	# Calculate Stats
	var final_damage = ammo_data.damage * damage_multiplier
	
	# Fire Projectiles (Handle Multishot)
	for i in range(projectiles_per_shot):
		var angle_offset = 0.0
		
		# Calculate spread if we have multiple shots
		if projectiles_per_shot > 1:
			var spread_rad = deg_to_rad(spread_degrees)
			var step = spread_rad / (projectiles_per_shot - 1)
			# Center the cone: Start at -spread/2, increment by step
			angle_offset = - (spread_rad / 2.0) + (i * step)
		
		# Emit signal for the Level to spawn the actual arrow/rock
		fired_projectile.emit(
			global_position, 
			current_target, 
			ammo_data, 
			final_damage, 
			ammo_data.projectile_speed, 
			angle_offset
		)
	
	# Debug print
	# print("%s fired %d x %s!" % [building_name, projectiles_per_shot, ammo_data.display_name])

# --- UI ---
func get_inventory_info() -> Dictionary:
	return { 
		"Ammo": ammo_inventory.size(),
		"Type": required_ammo_type
	}
