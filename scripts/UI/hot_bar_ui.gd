# ==============================================================================
# Script: UI/hot_bar_ui.gd
# Purpose: Controls the build/select hotbar, dynamic button creation, selection emission,
#          and core placement flashing animations.
# Dependencies: Exports for BuildingManager.
# Signals:
#   - item_selected(data_wrapper, is_building): Emitted when a hotbar button is pressed.
# ==============================================================================
extends Control

@onready var container = $PanelContainer/HBoxContainer

# Defines a signal that Level.gd will listen to
# data_wrapper can be a PackedScene (Building) or an Integer (Tile Index)
signal item_selected(data_wrapper, is_building)

# --- NEW: CORE FLASHING REFERENCES ---
@export var building_manager: BuildingManager # Drag your BuildingManager here in the Inspector!
var core_button: Button
var flash_tween: Tween
# -------------------------------------

func _ready():
	# Clear any placeholder buttons you added in editor
	for child in container.get_children():
		child.queue_free()
		
	# Listen for the Core placement signal!
	if building_manager:
		building_manager.core_placed_event.connect(_on_core_placed)

# Function to add a button dynamically
func add_button(label_text: String, icon_texture: Texture2D, data, is_building: bool):
	var btn = Button.new()
	btn.text = label_text
	btn.icon = icon_texture
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.expand_icon = true
	btn.custom_minimum_size = Vector2(64, 64) # Big square buttons
	
	# Connect the click event
	# We bind the specific data to the signal so we know what was clicked
	btn.pressed.connect(_on_button_pressed.bind(data, is_building))
	
	container.add_child(btn)
	
	# --- NEW: CATCH THE CORE BUTTON ---
	# IMPORTANT: Make sure "Core" perfectly matches whatever text you pass into this function!
	if label_text == "Core": 
		core_button = btn
		_start_core_flash()
	# ----------------------------------


func clear_buttons():
	for child in container.get_children():
		child.queue_free()

func _on_button_pressed(data, is_building):
	item_selected.emit(data, is_building)

# ANIMATION LOGIC
func _start_core_flash():
	if not core_button: return
	
	# Create a tween that loops forever
	flash_tween = create_tween().set_loops()
	
	# Pulse to a bright greenish/yellow, then back to normal white
	var highlight_color = Color(0.5, 0.5, 0.0, 1.0) # Overdriving values makes it glow!
	
	flash_tween.tween_property(core_button, "modulate", highlight_color, 0.6).set_trans(Tween.TRANS_SINE)
	flash_tween.tween_property(core_button, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)

func _on_core_placed():
	# The Core is down! Kill the animation and reset the color.
	if flash_tween:
		flash_tween.kill()
		flash_tween = null
		
	if core_button:
		core_button.modulate = Color.WHITE
		
# UTILITY LOGIC
func remove_button(button_name: String):
	# Loop through all the buttons inside the HBoxContainer
	for child in container.get_children():
		# Check if it's a button and if the text matches
		if child is Button and child.text == button_name:
			child.queue_free() # Destroy it!
			return # Stop searching since we found it
