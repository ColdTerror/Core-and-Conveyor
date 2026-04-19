extends PanelContainer

@onready var title_label = $VBoxContainer/TitleLabel
@onready var info_label = $VBoxContainer/InfoLabel 
@onready var action_container = $VBoxContainer/ActionContainer # The dynamic folder!

@onready var close_button = $VBoxContainer/CloseButton

@export var building_manager: BuildingManager

var current_building: Node2D = null
var bot_awaiting_home: Node2D = null # --- NEW: Remembers the bot while waiting for a click! ---

signal menu_closed
signal research_button_clicked

func _ready():
	hide()
	close_button.pressed.connect(close_menu)
	
	info_label.custom_minimum_size = Vector2(225, 50) 

func open_menu(building: Node2D):
	if is_instance_valid(current_building) and current_building != building:
		if "is_selected" in current_building:
			current_building.is_selected = false
			current_building.queue_redraw()
	
	current_building = building
	title_label.text = building.building_name
	
	if "is_selected" in current_building:
		current_building.is_selected = true
		current_building.queue_redraw()
		


	if current_building.has_signal("inventory_changed"):
		if not current_building.inventory_changed.is_connected(refresh_ui):
			current_building.inventory_changed.connect(refresh_ui)


	refresh_ui()
	show()

func refresh_ui():
	if not is_instance_valid(current_building): return
	
	# 1. Clean up ALL old dynamic buttons
	for child in action_container.get_children():
		child.queue_free()

	info_label.modulate = Color.WHITE
	info_label.visible = true

	# ==========================================
	# UNIVERSAL FOCUS/FOLLOW BUTTON
	# ==========================================
	# Duck-type check: Is it a bot or a building?
	var focus_text = "Follow Bot" if current_building.has_method("set_priority") else "Center Camera"
	
	_create_button(focus_text, Color(0.9, 0.9, 0.9), func():
		var cam = get_tree().get_first_node_in_group("Camera")
		if cam and cam.has_method("set_follow_target"):
			cam.set_follow_target(current_building)
	)
	# ==========================================
	
	
	# ==========================================
	# --- UNIVERSAL RELOCATE BUTTON ---
	# ==========================================
	# Exclude Cores, Filters, and Bots from being relocated
	var can_relocate = not (current_building is CoreBuilding or current_building is TerraformSite or current_building is ConstructionSite or current_building is WallBuilding or current_building is ConveyorBuilding or current_building.has_method("set_priority"))
	
	if can_relocate:
		_create_button("Relocate (Lose Inventory)", Color(0.8, 0.4, 1.0), func():
			if building_manager.has_method("start_relocating"):
				building_manager.start_relocating(current_building)
				close_menu() # Close the menu so they can place the ghost!
		)
	# ==========================================
	
	# 2. Route to the correct UI builder
	if current_building is ProcessorBuilding:
		_setup_processor_ui(current_building as ProcessorBuilding)
	elif current_building is StockpileBuilding:
		_setup_stockpile_ui(current_building as StockpileBuilding)
	elif current_building is TowerBuilding:
		_setup_tower_ui(current_building as TowerBuilding)
	elif current_building is CoreBuilding:
		_setup_core_ui(current_building as CoreBuilding)
	elif current_building.has_method("set_priority"):
		_setup_bot_ui(current_building)
	elif current_building is FilterBuilding:
		_setup_filter_ui(current_building as FilterBuilding)
	else:
		info_label.text = "No configurable options."
		
	if not current_building.has_method("set_priority"):
		_build_priority_widget(current_building)

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
		var recipe = b.active_recipe
		var details = "Recipe: %s\n" % recipe.recipe_name
		
		# --- 1. FORMAT INPUTS ---
		# Loop through the Dictionary keys (ItemResource) and get the value (Amount)
		if recipe.inputs.size() > 0:
			details += "[Requires]"
			for item_res in recipe.inputs.keys():
				var amount = recipe.inputs[item_res]
				# Fallback just in case a resource is empty/null
				var item_name = item_res.display_name if item_res != null else "Unknown Item" 
				details += "\n • %d %s" % [amount, item_name]
				
		# --- 2. FORMAT OUTPUT ---
		# Grab the single output item directly!
		if recipe.output_item != null:
			details += "\n[Produces]"
			details += "\n • %d %s" % [recipe.output_count, recipe.output_item.display_name]
		
		# Apply the final formatted string!
		info_label.text = details.strip_edges()
		
		# 3. Only spawn the button if we actually have choices
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

func _setup_core_ui(b: CoreBuilding):
	info_label.modulate = Color(0.8, 0.8, 1.0)
	
	# Are we currently researching something?
	if b.active_research_name != "":
		info_label.text = ""
		info_label.text += "\n\nResearching: %s" % b.active_research_name
		
		# Loop through the bill and print the progress (e.g., "Wood: 20 / 50")
		for item_name in b.research_bill_max.keys():
			var max_required = b.research_bill_max[item_name]
			var still_needed = b.research_bill.get(item_name, 0)
			var currently_deposited = max_required - still_needed
			
			info_label.text += "\n%s: %d / %d" % [item_name.display_name, currently_deposited, max_required]
			
		# Optional: Add a cancel button!
		_create_button("Cancel Research", Color(1.0, 0.4, 0.4), func():
			b.active_research_name = ""
			b.research_bill.clear()
			b.research_bill_max.clear()
			refresh_ui()
		)
		
	else:
		info_label.text = "No Current Research"
		# Only allow opening the Tech Tree if we AREN'T currently researching
		_create_button("Open Research Tree", Color(1.0, 0.84, 0.0), func(): 
			research_button_clicked.emit()
		)

# --- HELPER: Setup UI for Worker Bots ---
func _setup_bot_ui(b: Node2D):
	var info = b.get_inventory_info()
	info_label.text = "Target: %s\nCarrying: %s" % [info["Target"], info["Carrying"]]
	
	if info["Target"] == "Wood Only": info_label.modulate = Color(0.6, 1.0, 0.6)
	elif info["Target"] == "Stone Only": info_label.modulate = Color(0.785, 0.785, 0.785, 1.0)
	elif info["Target"] == "Maintain": info_label.modulate = Color(0.2, 0.6, 1.0)
	elif info["Target"] == "Home": info_label.modulate = Color(1.0, 0.4, 0.4)
	else: info_label.modulate = Color(1.0, 1.0, 1.0)

	# RTS Command Panel
	_create_button("Wood Only", Color(0.6, 1.0, 0.6), func(): b.set_priority(0))
	_create_button("Stone Only", Color(0.785, 0.785, 0.785, 1.0), func(): b.set_priority(1))
	_create_button("Maintain", Color(0.2, 0.6, 1.0), func(): b.set_priority(2))
	_create_button("Go Home", Color(1.0, 0.4, 0.4), func(): b.set_priority(3))
	
	# --- NEW: Set Home Button ---
	_create_button("Set Home", Color(1.0, 0.8, 0.2), func(): 
		bot_awaiting_home = b
		if b.has_method("toggle_set_home_mode"):
			b.toggle_set_home_mode(true) # Tell the bot to start drawing!
		print("Targeting Mode ON: Click a tile to set home.")
	)

# --- Setup UI for Filters ---
func _setup_filter_ui(b: FilterBuilding):
	var current_filter = b.filter_options[b.current_filter_index]
	var mode_text = "Output: Sides" if b.is_split_mode else "Output: Forward"
	
	info_label.text = "Filtering: %s\nMode: %s" % [current_filter, mode_text]
	info_label.modulate = Color(0.4, 1.0, 0.4) if current_filter != "None" else Color.WHITE
	
	# Button 1: Change what we are filtering
	_create_button("Cycle Item", Color.WHITE, b.cycle_filter)
	
	# Button 2: Change where that item goes
	_create_button("Change Mode", Color(0.3, 0.8, 1.0), b.toggle_filter_mode)

func _build_priority_widget(b: Node):
	# 1. Grab the building manager safely through the building's level reference!
	if building_manager == null: 
		print("Widget failed: Building Manager is not assigned in the Inspector!")
		return
	var bm = building_manager
	
	# 2. Figure out if we are ranking the specific building, or its whole group!
	var priority_item = b
	if b is ConveyorBuilding:
		priority_item = "Belts"
	elif b is WallBuilding: # Make sure this matches your wall class!
		priority_item = "Walls"
		
	var current_rank = bm.get_priority_rank(priority_item)
	var max_rank = bm.get_total_priority_ranks()
	
	# If the building somehow isn't in the list, skip drawing the widget
	if current_rank == 0: return

	# 3. Create the Horizontal Row
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# 4. Create UP Button (Moves closer to Rank 1)
	var up_btn = Button.new()
	up_btn.text = " ▲ "
	up_btn.disabled = (current_rank == 1) # Disable if it's already #1!
	up_btn.pressed.connect(func():
		bm.move_priority_up(priority_item)
		refresh_ui() # Redraw the menu to update the numbers!
	)
	
	# 5. Create the Text Label
	var rank_label = Label.new()
	rank_label.text = "  Priority: %d / %d  " % [current_rank, max_rank]
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# 6. Create DOWN Button (Moves further from Rank 1)
	var down_btn = Button.new()
	down_btn.text = " ▼ "
	down_btn.disabled = (current_rank == max_rank) # Disable if it's dead last!
	down_btn.pressed.connect(func():
		bm.move_priority_down(priority_item)
		refresh_ui()
	)
	
	# 7. Assemble the widget
	hbox.add_child(up_btn)
	hbox.add_child(rank_label)
	hbox.add_child(down_btn)
	
	# 8. Add it to your action container! (Replaced menu_vbox)
	action_container.add_child(hbox)
	
func close_menu():
	# CLEAN UP SIGNALS
	if is_instance_valid(current_building):
		if current_building.has_signal("inventory_changed"):
			if current_building.inventory_changed.is_connected(refresh_ui):
				current_building.inventory_changed.disconnect(refresh_ui)
		
		if "is_selected" in current_building:
			current_building.is_selected = false
			current_building.queue_redraw()
	
	var cam = get_tree().get_first_node_in_group("Camera")
	if cam and cam.has_method("set_follow_target"):
		cam.set_follow_target(null)
	
	if bot_awaiting_home != null and is_instance_valid(bot_awaiting_home):
		if bot_awaiting_home.has_method("toggle_set_home_mode"):
			bot_awaiting_home.toggle_set_home_mode(false)
			
	bot_awaiting_home = null
	current_building = null
	hide()
	menu_closed.emit()


# ==========================================================
# TARGETING MODE LOGIC (Intercepts Clicks when waiting for Home)
# ==========================================================
func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		close_menu()
		get_viewport().set_input_as_handled()
		return # Stop reading inputs for this frame!
		
	# Are we currently waiting for the player to pick a home?
	if bot_awaiting_home != null and is_instance_valid(bot_awaiting_home):
		
		if event is InputEventMouseButton and event.pressed:
			
			# --- LEFT CLICK: SET HOME ---
			if event.button_index == MOUSE_BUTTON_LEFT:
				
				# 1. Borrow the bot's spatial awareness to get the true world mouse position
				var world_mouse_pos = bot_awaiting_home.get_global_mouse_position()
				
				# 2. Borrow the bot's level reference to calculate the grid tile
				if "level_ref" in bot_awaiting_home and bot_awaiting_home.level_ref != null:
					var grid_pos = bot_awaiting_home.level_ref.object_layer.local_to_map(world_mouse_pos)
					
					#Check if the tile is valid
					if bot_awaiting_home.has_method("is_valid_home_tile"):
						if not bot_awaiting_home.is_valid_home_tile(grid_pos):
							# Consume the click, but keep the targeting mode ON so they can try again
							get_viewport().set_input_as_handled()
							return 
					
					# 3. Apply the home!
					bot_awaiting_home.set_home(grid_pos)
					print("Home set to: ", grid_pos)
				
				# Cleanup
				if bot_awaiting_home.has_method("toggle_set_home_mode"):
					bot_awaiting_home.toggle_set_home_mode(false)
				bot_awaiting_home = null
				get_viewport().set_input_as_handled()
				
			# --- RIGHT CLICK: CANCEL ---
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if bot_awaiting_home.has_method("toggle_set_home_mode"):
					bot_awaiting_home.toggle_set_home_mode(false)
				bot_awaiting_home = null
				print("Canceled Set Home mode.")
				get_viewport().set_input_as_handled()
