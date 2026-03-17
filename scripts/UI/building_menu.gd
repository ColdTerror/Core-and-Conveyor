extends PanelContainer

@onready var title_label = $VBoxContainer/TitleLabel
@onready var info_label = $VBoxContainer/InfoLabel 
@onready var action_container = $VBoxContainer/ActionContainer # The dynamic folder!

@onready var close_button = $VBoxContainer/CloseButton

var current_building: Node2D = null

signal menu_closed

func _ready():
	hide()
	close_button.pressed.connect(close_menu)

func open_menu(building: Node2D):
	current_building = building
	title_label.text = building.building_name
	
	# --- NEW: LIVE UPDATES ---
	# Duck typing: Check if this object (Bot or Building) has the signal
	if current_building.has_signal("inventory_changed"):
		if not current_building.inventory_changed.is_connected(refresh_ui):
			current_building.inventory_changed.connect(refresh_ui)
	# -------------------------

	refresh_ui()
	show()

func refresh_ui():
	if not is_instance_valid(current_building): return
	
	# 1. Clean up ALL old dynamic buttons
	for child in action_container.get_children():
		child.queue_free()

	info_label.modulate = Color.WHITE
	info_label.visible = true

	# 2. Route to the correct UI builder
	if current_building is ProcessorBuilding:
		_setup_processor_ui(current_building as ProcessorBuilding)
	elif current_building is StockpileBuilding:
		_setup_stockpile_ui(current_building as StockpileBuilding)
	# --- NEW: ROUTE FOR TOWERS ---
	elif current_building is TowerBuilding:
		_setup_tower_ui(current_building as TowerBuilding)
	# --- NEW: ROUTE FOR BOTS (Duck Typing!) ---
	elif current_building.has_method("cycle_priority"):
		_setup_bot_ui(current_building)
	# ------------------------------------------
	else:
		info_label.text = "No configurable options."

# ==========================================================
# THE MAGIC HELPER: Spawns and wires a button instantly
# ==========================================================
func _create_button(btn_text: String, btn_color: Color, action_callable: Callable):
	var btn = Button.new()
	btn.text = btn_text
	btn.modulate = btn_color
	
	# Use a Lambda to call the building's function, then instantly refresh the UI!
	btn.pressed.connect(func():
		action_callable.call()
		refresh_ui() 
	)
	
	action_container.add_child(btn)
# ==========================================================


# --- HELPER: Setup UI for Factories ---
func _setup_processor_ui(b: ProcessorBuilding):
	if b.recipes.size() > 0:
		info_label.text = "Recipe: %s" % b.active_recipe.recipe_name
		
		# Only spawn the button if we actually have choices
		if b.recipes.size() > 1:
			_create_button("Switch Recipe", Color.WHITE, b.cycle_recipe)
	else:
		info_label.text = "No Recipes Configured"


# --- HELPER: Setup UI for Stockpiles ---
func _setup_stockpile_ui(b: StockpileBuilding):
	
	# 1. Setup Info Label
	if b.selected_output_name == "":
		info_label.text = "Output: OFF"
		info_label.modulate = Color(1, 0.5, 0.5) 
	else:
		info_label.text = "Output: %s" % b.selected_output_name
		info_label.modulate = Color(0.5, 1, 0.5) 

	# 2. Spawn MODE Button
	if b.has_method("toggle_inventory_mode"):
		var mode_text = "Mode: Dedicated (100)" if b.is_dedicated_mode else "Mode: Mixed (25)"
		var mode_color = Color(0.3, 0.8, 1.0) if b.is_dedicated_mode else Color(1.0, 0.8, 0.3)
		_create_button(mode_text, mode_color, b.toggle_inventory_mode)
		
	# 3. Spawn CYCLE OUTPUT Button (If ANY items exist in inventory!)
	if b.has_method("cycle_output_mode") and b.has_method("get_economy_assets"):
		var unique_item_types_count = b.get_economy_assets().keys().size()
		# --- FIXED: Changed from > 1 to > 0 ---
		if unique_item_types_count > 0: 
			_create_button("Cycle Output", Color.WHITE, b.cycle_output_mode)
			
	# 4. Spawn VOID Button
	if b.has_method("void_inventory"):
		_create_button("Void All Items", Color(1.0, 0.3, 0.3), b.void_inventory)

# --- HELPER: Setup UI for Towers ---
func _setup_tower_ui(b: TowerBuilding):
	info_label.text = "Priority: %s" % b.targeting_mode
	
	# Color code the text so it pops!
	match b.targeting_mode:
		"Closest": info_label.modulate = Color(0.8, 0.8, 1.0) # Light Blue
		"Strongest": info_label.modulate = Color(1.0, 0.4, 0.4) # Red
		"Weakest": info_label.modulate = Color(0.4, 1.0, 0.4) # Green
		"Furthest": info_label.modulate = Color(0.8, 0.4, 1.0) # Purple

	# Spawn the dynamic button
	_create_button("Cycle Targeting", Color.WHITE, b.cycle_targeting_mode)

# --- HELPER: Setup UI for Worker Bots ---
func _setup_bot_ui(b: Node2D):
	# 1. Pull the data we set up in the bot's script
	var info = b.get_inventory_info()
	
	# 2. Display what it's hunting and what's in its pockets
	info_label.text = "Target: %s\nCarrying: %s" % [info["Target"], info["Carrying"]]
	
	# Color code the text based on its target!
	if info["Target"] == "Wood Only":
		info_label.modulate = Color(0.6, 1.0, 0.6) # Green
	elif info["Target"] == "Stone Only":
		info_label.modulate = Color(0.6, 0.6, 1.0) # Blue
	else:
		info_label.modulate = Color(1.0, 1.0, 1.0) # White

	# 3. Spawn the dynamic button
	_create_button("Cycle Priority", Color(1.0, 0.8, 0.3), b.cycle_priority)

func close_menu():
	# --- NEW: CLEAN UP SIGNALS ---
	# We must disconnect so it doesn't try to update a closed menu!
	if is_instance_valid(current_building) and current_building.has_signal("inventory_changed"):
		if current_building.inventory_changed.is_connected(refresh_ui):
			current_building.inventory_changed.disconnect(refresh_ui)
	# -----------------------------
	
	current_building = null
	hide()
	menu_closed.emit()
