extends PanelContainer

@onready var name_label = $VBoxContainer/Name
@onready var health_label = $VBoxContainer/Health
@onready var stats_box = $VBoxContainer/Stats
@onready var inventory_box = $VBoxContainer/Inventory
@onready var work_bar = $VBoxContainer/WorkBar

var current_building: Node2D = null

func _ready():
	work_bar.visible = false
	hide() # Start hidden

func _process(_delta):
	# SAFETY CHECK: If building died, close popup immediately
	if visible and not is_instance_valid(current_building):
		hide_popup()
		return

	# PROGRESS BAR ANIMATION
	if visible:
		# Duck typing check to prevent crashing on bots
		if current_building is ConstructionSite:
			work_bar.value = (float(current_building.health) / current_building.max_health) * 100.0
		elif current_building.has_method("get_progress_ratio"):
			work_bar.value = current_building.get_progress_ratio() * 100.0
	
	# Live-refresh bot stats since energy changes every frame
	if is_instance_valid(current_building) and current_building.building_name == "Worker Bot":
		_refresh_stats_ui(current_building)


func show_building_info(b: Node2D):
	var is_new_target = (current_building != b)
	_disconnect_signals()
	current_building = b
	
	# --- NAME & LEVEL ---
	var b_name = b.building_name if "building_name" in b else "Unknown Object"
	if "building_level" in b:
		name_label.text = "%s (Lv. %d)" % [b_name, b.building_level]
	else:
		name_label.text = b_name # Bots don't have levels!

	# --- HEALTH LOGIC ---
	if "health" in b and "max_health" in b:
		health_label.visible = true
		_update_health_text(b.health, b.max_health)
	else:
		health_label.visible = false

	# --- SIGNALS ---
	if b.has_signal("health_changed") and not b.health_changed.is_connected(_on_health_changed):
		b.health_changed.connect(_on_health_changed)
		
	if b.has_signal("inventory_changed") and not b.inventory_changed.is_connected(_on_inventory_changed):
		b.inventory_changed.connect(_on_inventory_changed)
	
	# Only show work bar for specific building types
	work_bar.visible = (b is ProcessorBuilding) or (b is ConstructionSite)
	
	_refresh_inventory_ui()
	_refresh_stats_ui(b)
	
	# TWEEN ANIMATION
	if is_new_target or not visible:
		show()
		pivot_offset = size / 2
		scale = Vector2(0.9, 0.9)
		modulate.a = 0.5 
		
		var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector2.ONE, 0.1)
		tween.parallel().tween_property(self, "modulate:a", 1.0, 0.1)


func hide_popup():
	_disconnect_signals()
	current_building = null
	hide()

# --- HELPER: CLEAN DISCONNECT ---
func _disconnect_signals():
	if current_building and is_instance_valid(current_building):
		if current_building.has_signal("health_changed") and current_building.health_changed.is_connected(_on_health_changed):
			current_building.health_changed.disconnect(_on_health_changed)
			
		if current_building.has_signal("inventory_changed") and current_building.inventory_changed.is_connected(_on_inventory_changed):
			current_building.inventory_changed.disconnect(_on_inventory_changed)

# --- SIGNAL CALLBACKS ---

func _on_health_changed(current: int, max_hp: int):
	_update_health_text(current, max_hp)

func _update_health_text(current: int, max_hp: int):
	health_label.text = "HP: %d / %d" % [current, max_hp]

func _on_inventory_changed():
	_refresh_inventory_ui()


# --- INVENTORY LOGIC ---

func _refresh_inventory_ui():
	if not current_building: return
	
	if not current_building.has_method("get_inventory_info"):
		hide_inventory()
		return

	var info = current_building.get_inventory_info()
	
	if not info.is_empty():
		show_inventory(info)
	else:
		hide_inventory()


func show_inventory(inventory: Dictionary):
	inventory_box.visible = true

	# Clear previous rows
	for child in inventory_box.get_children():
		child.queue_free()

	# --- NEW: SPECIAL BOT TRAP ---
	# If this is our bot, it returns text like {"Target": "Wood Only", "Carrying": "Wood (5)"}
	if current_building.building_name == "Worker Bot":
		for key in inventory.keys():
			var row = Label.new()
			row.text = "%s: %s" % [key, inventory[key]]
			row.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0)) # Soft Blue
			inventory_box.add_child(row)
		return # Stop here so it doesn't run the building logic below!
	# -----------------------------

	# --- Standard Building Logic ---
	var is_buffer = false
	var max_cap = 0
	
	if "buffer_capacity" in current_building:
		is_buffer = true
		max_cap = current_building.buffer_capacity

	for key in inventory.keys():
		var value = inventory[key] 
		var display_text = "Unknown"

		if key is Resource and "display_name" in key:
			display_text = key.display_name
		elif key is String:
			display_text = key
			
		var row := Label.new()
		
		if current_building is ConstructionSite:
			row.text = "%s: %s" % [display_text, str(value)]
			row.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2)) 
			
		elif is_buffer and (value is int or value is float):
			if max_cap > 0 and value >= max_cap:
				row.text = "Buffer FULL [%s]: %d/%d" % [display_text, value, max_cap]
				row.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3)) 
			else:
				var cap_str = str(max_cap) if max_cap > 0 else "?"
				row.text = "Output Buffer [%s]: %d/%s" % [display_text, value, cap_str]
				row.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7)) 
		else:
			if value is int or value is float:
				row.text = "Secured [%s]: %d" % [display_text, value]
			else:
				row.text = "Secured [%s]: %s" % [display_text, str(value)]
				
			row.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
			
		inventory_box.add_child(row)

func hide_inventory():
	inventory_box.visible = false


func _refresh_stats_ui(b: Node2D):
	for child in stats_box.get_children():
		child.queue_free()

	var stats = []
	
	if b.building_name == "Worker Bot":
		_collect_bot_stats(b, stats)
	elif b is TowerBuilding:
		_collect_tower_stats(b, stats)
	elif b is ProcessorBuilding:
		_collect_processor_stats(b, stats)
	else:
		_collect_harvester_stats(b, stats)

	for stat_text in stats:
		var row = Label.new()
		row.text = stat_text
		row.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		row.add_theme_font_size_override("font_size", 12)
		stats_box.add_child(row)

func _collect_bot_stats(b: Node2D, stats: Array):
	if "current_speed" in b: stats.append("Speed: %.0f" % b.current_speed)
	if "carry_capacity" in b: stats.append("Carry Cap: %d" % b.carry_capacity)
	if "current_energy" in b and "max_energy" in b:
		stats.append("Energy: %.0f / %.0f" % [b.current_energy, b.max_energy])
	if "energy_recharge_rate" in b: stats.append("Recharge: %.0f/s" % b.energy_recharge_rate)
	if "energy_drain_rate" in b: stats.append("Drain: %.0f/s" % b.energy_drain_rate)
	if "is_limping" in b and b.is_limping: stats.append("Status: Limping!")

func _collect_tower_stats(b: Node2D, stats: Array):
	if "damage_multiplier" in b: stats.append("Damage Mult: %.1fx" % b.damage_multiplier)
	if "fire_rate" in b: stats.append("Fire Rate: %.1f/s" % b.fire_rate)
	if "attack_range" in b: stats.append("Range: %d Tiles" % int(b.attack_range / 32.0))
	if "ammo_inventory" in b and "ammo_capacity" in b:
		stats.append("Ammo: %d / %d" % [b.ammo_inventory.size(), b.ammo_capacity])

func _collect_processor_stats(b: Node2D, stats: Array):
	if "crafting_time_multiplier" in b:
		stats.append("Time Multiplier: %d%%" % int(b.crafting_time_multiplier * 100))

func _collect_harvester_stats(b: Node2D, stats: Array):
	if "scan_radius" in b: stats.append("Harvest Radius: %d" % b.scan_radius)
	if "harvest_damage" in b: stats.append("Harvest Amount: %d" % b.harvest_damage)
	if "work_interval" in b: stats.append("Work Interval: %.1fs" % b.work_interval)
