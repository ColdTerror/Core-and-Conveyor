extends PanelContainer

@onready var name_label = $VBoxContainer/Name
@onready var health_label = $VBoxContainer/Health
@onready var inventory_box = $VBoxContainer/Inventory

var current_building: Building = null

func show_building_info(b: Building):
	# 1. Clean up previous connection if switching buildings fast
	if current_building and current_building.inventory_changed.is_connected(_on_inventory_changed):
		current_building.inventory_changed.disconnect(_on_inventory_changed)
	
	current_building = b
	
	# 2. Update Static Info
	name_label.text = b.building_name
	health_label.text = "%d / %d" % [b.health, b.max_health]
	
	# 3. Connect Signal for Live Updates
	if not current_building.inventory_changed.is_connected(_on_inventory_changed):
		current_building.inventory_changed.connect(_on_inventory_changed)
	
	# 4. Draw Initial State
	_refresh_inventory_ui()
	show()

func _on_inventory_changed():
	_refresh_inventory_ui()

func _refresh_inventory_ui():
	if not current_building: return
	
	var info = current_building.get_inventory_info()
	
	if not info.is_empty():
		show_inventory(info)
	else:
		hide_inventory()

func show_inventory(inventory: Dictionary):
	inventory_box.visible = true

	# Clear previous rows
	for child in inventory_box.get_children():
		child.queue_free()

	# Populate rows
	for key in inventory.keys():
		var amount = inventory[key]
		var display_text = "Unknown"

		# Handle Resource Objects (TileDataResource / ItemResource)
		if key is Resource and "display_name" in key:
			display_text = key.display_name
		# Handle Simple Strings (fallback)
		elif key is String:
			display_text = key
			
		var row := Label.new()
		row.text = "%s: %d" % [display_text, amount]
		inventory_box.add_child(row)

func hide_inventory():
	inventory_box.visible = false

func hide_popup():
	# Clean up connection when hiding
	if current_building and current_building.inventory_changed.is_connected(_on_inventory_changed):
		current_building.inventory_changed.disconnect(_on_inventory_changed)
	
	current_building = null
	hide()
