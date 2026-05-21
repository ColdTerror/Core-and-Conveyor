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

signal item_selected(data_wrapper, is_building)

@export var building_manager: BuildingManager

var core_button: Button
var flash_tween: Tween



## Initializes the hotbar panel and connects global placement event signals.
func _ready():
	# Clear placeholder buttons
	for child in container.get_children():
		child.queue_free()
		
	# Listen for Core placement
	if building_manager:
		building_manager.core_placed_event.connect(_on_core_placed)



## Dynamically creates and registers a square selection button with bound action data inside the hotbar.
func add_button(label_text: String, icon_texture: Texture2D, data, is_building: bool):
	var btn = Button.new()
	btn.text = label_text
	btn.icon = icon_texture
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.expand_icon = true
	btn.custom_minimum_size = Vector2(64, 64)
	
	# Connect click event binding data
	btn.pressed.connect(_on_button_pressed.bind(data, is_building))
	
	container.add_child(btn)
	
	# Check for Core button to flash
	if label_text == "Core": 
		core_button = btn
		_start_core_flash()



## Purges all active selection buttons from the hotbar panel.
func clear_buttons():
	for child in container.get_children():
		child.queue_free()



## Emits selection data representing the pressed hotbar entry.
func _on_button_pressed(data, is_building):
	item_selected.emit(data, is_building)



## Triggers a looping pulse animation overlaying the core construction card until placed.
func _start_core_flash():
	if not core_button: return
	
	# Create a looping tween
	flash_tween = create_tween().set_loops()
	
	# Pulse to a highlighted yellow/green color
	var highlight_color = Color(0.5, 0.5, 0.0, 1.0)
	
	flash_tween.tween_property(core_button, "modulate", highlight_color, 0.6).set_trans(Tween.TRANS_SINE)
	flash_tween.tween_property(core_button, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)



## Halts core button flashing animations and restores standard button visuals when the core is constructed.
func _on_core_placed():
	# Halts animation and resets color when placed
	if flash_tween:
		flash_tween.kill()
		flash_tween = null
		
	if core_button:
		core_button.modulate = Color.WHITE



## Finds and deletes a hotbar action button by its matching label text.
func remove_button(button_name: String):
	# Loop through HBoxContainer buttons
	for child in container.get_children():
		if child is Button and child.text == button_name:
			child.queue_free()
			return
