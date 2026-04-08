extends Control
# game_ui.gd

@onready var inventoryContainer = $InventoryPanel/HBoxContainer
@onready var dateLabel = $VBoxContainer/DateLabel
@onready var waveLabel = $VBoxContainer/WaveLabel

# --- NEW: CORRUPTION UI REFERENCES ---
@onready var corruptionLabel = $VBoxContainer/CorruptionLabel
@onready var corruptionBar = $VBoxContainer/CorruptionBar

@onready var costPanel = $CostPanel
@onready var costLabel = $CostPanel/CostLabel

# --- MANAGER REFERENCES ---
@export var wave_manager: WaveManager 
@export var time_manager: TimeManager
@export var building_manager: BuildingManager
@export var corruption_manager: CorruptionManager # <--- DRAG YOUR CORRUPTION MANAGER HERE!

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

func update_labels():
	for resource_name in EconomyManager.global_inventory:
		var amount = EconomyManager.global_inventory[resource_name]
		if not resource_labels.has(resource_name):
			var new_label = Label.new()
			inventoryContainer.add_child(new_label)
			resource_labels[resource_name] = new_label
		resource_labels[resource_name].text = "  %s: %d  " % [resource_name, amount]


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
			var forecast = wave_manager.get_estimated_enemies()
			if forecast <= 0:
				waveLabel.text = "Full Moon Tonight... The forest is quiet."
				waveLabel.modulate = Color(0.6, 0.8, 1.0) # Soft moonlight blue!
			else:
				waveLabel.text = "Enemies Spawning Tonight: ~%d" % forecast
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
	
	# Move the costPanel to follow mouse
	if costPanel.visible: 
		var mouse_pos = get_viewport().get_mouse_position()
		costPanel.global_position = mouse_pos + Vector2(25, 25)
