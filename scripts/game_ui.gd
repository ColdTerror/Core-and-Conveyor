extends Control
# game_ui.gd

@onready var container = $PanelContainer/HBoxContainer
@onready var waveLabel = $VBoxContainer/WaveLabel

# --- NEW: WAVE UI REFERENCES ---
@export var wave_manager: WaveManager # Drag your WaveManager node here in the Inspector!
@onready var wave_progress_bar = $VBoxContainer/WaveProgressBar # Adjust path if you put it inside a container

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
			container.add_child(new_label)
			resource_labels[resource_name] = new_label
			
		# Update the text of the existing label
		resource_labels[resource_name].text = "  %s: %d  " % [resource_name, amount]

# --- NEW: WAVE TIMER LOGIC ---
func _process(_delta):
	# Don't run if we haven't linked the manager or the progress bar
	if not wave_manager or not wave_progress_bar: 
		return
		
		
	if wave_manager.is_wave_active:
		# Wave is happening right now! Keep the bar full.
		wave_progress_bar.max_value = 1.0
		wave_progress_bar.value = 1.0
		
		
	else:
		# Cooldown phase: counting down to the next wave
		var time_left = wave_manager.wave_timer.time_left
		var total_time = wave_manager.wave_timer.wait_time
		
		# Update the bar (Fills up as time gets closer to 0)
		wave_progress_bar.max_value = total_time
		wave_progress_bar.value = total_time - time_left 
		
	if waveLabel:
			# --- NEW: Calculate the active enemies on the fly! ---
			var active_on_map = wave_manager.enemies_alive - wave_manager.enemies_to_spawn
			
			waveLabel.text = "Wave %d | Queue: %d | Active: %d" % [
				wave_manager.current_wave, 
				wave_manager.enemies_to_spawn, 
				active_on_map
			]
		
