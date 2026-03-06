extends Control
# game_ui.gd

@onready var inventoryContainer = $InventoryPanel/HBoxContainer
@onready var dateLabel = $VBoxContainer/DateLabel
@onready var waveLabel = $VBoxContainer/WaveLabel

@onready var costPanel = $CostPanel
@onready var costLabel = $CostPanel/CostLabel

# --- NEW: WAVE UI REFERENCES ---
@export var wave_manager: WaveManager # Drag your WaveManager node here in the Inspector!
@export var time_manager: TimeManager
@export var building_manager: BuildingManager

# --- NEW: GAME OVER REFERENCES ---
@onready var game_over_panel = $"../../GameOverPanel"
@onready var stats_label = $"../../GameOverPanel/VBoxContainer/Stats"
@onready var restart_button = $"../../GameOverPanel/VBoxContainer/Restart"
@onready var exit_button = $"../../GameOverPanel/VBoxContainer/Exit"


var resource_labels: Dictionary = {}

func _ready():
	update_labels()
	EconomyManager.resources_changed.connect(_on_resources_changed)
	
	# Hide the panel at the start, connect the restart button
	if game_over_panel:
		game_over_panel.hide()
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if exit_button: 
		exit_button.pressed.connect(_on_exit_pressed)
	if building_manager:
		building_manager.placement_cost_updated.connect(_on_placement_cost_updated)
		building_manager.placement_ended.connect(_on_placement_ended)

func _on_placement_cost_updated(b_name: String, total_cost: Dictionary, can_afford: bool):
	costPanel.show()
	
	var text = "[ %s ]\n" % b_name
	
	for res in total_cost:
		var needed = total_cost[res]
		var have = EconomyManager.global_inventory.get(res, 0)
		text += "%s: %d / %d\n" % [res, have, needed]
		
	costLabel.text = text
	
	# Tint green if good, red if broke!
	if can_afford:
		costLabel.modulate = Color(0.4, 1.0, 0.4) 
	else:
		costLabel.modulate = Color(1.0, 0.4, 0.4)

func _on_placement_ended():
	costPanel.hide()

# --- GAME OVER LOGIC ---
func _on_core_destroyed():
	if game_over_panel:
		game_over_panel.show()
		
		# Pull the wave count directly from the wave manager!
		if wave_manager:
			stats_label.text = "You survived until Wave %d." % wave_manager.current_wave

func _on_restart_pressed():
	# 1. MUST unpause the tree before reloading!
	get_tree().paused = false 
	
	# 2. Reset the Economy so you don't start the next game with leftover wood
	EconomyManager.global_inventory.clear()
	EconomyManager.resources_changed.emit()
	
	# 3. Reload the level
	get_tree().reload_current_scene()

func _on_exit_pressed():
	# Closes the game entirely
	get_tree().quit()
	
func _on_resources_changed():
	update_labels()

func update_labels():
	# Loop through every item currently known to the economy
	for resource_name in EconomyManager.global_inventory:
		var amount = EconomyManager.global_inventory[resource_name]
		
		# If we don't have a label for this item yet, create one!
		if not resource_labels.has(resource_name):
			var new_label = Label.new()
			inventoryContainer.add_child(new_label)
			resource_labels[resource_name] = new_label
			
		# Update the text of the existing label
		resource_labels[resource_name].text = "  %s: %d  " % [resource_name, amount]


# --- NEW: WAVE & TIMER LOGIC ---
func _process(_delta):
	# 1. UPDATE THE CLOCK (DateLabel)
	if time_manager and dateLabel:
		# Convert the float time (e.g. 14.5) to Hours and Minutes (14:30)
		var time = time_manager.current_time
		var hours = int(time)
		var minutes = int((time - hours) * 60.0)
		
		# "%02d" ensures single digits get a leading zero (e.g., 9 becomes 09)
		var time_string = "%02d:%02d" % [hours, minutes]
		
		dateLabel.text = "Day %d | %s" % [time_manager.current_day, time_string]


	# 2. UPDATE THE COMBAT STATS (WaveLabel)
	if wave_manager and waveLabel:
		
		# --- FIXED: SINGLE SOURCE OF TRUTH ---
		# Physically count the nodes in the scene. Impossible to be negative!
		var enemies_alive = get_tree().get_nodes_in_group("Enemies").size()
		
		# --- FIXED: UI HOLD LOGIC ---
		# Keep the UI on "Night Mode" if the clock says it's night, 
		# OR if there are still enemies alive on the map!
		if wave_manager.is_wave_active or enemies_alive > 0:
			
			waveLabel.text = "Night %d | Queue: %d | Active: %d" % [
				wave_manager.current_wave, 
				wave_manager.enemies_to_spawn, 
				enemies_alive # <--- Using our foolproof node count!
			]
			waveLabel.modulate = Color(1.0, 0.4, 0.4) # Tint text red to indicate danger!
			
		else:
			# Daytime AND map is totally clean! 
			var forecast = wave_manager.get_estimated_enemies()
			
			# Using a "~" adds a nice touch of "this is an estimate!"
			waveLabel.text = "Enemies Spawning Tonight: ~%d" % forecast
			waveLabel.modulate = Color.WHITE # Back to normal text color
