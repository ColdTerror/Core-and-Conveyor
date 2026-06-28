# ==============================================================================
# Script: UI/game_ui.gd
# Purpose: Manages gameplay overlay panels including time clock, combat status,
#          forecast indicators, corruption details, safe zone overlays, and inventory tracking.
# Dependencies: Autoloads EconomyManager and ResearchManager. Requires references to
#               WaveManager, TimeManager, BuildingManager, CorruptionManager,
#               GameOverPanel and restart/exit buttons.
# Signals: None.
# ==============================================================================
extends Control

@onready var inventoryContainer = $InventoryPanel/HBoxContainer

@onready var overlayLabel = $VBoxContainer/OverlayLabel




@onready var costPanel = $CostPanel
@onready var costLabel = $CostPanel/CostLabel

@export var wave_manager: WaveManager 
@export var time_manager: TimeManager
@export var building_manager: BuildingManager
@export var corruption_manager: CorruptionManager

@onready var game_over_panel = $"../../GameOverPanel"
@onready var stats_label = $"../../GameOverPanel/VBoxContainer/Stats"
@onready var restart_button = $"../../GameOverPanel/VBoxContainer/Restart"
@onready var exit_button = $"../../GameOverPanel/VBoxContainer/Exit"

var resource_labels: Dictionary = {}

const DIGIT_SCENE = preload("res://scenes/ui/split_flap_digit.tscn")

var date_hud: HBoxContainer
var yr_digits: Array = []
var season_label: Label
var day_digits: Array = []
var time_separator: Label
var hour_digits: Array = []
var clock_divider: Label
var minute_digits: Array = []

var wave_hud: HBoxContainer
var wave_digits: Array = []
var queue_digits: Array = []
var active_digits: Array = []
var wave_status_label: Label

var corruption_hud: HBoxContainer
var corruption_digits: Array = []
var percent_digits: Array = []

var threshold_hud: HBoxContainer
var threshold_digits: Array = []
var threshold_lbl_right: Label



## Connects signals from EconomyManager, TimeManager, and BuildingManager, and hides the game over panel.
func _ready():
	update_labels()
	EconomyManager.inventory_changed.connect(_on_inventory_changed)
	
	if game_over_panel:
		game_over_panel.hide()
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if exit_button: 
		exit_button.pressed.connect(_on_exit_pressed)
	if building_manager:
		building_manager.placement_cost_updated.connect(_on_placement_cost_updated)
		building_manager.placement_ended.connect(_on_placement_ended)


	
	# Instantiate dynamic Date HUD
	date_hud = HBoxContainer.new()
	date_hud.alignment = HBoxContainer.ALIGNMENT_CENTER
	date_hud.add_theme_constant_override("separation", 4)
	$VBoxContainer.add_child(date_hud)
	# Move to top of VBoxContainer
	$VBoxContainer.move_child(date_hud, 0)
	
	var yr_pref = Label.new()
	yr_pref.text = "Yr "
	yr_pref.add_theme_font_size_override("font_size", 20)
	date_hud.add_child(yr_pref)
	yr_digits = _create_digit_list(date_hud, 2)
	
	season_label = Label.new()
	season_label.text = " Spring "
	season_label.add_theme_font_size_override("font_size", 20)
	date_hud.add_child(season_label)
	day_digits = _create_digit_list(date_hud, 1)
	
	time_separator = Label.new()
	time_separator.text = " "
	time_separator.add_theme_font_size_override("font_size", 20)
	date_hud.add_child(time_separator)
	
	hour_digits = _create_digit_list(date_hud, 2)
	
	clock_divider = Label.new()
	clock_divider.text = ":"
	clock_divider.add_theme_font_size_override("font_size", 20)
	date_hud.add_child(clock_divider)
	
	minute_digits = _create_digit_list(date_hud, 2)
	
	# Instantiate dynamic Wave HUD
	wave_hud = HBoxContainer.new()
	wave_hud.alignment = HBoxContainer.ALIGNMENT_CENTER
	wave_hud.add_theme_constant_override("separation", 4)
	$VBoxContainer.add_child(wave_hud)
	# Move after date_hud
	$VBoxContainer.move_child(wave_hud, 1)
	
	var wave_pref = Label.new()
	wave_pref.text = "Night "
	wave_pref.add_theme_font_size_override("font_size", 20)
	wave_hud.add_child(wave_pref)
	wave_digits = _create_digit_list(wave_hud, 2)
	
	var queue_lbl = Label.new()
	queue_lbl.text = "  Queue "
	queue_lbl.add_theme_font_size_override("font_size", 20)
	wave_hud.add_child(queue_lbl)
	queue_digits = _create_digit_list(wave_hud, 3)
	
	var active_lbl = Label.new()
	active_lbl.text = "  Active "
	active_lbl.add_theme_font_size_override("font_size", 20)
	wave_hud.add_child(active_lbl)
	active_digits = _create_digit_list(wave_hud, 3)
	
	wave_hud.hide() # Hidden by default until wave active
	
	# Status label for non-wave times
	wave_status_label = Label.new()
	wave_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_status_label.add_theme_font_size_override("font_size", 20)
	$VBoxContainer.add_child(wave_status_label)
	$VBoxContainer.move_child(wave_status_label, 2)

	# Instantiate dynamic Corruption HUD
	corruption_hud = HBoxContainer.new()
	corruption_hud.alignment = HBoxContainer.ALIGNMENT_CENTER
	corruption_hud.add_theme_constant_override("separation", 4)
	$VBoxContainer.add_child(corruption_hud)
	# Place at original label index
	$VBoxContainer.move_child(corruption_hud, 4)
	
	var corr_lbl = Label.new()
	corr_lbl.text = "Corruption Tier "
	corr_lbl.add_theme_font_size_override("font_size", 20)
	corr_lbl.modulate = Color(0.8, 0.2, 1.0)
	corruption_hud.add_child(corr_lbl)
	corruption_digits = _create_digit_list(corruption_hud, 2)
	
	var pct_space = Label.new()
	pct_space.text = "   "
	pct_space.add_theme_font_size_override("font_size", 20)
	corruption_hud.add_child(pct_space)
	
	percent_digits = _create_digit_list(corruption_hud, 2)
	
	var pct_lbl = Label.new()
	pct_lbl.text = "%"
	pct_lbl.add_theme_font_size_override("font_size", 20)
	pct_lbl.modulate = Color(0.8, 0.2, 1.0)
	corruption_hud.add_child(pct_lbl)
	
	# Instantiate dynamic Threshold HUD
	threshold_hud = HBoxContainer.new()
	threshold_hud.alignment = HBoxContainer.ALIGNMENT_CENTER
	threshold_hud.add_theme_constant_override("separation", 4)
	$VBoxContainer.add_child(threshold_hud)
	$VBoxContainer.move_child(threshold_hud, 4)
	
	var thresh_lbl_left = Label.new()
	thresh_lbl_left.text = "Threshold "
	thresh_lbl_left.add_theme_font_size_override("font_size", 20)
	thresh_lbl_left.modulate = Color(1.0, 0.8, 0.2)
	threshold_hud.add_child(thresh_lbl_left)
	
	threshold_digits = _create_digit_list(threshold_hud, 2)
	
	threshold_lbl_right = Label.new()
	threshold_lbl_right.text = "  [+ / -]   |   Numbers: OFF  [N]"
	threshold_lbl_right.add_theme_font_size_override("font_size", 20)
	threshold_lbl_right.modulate = Color(1.0, 0.8, 0.2)
	threshold_hud.add_child(threshold_lbl_right)
	
	threshold_hud.hide()

	# Guarantee vertical VBoxContainer sorting order (index 0 is top, 5 is bottom)
	$VBoxContainer.move_child(date_hud, 0)
	$VBoxContainer.move_child(wave_hud, 1)
	$VBoxContainer.move_child(wave_status_label, 2)
	$VBoxContainer.move_child(corruption_hud, 3)
	$VBoxContainer.move_child(threshold_hud, 4)

## Updates gameplay labels including the clock, wave forecast, corruption state, and safe grid metrics.
func _process(_delta):
	# Update the clock
	if time_manager:
		var time = time_manager.current_time
		var hours = int(time)
		var minutes = int((time - hours) * 60.0)
		
		var day_in_season = (time_manager.current_day - 1) % 7 + 1
		
		_set_digits_value(yr_digits, time_manager.get_current_year())
		season_label.text = " %s " % time_manager.get_season_name()
		_set_digits_value(day_digits, day_in_season)
		
		_set_digits_value(hour_digits, hours)
		_set_digits_value(minute_digits, minutes)

	# Update combat stats
	if wave_manager:
		var enemies_alive = get_tree().get_nodes_in_group("Enemies").size()
		
		if wave_manager.is_wave_active or enemies_alive > 0:
			wave_hud.show()
			wave_status_label.hide()
			
			_set_digits_value(wave_digits, wave_manager.current_wave)
			_set_digits_value(queue_digits, wave_manager.enemies_to_spawn)
			_set_digits_value(active_digits, enemies_alive)
			
			wave_hud.modulate = Color(1.0, 0.4, 0.4) 
		else:
			wave_hud.hide()
			wave_status_label.show()
			wave_hud.modulate = Color.WHITE
			
			# NO RESEARCH: Completely blind!
			if not ResearchManager.wave_measure:
				wave_status_label.text = "Night approaching..."
				wave_status_label.modulate = Color.WHITE
				
			# HAS RESEARCH: Show the forecast!
			else:
				var forecast = wave_manager.get_estimated_enemies()
				var moon_status = ""
				var is_full_moon = false
				var is_blood_moon = false
				
				# Does the player have Moon Measurement tech?
				if ResearchManager.moon_measure_level > 0 and time_manager:
					var current_time = time_manager.current_time
					var reveal_time = 16.0 if ResearchManager.moon_measure_level == 1 else 6.0
					
					if current_time >= reveal_time:
						match time_manager.current_moon_phase:
							TimeManager.MoonPhase.FULL:
								moon_status = " [FULL MOON]"
								is_full_moon = true
							TimeManager.MoonPhase.BLOOD:
								moon_status = " [BLOOD MOON]"
								is_blood_moon = true
							TimeManager.MoonPhase.NORMAL:
								moon_status = " [Normal Moon]"
					else:
						moon_status = " [Calculating Lunar Phase...]"
				
				# Apply the text and colors!
				if forecast <= 0 or is_full_moon:
					wave_status_label.text = "Full Moon Tonight... The forest is quiet."
					wave_status_label.modulate = Color(0.6, 0.8, 1.0) # Soft moonlight blue
				else:
					wave_status_label.text = "Enemies Spawning Tonight: ~%d%s" % [forecast, moon_status]
					
					if is_blood_moon:
						wave_status_label.modulate = Color(1.0, 0.2, 0.2) # Deep Red for Blood Moon warning
					else:
						wave_status_label.modulate = Color.WHITE
						
	# Update corruption UI with safety checks
	if corruption_manager:
		var tier = corruption_manager.corruption_tier
		var pressure = corruption_manager.current_pressure
		
		# Do the exact same math the CorruptionManager does to find the ceiling!
		var threshold = corruption_manager.base_evolution_threshold * pow(corruption_manager.evolution_multiplier, tier - 1)
		
		_set_digits_value(corruption_digits, tier)
		
		var pct = 0
		if threshold > 0:
			pct = clamp(int((pressure / threshold) * 100.0), 0, 99)
		_set_digits_value(percent_digits, pct)
	
	# Update overlay threshold UI
	if building_manager and threshold_hud:
		if building_manager.show_safe_grid or building_manager.show_attack_grid:
			threshold_hud.show()
			_set_digits_value(threshold_digits, building_manager.overlay_threshold)
			var num_status = "ON" if building_manager.show_overlay_numbers else "OFF"
			threshold_lbl_right.text = "  [+ / -]   |   Numbers: %s  [N]" % num_status
		else:
			threshold_hud.hide()
	
	# Move the costPanel to follow mouse
	if costPanel.visible: 
		var mouse_pos = get_viewport().get_mouse_position()
		costPanel.global_position = mouse_pos + Vector2(25, 25)



## Refreshes pinning inventory slots in the top HUD panel with current count and in-transit numbers.
func update_labels():
	# Hide all existing labels
	for key in resource_labels.keys():
		resource_labels[key].hide()

	# Get the full unsecured map once to avoid calling it in the loop
	var unsecured_map = EconomyManager.get_unsecured_inventory()

	# Loop through ONLY the pinned list (capped at 5 items to prevent HUD overlaps)
	var max_slots = min(EconomyManager.pinned_resources.size(), 5)
	for i in range(max_slots):
		var resource_name = EconomyManager.pinned_resources[i]
		
		# Grab both values
		var secured = EconomyManager.global_inventory.get(resource_name, 0)
		var in_transit = unsecured_map.get(resource_name, 0)

		# Create the resource HUD item if it doesn't exist yet
		if not resource_labels.has(resource_name):
			var item_scene = load("res://scenes/ui/resource_hud_item.tscn")
			var new_item = item_scene.instantiate()
			inventoryContainer.add_child(new_item)
			new_item.setup(resource_name)
			resource_labels[resource_name] = new_item

		# Update values on the custom split-flap widget
		var item = resource_labels[resource_name]
		item.update_values(secured, in_transit)
		item.show()
		inventoryContainer.move_child(item, i)



## Updates and shows the float cost panel trailing the mouse cursor when placing structures.
func _on_placement_cost_updated(b_name: String, total_cost: Dictionary, can_afford: bool, extra_stats: Dictionary = {}):
	costPanel.show()
	
	var text = "[ %s ]\n" % b_name
	
	if total_cost.is_empty():
		if "Max Tier" in b_name:
			text += "No further upgrades.\n"
		else:
			text += "Free to build!\n"
	else:
		for res in total_cost:
			var needed = total_cost[res]
			var have = EconomyManager.global_inventory.get(res, 0)
			text += "%s: %d / %d\n" % [res, have, needed]
			
	if not extra_stats.is_empty():
		for stat_name in extra_stats:
			text += "%s: %s\n" % [stat_name, extra_stats[stat_name]]
			
	costLabel.text = text.strip_edges()
	
	if total_cost.is_empty() and "Max Tier" in b_name:
		costLabel.modulate = Color(0.7, 0.7, 0.7) 
	elif can_afford:
		costLabel.modulate = Color(0.4, 1.0, 0.4) 
	else:
		costLabel.modulate = Color(1.0, 0.4, 0.4)



## Hides the floating structure placement cost card when building completes or cancels.
func _on_placement_ended():
	costPanel.hide()



## Reveals the game over summary panel showing the final wave count upon the player's core destruction.
func _on_core_destroyed():
	if game_over_panel:
		game_over_panel.show()
		if wave_manager:
			stats_label.text = "You survived until Wave %d." % wave_manager.current_wave



## Resets inventories and reload-unpauses the game scene to begin a new round.
func _on_restart_pressed():
	get_tree().paused = false 
	EconomyManager.global_inventory.clear()
	EconomyManager.inventory_changed.emit()
	get_tree().reload_current_scene()



## Closes the application.
func _on_exit_pressed():
	get_tree().quit()



## Signal receiver that triggers standard UI HUD updates when player stock levels shift.
func _on_inventory_changed():
	update_labels()


func _create_digit_list(parent: HBoxContainer, num_digits: int) -> Array:
	var list = []
	for i in range(num_digits):
		var d = DIGIT_SCENE.instantiate()
		parent.add_child(d)
		d.set_size_custom(20, 30, 20)
		list.append(d)
	return list


func _set_digits_value(digits_arr: Array, val: int):
	var num_digits = digits_arr.size()
	var val_str = str(val)
	if val_str.length() > num_digits:
		val_str = val_str.substr(val_str.length() - num_digits)
	else:
		while val_str.length() < num_digits:
			val_str = "0" + val_str
	for i in range(num_digits):
		digits_arr[i].set_target_character(val_str[i])
