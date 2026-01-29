# HotbarUI.gd
extends Control

@onready var container = $PanelContainer/HBoxContainer

# Defines a signal that Level.gd will listen to
# data_wrapper can be a PackedScene (Building) or an Integer (Tile Index)
signal item_selected(data_wrapper, is_building)

func _ready():
	# Clear any placeholder buttons you added in editor
	for child in container.get_children():
		child.queue_free()

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

func _on_button_pressed(data, is_building):
	item_selected.emit(data, is_building)
