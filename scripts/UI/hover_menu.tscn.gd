# ==============================================================================
# Script: UI/hover_menu.tscn.gd
# Purpose: Dictates the tooltips and hover info overlay menus that pop up when cursor details are hovered over buildings or bots, including health, progress meters, inv capacity, stats, and leveling.
# Dependencies: Autoloads ResearchManager and EconomyManager. Also relies on child controls (name_label, health_label, stats_box, inventory_box, work_bar).
# Signals: None.
# ==============================================================================
extends PanelContainer

@onready var name_label = $VBoxContainer/Name
@onready var health_label = $VBoxContainer/Health
@onready var stats_box = $VBoxContainer/Stats
@onready var inventory_box = $VBoxContainer/Inventory
@onready var work_bar = $VBoxContainer/WorkBar

var current_building: Node2D = null



## Initializes the hover menu overlay panels, resetting work progress bar states.
func _ready():
	work_bar.visible = false
	hide()
	
	name_label.add_theme_font_size_override("font_size", 20)
	health_label.add_theme_font_size_override("font_size",16)



## Monitores progress bars, active selections, and live status energy updates for hover-cards.
func _process(_delta):
	# Close popup if building is destroyed
	if visible and not is_instance_valid(current_building):
		hide_popup()
		return

	if visible:
		# Duck typing check to prevent crashes
		if current_building is ConstructionSite:
			work_bar.value = (float(current_building.health) / current_building.max_health) * 100.0
		elif current_building.has_method("get_progress_ratio"):
			work_bar.value = current_building.get_progress_ratio() * 100.0
	
	# Live-refresh bot stats
	if is_instance_valid(current_building) and current_building.building_name == "Worker Bot":
		_refresh_stats_ui(current_building)
		_update_health_text(current_building.health, current_building.max_health)



## Renders a popup tooltip layout with relevant health, levels, inventory, and stats for the selected building or bot.
func show_building_info(b: Node2D):
	var is_new_target = (current_building != b)
	_disconnect_signals()
	current_building = b
	
	var b_name = b.building_name if "building_name" in b else "Unknown Object"
	if b is CoreBuilding:
		name_label.text = "%s [Tier %d]" % [b_name, ResearchManager.tier_unlocked]
	else:
		var has_upgrades = ("upgrades_to" in b and b.upgrades_to != null) or ("building_level" in b and b.building_level > 1)
		if has_upgrades and "building_level" in b:
			name_label.text = "%s (Lv %d)" % [b_name, b.building_level]
		else:
			name_label.text = b_name

	if "health" in b and "max_health" in b:
		health_label.visible = true
		_update_health_text(b.health, b.max_health)
	else:
		health_label.visible = false

	if b.has_signal("health_changed") and not b.health_changed.is_connected(_on_health_changed):
		b.health_changed.connect(_on_health_changed)
		
	if b.has_signal("inventory_changed") and not b.inventory_changed.is_connected(_on_inventory_changed):
		b.inventory_changed.connect(_on_inventory_changed)
	
	# Only show work bar for specific types
	work_bar.visible = (b is ProcessorBuilding) or (b is ConstructionSite)
	
	_refresh_inventory_ui()
	_refresh_stats_ui(b)
	
	if is_new_target or not visible:
		show()
		pivot_offset = size / 2
		scale = Vector2(0.9, 0.9)
		modulate.a = 0.5 
		
		var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector2.ONE, 0.1)
		tween.parallel().tween_property(self, "modulate:a", 1.0, 0.1)



## Cleans up active signals and hides the popup overlay.
func hide_popup():
	_disconnect_signals()
	current_building = null
	hide()



## Disconnects signals to prevent memory leaks or dangling receivers.
func _disconnect_signals():
	if current_building and is_instance_valid(current_building):
		if current_building.has_signal("health_changed") and current_building.health_changed.is_connected(_on_health_changed):
			current_building.health_changed.disconnect(_on_health_changed)
			
		if current_building.has_signal("inventory_changed") and current_building.inventory_changed.is_connected(_on_inventory_changed):
			current_building.inventory_changed.disconnect(_on_inventory_changed)



## Updates health details dynamically when the current target's health changes.
func _on_health_changed(current: int, max_hp: int):
	_update_health_text(current, max_hp)



## Standardizes the health metric format.
func _update_health_text(current: int, max_hp: int):
	health_label.text = "HP: %d / %d" % [current, max_hp]



## Triggers visual inventory card updates when stock levels shift on the target.
func _on_inventory_changed():
	_refresh_inventory_ui()
	if current_building and is_instance_valid(current_building):
		_refresh_stats_ui(current_building)



## Analyzes target inventory fields and rebuilds the inventory display layout.
func _refresh_inventory_ui():
	if not current_building: return
	
	if current_building is TowerBuilding:
		hide_inventory()
		return
		
	if not current_building.has_method("get_inventory_info"):
		hide_inventory()
		return

	var info = current_building.get_inventory_info()
	
	if not info.is_empty():
		show_inventory(info)
	else:
		hide_inventory()



## Populates list labels within the inventory panel showing buffer limits or carrying capacity.
func show_inventory(inventory: Dictionary):
	inventory_box.visible = true

	# Clear previous rows
	for child in inventory_box.get_children():
		child.queue_free()

	# Special bot inventory format
	if current_building.building_name == "Worker Bot":
		for key in inventory.keys():
			var row = Label.new()
			row.text = "%s: %s" % [key, inventory[key]]
			row.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			row.add_theme_font_size_override("font_size", 16)
			inventory_box.add_child(row)
		return

	# Standard building logic
	for key in inventory.keys():
		var value = inventory[key] 
		var display_text = "Unknown"

		if key is Resource and "display_name" in key:
			display_text = key.display_name
		elif key is String:
			display_text = key
			
		var row := Label.new()
		row.text = "%s: %s" % [display_text, str(value)]
		row.add_theme_font_size_override("font_size", 16)
		
		if current_building is ConstructionSite:
			row.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2)) 
		else:
			row.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
			
		inventory_box.add_child(row)



## Hides the target inventory panel.
func hide_inventory():
	inventory_box.visible = false



## Queries bot levels, veteran progression, turret specs, or harvester intervals to rebuild the stats list.
func _refresh_stats_ui(b: Node2D):
	for child in stats_box.get_children():
		child.queue_free()

	var stats = []
	
	if b.building_name == "Worker Bot":
		_collect_bot_stats(b, stats)
	elif b is CoreBuilding:
		_collect_core_stats(b, stats)
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
		row.add_theme_font_size_override("font_size", 16)
		stats_box.add_child(row)


## Populates stat list details representing worker bot energy, limping state, and XP progress.
func _collect_bot_stats(b: Node2D, stats: Array):
	if "bot_level" in b and "current_xp" in b and "XP_THRESHOLDS" in b:
		var global_max = 2
		
		# Safely query ResearchManager if it exists
		if ResearchManager.has_method("get_bot_max_level"):
			global_max = ResearchManager.get_bot_max_level()
				
		stats.append("Level: %d / %d" % [b.bot_level, global_max])
		
		if b.bot_level >= global_max:
			stats.append("XP: MAX")
		else:
			var next_threshold = b.XP_THRESHOLDS[b.bot_level]
			stats.append("XP: %d / %d" % [b.current_xp, next_threshold])
			
	if "current_speed" in b: stats.append("Speed: %.0f" % b.current_speed)
	if "carry_capacity" in b: stats.append("Carry Cap: %d" % b.carry_capacity)
	if "current_energy" in b and "max_energy" in b:
		stats.append("Energy: %.0f / %.0f" % [b.current_energy, b.max_energy])
	if "energy_recharge_rate" in b: stats.append("Recharge: %.0f/s" % b.energy_recharge_rate)
	if "energy_drain_rate" in b: stats.append("Drain: %.0f/s" % b.energy_drain_rate)
	if "is_limping" in b and b.is_limping: stats.append("Status: Limping!")
	if "is_flying" in b:
		stats.append("Flight: Enabled" if b.is_flying else "Flight: Locked")



## Formats core tech tier and worker bot population limits.
func _collect_core_stats(b: Node2D, stats: Array):
	stats.append("Core Tier: %d" % ResearchManager.tier_unlocked)
	var current_bots = get_tree().get_nodes_in_group("Bots").size()
	stats.append("Worker Bots: %d / %d" % [current_bots, ResearchManager.max_bots_allowed])



## Compiles defense turret rate of fire, damage, and ammunition stats.
func _collect_tower_stats(b: Node2D, stats: Array):
	# Determine active ammo-dependent firing stats
	var is_alternate = false
	if "ammo_inventory" in b and not b.ammo_inventory.is_empty():
		var loaded_ammo = b.ammo_inventory[0]
		if loaded_ammo.ammo_type != b.preferred_ammo_type:
			is_alternate = true

	if "damage_multiplier" in b:
		var damage_mult = b.damage_multiplier
		if is_alternate:
			var scale = b.alternate_damage_scale if "alternate_damage_scale" in b else 0.5
			var effective_mult = damage_mult * scale
			stats.append("Damage Mult: %.2fx (Alternate)" % effective_mult)
		else:
			stats.append("Damage Mult: %.2fx" % damage_mult)

	if "fire_rate" in b: stats.append("Fire Rate: %.2f/s" % b.fire_rate)
	if "attack_range" in b: stats.append("Range: %d Tiles" % int(b.attack_range))
	if "preferred_ammo_type" in b: stats.append("Preferred Ammo: %s" % b.preferred_ammo_type)
	if "compatible_ammo_types" in b and b.compatible_ammo_types.size() > 1:
		var compatible_list = ", ".join(b.compatible_ammo_types)
		stats.append("Compatible: %s" % compatible_list)
		
	var projectiles = b.projectiles_per_shot if "projectiles_per_shot" in b else 1
	var spread = b.spread_degrees if "spread_degrees" in b else 0.0
	if projectiles > 1:
		stats.append("Projectiles: %dx (%d° Spread)" % [projectiles, int(spread)])
	
	if "ammo_inventory" in b and "ammo_capacity" in b:
		if b.ammo_inventory.is_empty():
			stats.append("Ammo: Empty / %d" % b.ammo_capacity)
		else:
			stats.append("Ammo (%s): %d / %d" % [b.ammo_inventory[0].display_name, b.ammo_inventory.size(), b.ammo_capacity])



## Formats processor building crafting interval multipliers.
func _collect_processor_stats(b: Node2D, stats: Array):
	if "crafting_time_multiplier" in b:
		stats.append("Time Multiplier: %d%%" % int(b.crafting_time_multiplier * 100))


## Formats harvester area scanner radii and work speeds.
func _collect_harvester_stats(b: Node2D, stats: Array):
	if "scan_radius" in b: stats.append("Harvest Radius: %d" % b.scan_radius)
	if "harvest_damage" in b: stats.append("Harvest Amount: %d" % b.harvest_damage)
	if "work_interval" in b: stats.append("Work Interval: %.2fs" % b.work_interval)
