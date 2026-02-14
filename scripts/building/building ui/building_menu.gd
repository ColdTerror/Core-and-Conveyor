extends PanelContainer

@onready var title_label = $VBoxContainer/TitleLabel
@onready var info_label = $VBoxContainer/InfoLabel # We reuse this label for both!
@onready var switch_button = $VBoxContainer/SwitchButton

var current_building: Building = null

func _ready():
	hide()
	
	# Connect signals if not already connected in editor
	if not switch_button.pressed.is_connected(_on_switch_pressed):
		switch_button.pressed.connect(_on_switch_pressed)
	
	if has_node("VBoxContainer/CloseButton"):
		$VBoxContainer/CloseButton.pressed.connect(close_menu)

func open_menu(building: Building):
	current_building = building
	
	# 1. Update Title
	title_label.text = building.building_name
	
	# 2. Refresh Context-Specific UI
	refresh_ui()
	
	show()

func refresh_ui():
	# Reset colors/visibility defaults
	info_label.modulate = Color.WHITE
	info_label.visible = true
	switch_button.visible = true

	# --- CASE A: PROCESSOR (Recipes) ---
	if current_building is ProcessorBuilding:
		_setup_processor_ui(current_building)

	# --- CASE B: STOCKPILE (Outputs) ---
	elif current_building is StockpileBuilding:
		_setup_stockpile_ui(current_building)

	# --- CASE C: GENERIC (Walls, Towers) ---
	else:
		info_label.text = "No configurable options."
		switch_button.visible = false

# --- HELPER: Setup UI for Factories ---
func _setup_processor_ui(b: ProcessorBuilding):
	switch_button.text = "Switch Recipe" # Update Button Text
	
	if b.recipes.size() > 0:
		info_label.text = "Recipe: %s" % b.active_recipe.recipe_name
		# Only show switch button if we actually have choices
		switch_button.visible = (b.recipes.size() > 1)
	else:
		info_label.text = "No Recipes Configured"
		switch_button.visible = false

# --- HELPER: Setup UI for Stockpiles ---
func _setup_stockpile_ui(b: StockpileBuilding):
	switch_button.text = "Cycle Output" # Update Button Text
	
	if b.selected_output_name == "":
		info_label.text = "Output: OFF"
		info_label.modulate = Color(1, 0.5, 0.5) # Red text for "OFF"
	else:
		info_label.text = "Output: %s" % b.selected_output_name
		info_label.modulate = Color(0.5, 1, 0.5) # Green text for Active

# --- ACTION HANDLER ---
func _on_switch_pressed():
	if not is_instance_valid(current_building): return

	# 1. Execute logic based on type
	if current_building is ProcessorBuilding:
		current_building.cycle_recipe()
		
	elif current_building is StockpileBuilding:
		# Ensure your StockpileBuilding script has this function!
		if current_building.has_method("cycle_output_mode"):
			print_debug("switching output")
			current_building.cycle_output_mode()
			
	# 2. Update text immediately
	refresh_ui()

func close_menu():
	current_building = null
	hide()
