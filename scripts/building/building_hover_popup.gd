extends PanelContainer

@onready var name_label = $VBoxContainer/Name
@onready var health_label = $VBoxContainer/Health
@onready var inventory_box = $VBoxContainer/Inventory

# NEW NODE
@onready var work_bar = $VBoxContainer/WorkBar

var current_building: Building = null

func _ready():
	work_bar.visible = false

func _process(_delta):
	# SMOOTH ANIMATION LOOP
	# Only run this if the popup is visible and we are looking at a machine
	if visible and current_building is ProcessorBuilding:
		var b = current_building as ProcessorBuilding
		if b.has_method("get_progress_ratio"):
			work_bar.value = b.get_progress_ratio() * 100.0

func show_building_info(b: Building):
	# 1. Clean up previous connection
	if current_building and current_building.inventory_changed.is_connected(_on_inventory_changed):
		current_building.inventory_changed.disconnect(_on_inventory_changed)
	
	current_building = b
	
	# 2. Update Static Info
	name_label.text = b.building_name 
	health_label.text = "%d / %d" % [b.health, b.max_health]
	
	# 3. Connect Signal (Updates the text inventory)
	if not current_building.inventory_changed.is_connected(_on_inventory_changed):
		current_building.inventory_changed.connect(_on_inventory_changed)
	
	# 4. HANDLE PROGRESS BAR
	if b is ProcessorBuilding:
		work_bar.visible = true
	else:
		work_bar.visible = false
	
	# 5. Draw Initial State
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

	# Populate rows (Handles "Log: 5", "Plank: 10", etc.)
	for key in inventory.keys():
		var amount = inventory[key]
		var display_text = "Unknown"

		if key is Resource and "display_name" in key:
			display_text = key.display_name
		elif key is String:
			display_text = key
			
		var row := Label.new()
		row.text = "%s: %d" % [display_text, amount]
		inventory_box.add_child(row)

func hide_inventory():
	inventory_box.visible = false

func hide_popup():
	if current_building and current_building.inventory_changed.is_connected(_on_inventory_changed):
		current_building.inventory_changed.disconnect(_on_inventory_changed)
	
	current_building = null
	hide()
