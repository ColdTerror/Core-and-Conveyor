extends Control
# game_ui.gd

@onready var container = $PanelContainer/HBoxContainer

# --- NEW: WAVE UI REFERENCES ---
@export var wave_manager: WaveManager # Drag your WaveManager node here in the Inspector!
@onready var wave_progress_bar = $WaveProgressBar # Adjust path if you put it inside a container

var resource_labels: Dictionary = {}

func _ready():
	update_labels()
	EconomyManager.resources_changed.connect(_on_resources_changed)

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
		
	# Optional: If you added a Label as a child of the ProgressBar, grab it here
	var text_label = wave_progress_bar.get_node_or_null("Label")
		
	if wave_manager.is_wave_active:
		# Wave is happening right now! Keep the bar full.
		wave_progress_bar.max_value = 1.0
		wave_progress_bar.value = 1.0
		
		if text_label:
			text_label.text = "Wave %d Active! Enemies: %d" % [wave_manager.current_wave, wave_manager.enemies_alive]
			
	else:
		# Cooldown phase: counting down to the next wave
		var time_left = wave_manager.wave_timer.time_left
		var total_time = wave_manager.wave_timer.wait_time
		
		# Update the bar (Fills up as time gets closer to 0)
		wave_progress_bar.max_value = total_time
		wave_progress_bar.value = total_time - time_left 
		
		if text_label:
			text_label.text = "Next Wave in: %.1fs" % time_left
