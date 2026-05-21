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
@onready var dateLabel = $VBoxContainer/DateLabel
@onready var waveLabel = $VBoxContainer/WaveLabel

# --- NEW: OVERLAY UI REFERENCE ---
@onready var overlayLabel = $VBoxContainer/OverlayLabel

# --- NEW: CORRUPTION UI REFERENCES ---
@onready var corruptionLabel = $VBoxContainer/CorruptionLabel
@onready var corruptionBar = $VBoxContainer/CorruptionBar

@onready var costPanel = $CostPanel
@onready var costLabel = $CostPanel/CostLabel

# --- MANAGER REFERENCES ---
@export var wave_manager: WaveManager 
@export var time_manager: TimeManager
@export var building_manager: BuildingManager
@export var corruption_manager: CorruptionManager

# --- GAME OVER REFERENCES ---
@onready var game_over_panel = $"../../GameOverPanel"
@onready var stats_label = $"../../GameOverPanel/VBoxContainer/Stats"
@onready var restart_button = $"../../GameOverPanel/VBoxContainer/Restart"
@onready var exit_button = $"../../GameOverPanel/VBoxContainer/Exit"

var resource_labels: Dictionary = {}

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

# --- PROCESS LOOP (UI UPDATES) ---
func _process(_delta):
	# 1. UPDATE THE CLOCK
	if time_manager and dateLabel:
		var time = time_manager.current_time
		var hours = int(time)
		var minutes = int((time - hours) * 60.0)
		var time_string = "%02d:%02d" % [hours, minutes]
		
		dateLabel.text = "Day %d | %s" % [time_manager.current_day, time_string]

	# 2. UPDATE THE COMBAT STATS
	if wave_manager and waveLabel:
		var enemies_alive = get_tree().get_nodes_in_group("Enemies").size()
		
		if wave_manager.is_wave_active or enemies_alive > 0:
			waveLabel.text = "Night %d | Queue: %d | Active: %d" % [
				wave_manager.current_wave, 
				wave_manager.enemies_to_spawn, 
				enemies_alive
			]
			waveLabel.modulate = Color(1.0, 0.4, 0.4) 
		else:
			# --- RESEARCH GATED FORECAST ---
			
			# NO RESEARCH: Completely blind!
			if not ResearchManager.wave_measure:
				waveLabel.text = "Night approaching..."
				waveLabel.modulate = Color.WHITE
				
			# HAS RESEARCH: Show the forecast!
			else:
				var forecast = wave_manager.get_estimated_enemies()
				var moon_status = ""
				var is_full_moon = false
				var is_blood_moon = false
				
				# Does the player have Moon Measurement tech?
				if ResearchManager.moon_measure_level > 0 and time_manager:
					var current_time = time_manager.current_time
					
					# Level 1 reveals at 16:00 (4 PM). Level 2 reveals instantly at 6:00 (Dawn).
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
					waveLabel.text = "Full Moon Tonight... The forest is quiet."
					waveLabel.modulate = Color(0.6, 0.8, 1.0) # Soft moonlight blue
				else:
					waveLabel.text = "Enemies Spawning Tonight: ~%d%s" % [forecast, moon_status]
					
					if is_blood_moon:
						waveLabel.modulate = Color(1.0, 0.2, 0.2) # Deep Red for Blood Moon warning
					else:
						waveLabel.modulate = Color.WHITE
						
	# --- NEW: 3. UPDATE CORRUPTION UI ---
	# We added safety checks (if corruptionLabel) so the game doesn't crash 
	# if you haven't created the nodes in the editor yet!
	if corruption_manager and corruptionLabel and corruptionBar:
		var tier = corruption_manager.corruption_tier
		var pressure = corruption_manager.current_pressure
		
		# Do the exact same math the CorruptionManager does to find the ceiling!
		var threshold = corruption_manager.base_evolution_threshold * pow(corruption_manager.evolution_multiplier, tier - 1)
		
		corruptionLabel.text = "Corruption Tier: %d" % tier
		corruptionBar.max_value = threshold
		corruptionBar.value = pressure
		
		# Optional: Tint the text so it looks dangerous
		corruptionLabel.modulate = Color(0.8, 0.2, 1.0) # Purple!
		corruptionBar.modulate = Color(0.8, 0.2, 1.0)
	# ------------------------------------
	
	# --- NEW: 4. UPDATE OVERLAY THRESHOLD UI ---
	if building_manager and overlayLabel:
		if building_manager.show_safe_grid or building_manager.show_attack_grid:
			
			# --- NEW: Format the text to show the live status of both controls! ---
			var num_status = "ON" if building_manager.show_overlay_numbers else "OFF"
			overlayLabel.text = "Threshold: %d  [+ / -]   |   Numbers: %s  [N]" % [building_manager.overlay_threshold, num_status]
			
			overlayLabel.modulate = Color(1.0, 0.8, 0.2)
			overlayLabel.show()
		else:
			overlayLabel.hide()
	# -------------------------------------------
	
	# Move the costPanel to follow mouse
	if costPanel.visible: 
		var mouse_pos = get_viewport().get_mouse_position()
		costPanel.global_position = mouse_pos + Vector2(25, 25)


func update_labels():
	# 1. Hide all existing labels
	for key in resource_labels.keys():
		resource_labels[key].hide()

	# 2. Get the full unsecured map once to avoid calling it in the loop
	var unsecured_map = EconomyManager.get_unsecured_inventory()

	# 3. Loop through ONLY the pinned list (capped at 10 items)
	var max_slots = min(EconomyManager.pinned_resources.size(), 10)
	for i in range(max_slots):
		var resource_name = EconomyManager.pinned_resources[i]
		
		# Grab both values
		var secured = EconomyManager.global_inventory.get(resource_name, 0)
		var in_transit = unsecured_map.get(resource_name, 0)

		# Create the label if it doesn't exist yet
		if not resource_labels.has(resource_name):
			var new_label = Label.new()
			inventoryContainer.add_child(new_label)
			resource_labels[resource_name] = new_label

		# Update the text with the "(+X)" format if in_transit > 0
		var lbl = resource_labels[resource_name]
		
		var display_text = "  %s: %d" % [resource_name, secured]
		if in_transit > 0:
			display_text += " (+%d)" % in_transit
		display_text += "  " # Trailing space for padding
		
		lbl.text = display_text
		lbl.show()
		inventoryContainer.move_child(lbl, i)

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
		
func _on_placement_ended():
	costPanel.hide()

# --- GAME OVER LOGIC ---
func _on_core_destroyed():
	if game_over_panel:
		game_over_panel.show()
		if wave_manager:
			stats_label.text = "You survived until Wave %d." % wave_manager.current_wave

func _on_restart_pressed():
	get_tree().paused = false 
	EconomyManager.global_inventory.clear()
	EconomyManager.inventory_changed.emit()
	get_tree().reload_current_scene()

func _on_exit_pressed():
	get_tree().quit()
	
func _on_inventory_changed():
	update_labels()
