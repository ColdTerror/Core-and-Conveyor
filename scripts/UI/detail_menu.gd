# ==============================================================================
# Script: UI/detail_menu.gd
# Purpose: Dictates UI interaction panels for inspected elements in the level (buildings, bots, enemies), showing health, priority rankings, recipes, inventory capacity, void/filter toggles, targeting routines, and building queues.
# Dependencies: Requires a reference to BuildingManager (via export), and Autoloads ResearchManager and EconomyManager. Also relies on child controls (title_label, info_label, action_container, close_button).
# Signals:
#   - menu_closed: Emitted when the detail menu panel is closed.
#   - research_button_clicked: Emitted when the user selects research tree triggers.
#   - quota_shortcut_clicked: Emitted when the user chooses shortcuts to the quota management page.
# ==============================================================================
extends PanelContainer

@onready var title_label = $VBoxContainer/TitleLabel
@onready var info_label = $VBoxContainer/InfoLabel 
@onready var action_container = $VBoxContainer/ActionContainer

@onready var close_button = $VBoxContainer/CloseButton

@export var building_manager: BuildingManager

var selected_object: Node2D = null

signal menu_closed
signal research_button_clicked
signal quota_shortcut_clicked



## Initializes the detail menu, hiding it by default and connecting UI actions.
func _ready():
	hide()
	close_button.pressed.connect(close_menu)
	info_label.custom_minimum_size = Vector2(225, 50) 



## Monitores the validity and details of selected targets, auto-closing if a target is destroyed.
func _process(_delta):
	if visible:
		# Safely close if the target was destroyed while we were looking at it
		if not is_instance_valid(selected_object):
			close_menu()
			return
			
		# Live update for Enemies
		if selected_object is Enemy:
			info_label.text = "Health: %d / %d\nDamage: %d" % [selected_object.health, selected_object.max_health, selected_object.damage]
			
		# Live update for Worker Bots
		elif selected_object.has_method("set_priority"): 
			var info = selected_object.get_inventory_info()
			
			# Live-update the Level & XP string
			var level_str = ""
			if "bot_level" in selected_object and "current_xp" in selected_object and "XP_THRESHOLDS" in selected_object:
				var global_max = 2
				if ResearchManager.has_method("get_bot_max_level"):
					global_max = ResearchManager.get_bot_max_level()
						
				level_str = "Level: %d / %d | " % [selected_object.bot_level, global_max]
				if selected_object.bot_level >= global_max:
					level_str += "XP: MAX\n"
				else:
					var next_threshold = selected_object.XP_THRESHOLDS[selected_object.bot_level]
					level_str += "XP: %d / %d\n" % [selected_object.current_xp, next_threshold]
			
			info_label.text = "%sHealth: %d / %d\nTarget: %s\nCarrying: %s" % [level_str, selected_object.health, selected_object.max_health, info["Target"], info["Carrying"]]



## Triggers a redraw of the building overlay footprint to match current selections.
func _force_overlay_redraw():
	if building_manager and building_manager.level_ref:
		var overlay = building_manager.level_ref.get_node_or_null("OverlayRenderer")
		if overlay:
			overlay.queue_redraw()



## Focuses the inspection window on a new building or unit target and loads its interactive UI controls.
func open_menu(target: Node2D):
	if target == null:
		close_menu()
		return
	
	var is_new_target = (selected_object != target)
	var was_closed = not visible
		
	# Unselect old target
	if is_instance_valid(selected_object) and selected_object != target:
		if "is_selected" in selected_object:
			selected_object.is_selected = false
			selected_object.queue_redraw()
	
	selected_object = target
	
	# Handle Enemy vs Building names
	if selected_object is Enemy:
		title_label.text = selected_object.enemy_name
	elif "building_name" in selected_object:
		title_label.text = selected_object.building_name
	else:
		title_label.text = "Unknown Entity"
	
	# Select new target
	if "is_selected" in selected_object:
		selected_object.is_selected = true
		selected_object.queue_redraw()
		
	# Force the OverlayRenderer to draw the new footprint!
	_force_overlay_redraw()
		
	if selected_object.has_signal("inventory_changed"):
		if not selected_object.inventory_changed.is_connected(refresh_ui):
			selected_object.inventory_changed.connect(refresh_ui)
	
	if selected_object is ConveyorBuilding:
		if not selected_object.item_changed.is_connected(refresh_ui):
			selected_object.item_changed.connect(refresh_ui)
		
	refresh_ui()
	show()
	
	# only play the flash when switching targets or opening menu
	if is_new_target or was_closed:
		_play_refresh_flash()



## Closes the details menu, deselects the current target, and clears overlay footprints.
func close_menu():
	if is_instance_valid(selected_object):
		if selected_object.has_signal("inventory_changed"):
			if selected_object.inventory_changed.is_connected(refresh_ui):
				selected_object.inventory_changed.disconnect(refresh_ui)
		
		# Unselect and hide footprint on close
		if "is_selected" in selected_object:
			selected_object.is_selected = false
			selected_object.queue_redraw()
			
		# Force the OverlayRenderer to clear the footprint!
		_force_overlay_redraw()
	
	var cam = get_tree().get_first_node_in_group("Camera")
	if cam and cam.has_method("set_follow_target"):
		cam.set_follow_target(null)
	
	if is_instance_valid(selected_object) and selected_object is ConveyorBuilding:
		if selected_object.item_changed.is_connected(refresh_ui):
			selected_object.item_changed.disconnect(refresh_ui)
			
	selected_object = null
	hide()
	menu_closed.emit()



## Rebuilds the action buttons and details display panel matching the currently inspected object.
func refresh_ui():
	if not is_instance_valid(selected_object): return
	
	for child in action_container.get_children():
		child.queue_free()

	info_label.modulate = Color.WHITE
	info_label.visible = true

	# Change focus text based on selection
	var focus_text = "Center Camera"
	if selected_object.has_method("set_priority"):
		focus_text = "Follow Bot"
	elif selected_object is Enemy:
		focus_text = "Follow Enemy"
		
	_create_button(focus_text, Color(0.9, 0.9, 0.9), func():
		var cam = get_tree().get_first_node_in_group("Camera")
		if cam and cam.has_method("set_follow_target"):
			cam.set_follow_target(selected_object)
	)
	
	var can_relocate = not (
		selected_object is CoreBuilding or 
		selected_object is GateBuilding or 
		selected_object is TerraformSite or 
		selected_object is ConstructionSite or 
		selected_object is WallBuilding or 
		selected_object is ConveyorBuilding or
		selected_object is Enemy or 
		selected_object.has_method("set_priority")
	)
	if can_relocate:
		_create_button("Relocate (Can't Be Undone)", Color(0.8, 0.4, 1.0), func():
			if building_manager.has_method("start_relocating"):
				building_manager.start_relocating(selected_object)
				close_menu()
		)
	
	if selected_object is ProcessorBuilding:
		_setup_processor_ui(selected_object as ProcessorBuilding)
	elif selected_object is StockpileBuilding:
		_setup_stockpile_ui(selected_object as StockpileBuilding)
	elif selected_object is TowerBuilding:
		_setup_tower_ui(selected_object as TowerBuilding)
	elif selected_object is CoreBuilding:
		_setup_core_ui(selected_object as CoreBuilding)
	elif selected_object is QuotaBuilding:
		_setup_quota_ui(selected_object as QuotaBuilding)
	elif selected_object.has_method("set_priority"):
		_setup_bot_ui(selected_object)
	elif selected_object is Enemy:
		_setup_enemy_ui(selected_object)
	elif selected_object is ConveyorBridge:
		_setup_conveyor_bridge_ui(selected_object as ConveyorBridge)
	elif selected_object is ConveyorBuilding:
		_setup_conveyor_ui(selected_object as ConveyorBuilding)
	elif selected_object is FilterBuilding:
		_setup_filter_ui(selected_object as FilterBuilding)
	else:
		info_label.text = "No configurable options."
		
	if not selected_object.has_method("set_priority"):
		_build_priority_widget(selected_object)



## Instantiates and formats an interactive action button within the options layout container.
func _create_button(btn_text: String, btn_color: Color, action_callable: Callable):
	var btn = Button.new()
	btn.text = btn_text
	btn.modulate = btn_color
	btn.pressed.connect(func():
		action_callable.call()
		refresh_ui() 
	)
	action_container.add_child(btn)


## Configures and formats recipes, requirements, and outputs details for processor buildings.
func _setup_processor_ui(b: ProcessorBuilding):
	if b.recipes.size() > 0:
		var recipe = b.active_recipe
		var details = "Recipe: %s\n" % recipe.recipe_name
		if recipe.inputs.size() > 0:
			details += "[Requires]"
			for item_res in recipe.inputs.keys():
				var amount = recipe.inputs[item_res]
				var item_name = item_res.display_name if item_res != null else "Unknown Item" 
				details += "\n • %d %s" % [amount, item_name]
		if recipe.output_item != null:
			details += "\n[Produces]"
			details += "\n • %d %s" % [recipe.output_count, recipe.output_item.display_name]
		
		info_label.text = details.strip_edges()
		
		if b.recipes.size() > 1:
			_create_button("Switch Recipe", Color.WHITE, b.cycle_recipe)
	else:
		info_label.text = "No Recipes Configured"


## Prepares storage status labels, dedicated/mixed modes toggles, and void-all buttons.
func _setup_stockpile_ui(b: StockpileBuilding):
	if b.selected_output_name == "":
		info_label.text = "Output: OFF"
		info_label.modulate = Color(1, 0.5, 0.5) 
	else:
		info_label.text = "Output: %s" % b.selected_output_name
		info_label.modulate = Color(0.5, 1, 0.5) 

	if b.has_method("toggle_inventory_mode"):
		var mode_text = ""
		if b.is_dedicated_mode:
			mode_text = "Mode: Dedicated (%d)" % b.max_dedicated_capacity
		else:
			mode_text = "Mode: Mixed (%d)" % b.max_mixed_capacity
			
		var mode_color = Color(0.3, 0.8, 1.0) if b.is_dedicated_mode else Color(1.0, 0.8, 0.3)
		_create_button(mode_text, mode_color, b.toggle_inventory_mode)
		
	if b.has_method("cycle_output_mode") and b.has_method("get_economy_assets"):
		var unique_item_types_count = b.get_economy_assets().keys().size()
		if unique_item_types_count > 0: 
			_create_button("Cycle Output", Color.WHITE, b.cycle_output_mode)
			
	if b.has_method("void_inventory"):
		_create_button("Void All Items", Color(1.0, 0.3, 0.3), b.void_inventory)


## Standardizes defense tower prioritization controls and targeting targets.
func _setup_tower_ui(b: TowerBuilding):
	info_label.text = "Priority: %s" % b.targeting_mode
	match b.targeting_mode:
		"Closest": info_label.modulate = Color(0.8, 0.8, 1.0)
		"Strongest": info_label.modulate = Color(1.0, 0.4, 0.4)
		"Weakest": info_label.modulate = Color(0.4, 1.0, 0.4)
		"Furthest": info_label.modulate = Color(0.8, 0.4, 1.0)

	_create_button("Cycle Targeting", Color.WHITE, b.cycle_targeting_mode)


## Displays ongoing tech research progress and handles robot assembly and cost information.
func _setup_core_ui(b: CoreBuilding):
	info_label.modulate = Color(0.8, 0.8, 1.0)
	info_label.text = ""
	
	# Research UI
	if b.active_research_name != "":
		info_label.text += "Researching: %s\n" % b.active_research_name
		
		for item_res in b.research_bill_max.keys():
			var max_required = b.research_bill_max[item_res]
			var still_needed = b.research_bill.get(item_res, 0)
			var currently_deposited = max_required - still_needed
			info_label.text += "%s: %d / %d\n" % [item_res.display_name, currently_deposited, max_required]
			
		_create_button("Cancel Research", Color(1.0, 0.4, 0.4), func():
			b.active_research_name = ""
			b.research_bill.clear()
			b.research_bill_max.clear()
			refresh_ui()
		)
	else:
		info_label.text += "No Current Research\n"
		_create_button("Open Research Tree", Color(1.0, 0.84, 0.0), func(): 
			research_button_clicked.emit()
		)

	# Visual separator in the text
	info_label.text += "\n----------------------\n\n"

	# Bot construction UI
	var current_bots = get_tree().get_nodes_in_group("Bots").size()
	var max_bots = ResearchManager.max_bots_allowed
	
	info_label.text += "Worker Bots: %d / %d\n" % [current_bots, max_bots]

	if b.is_building_bot:
		info_label.text += "Constructing Bot...\n"
		
		for item_res in b.bot_bill_max.keys():
			var max_required = b.bot_bill_max[item_res]
			var still_needed = b.bot_bill.get(item_res, 0)
			var currently_deposited = max_required - still_needed
			info_label.text += "%s: %d / %d\n" % [item_res.display_name, currently_deposited, max_required]
			
		_create_button("Cancel Bot", Color(1.0, 0.4, 0.4), func():
			b.is_building_bot = false
			b.bot_bill.clear()
			b.bot_bill_max.clear()
			refresh_ui()
		)
	else:
		if current_bots >= max_bots:
			info_label.text += "Maximum bots reached.\n"
		else:
			# Show the player the cost before buying
			var cost_text = "Cost: "
			var cost_dict = b.get_bot_cost()
			for item_res in cost_dict.keys():
				cost_text += "%d %s, " % [cost_dict[item_res], item_res.display_name]
			
			info_label.text += cost_text.trim_suffix(", ") + "\n"

			# Build worker bot button configuration
			_create_button("Build Worker Bot", Color(0.4, 1.0, 0.4), func():
				b.start_bot_construction()
				refresh_ui()
			)


## Renders current requirements, daily compliance status, and weekly safety goals.
func _setup_quota_ui(b: QuotaBuilding):
	var info = b.get_inventory_info()
	
	if info.is_empty():
		info_label.text = "Awaiting connection to Quota Manager..."
		info_label.modulate = Color(0.5, 0.5, 0.5)
		return
		
	# Grace period UI
	if info.get("Status", "") == "GRACE PERIOD":
		var txt = "Status: GRACE PERIOD\n"
		txt += "Weekly Success: 7 / 7 Days\n"
		txt += "--- Daily Requirements ---\n"
		txt += " • None! Free build time."
		
		info_label.text = txt
		info_label.modulate = Color(0.4, 1.0, 0.4)
		
		_create_button("View Global Quota", Color(0.3, 0.8, 1.0), func():
			quota_shortcut_clicked.emit()
			close_menu() 
		)
		return
		
	# Color code the entire text block based on safety!
	if info.get("Status", "") == "SAFE TODAY":
		info_label.modulate = Color(0.2, 1.0, 0.2)
	else:
		info_label.modulate = Color(1.0, 0.8, 0.2)
		
	# Build the display string
	var details = ""
	details += "Status: %s\n" % info.get("Status", "Unknown")
	details += "Weekly Success: %s\n" % info.get("Weekly Success", "0 / 7 Days")
	details += "--- Daily Requirements ---\n"
	
	# Loop through the dictionary to find the raw material numbers
	for key in info.keys():
		# Skip the header info we already printed
		if key == "Status" or key == "Weekly Success":
			continue
			
		# This prints: "Wood: 45 / 100"
		details += " • %s: %s\n" % [key, info[key]]
		
	info_label.text = details.strip_edges()
	
	_create_button("View Global Quota", Color(0.3, 0.8, 1.0), func():
		quota_shortcut_clicked.emit()
		close_menu()
	)


## Handles level meters, inventory indicators, pathing targets, and directive priority hotkeys.
func _setup_bot_ui(b: Node2D):
	var info = b.get_inventory_info()
	
	# Build the Level & XP string
	var level_str = ""
	if "bot_level" in b and "current_xp" in b and "XP_THRESHOLDS" in b:
		var global_max = 2
		if ResearchManager.has_method("get_bot_max_level"):
			global_max = ResearchManager.get_bot_max_level()
				
		level_str = "Level: %d / %d | " % [b.bot_level, global_max]
		if b.bot_level >= global_max:
			level_str += "XP: MAX\n"
		else:
			var next_threshold = b.XP_THRESHOLDS[b.bot_level]
			level_str += "XP: %d / %d\n" % [b.current_xp, next_threshold]

	# Inject the level_str at the very beginning of the label
	info_label.text = "%sHealth: %d / %d\nTarget: %s\nCarrying: %s" % [level_str, b.health, b.max_health, info["Target"], info["Carrying"]]
	
	# Match colors to bot screen
	if info["Target"] == "Wood Only": 
		info_label.modulate = Color(0.2, 0.8, 0.2)
	elif info["Target"] == "Stone Only": 
		info_label.modulate = Color(0.2, 0.6, 1.0)
	elif info["Target"] == "Maintain": 
		info_label.modulate = Color(1.0, 0.8, 0.2)
	elif info["Target"] == "Home": 
		info_label.modulate = Color(1.0, 1.0, 1.0)
	else: 
		info_label.modulate = Color(1.0, 1.0, 1.0)

	# Buttons matching the screens
	_create_button("Wood Only", Color(0.2, 0.8, 0.2), func(): b.set_priority(0))
	_create_button("Stone Only", Color(0.2, 0.6, 1.0), func(): b.set_priority(1))
	_create_button("Maintain", Color(1.0, 0.8, 0.2), func(): b.set_priority(2))
	_create_button("Go Home", Color(0.8, 0.8, 0.8), func(): b.set_priority(3)) 
	
	# Tell InputManager to take over
	_create_button("Set Home", Color(0.0, 0.8, 0.8), func(): 
		var input = get_tree().get_first_node_in_group("InputManager")
		if input:
			input.bot_awaiting_home = b
			input.current_mode = input.InteractionMode.SET_HOME
			
		if b.has_method("toggle_set_home_mode"):
			b.toggle_set_home_mode(true)
	)


## Displays general attributes and status indicators for targeted enemies.
func _setup_enemy_ui(e: Enemy):
	# We leave info_label blank here because _process() is updating it!
	info_label.modulate = Color(1.0, 0.4, 0.4)


## Shows visual cargo info and lets players dump items off conveyor tracks.
func _setup_conveyor_ui(b: ConveyorBuilding):
	var item_name = "Empty"
	if b.held_item and "item_data" in b.held_item and b.held_item.item_data:
		item_name = b.held_item.item_data.display_name
		info_label.modulate = Color(0.4, 1.0, 0.4)
	else:
		info_label.modulate = Color(0.5, 0.5, 0.5)
		
	info_label.text = "Held Item: %s" % item_name
	
	# Add the Void Button (Only if holding an item)
	if b.held_item and is_instance_valid(b.held_item):
		_create_button("Void Item", Color(1.0, 0.3, 0.3), func():
			if b.held_item and is_instance_valid(b.held_item):
				# Log the destruction to the economy!
				if "item_data" in b.held_item and b.held_item.item_data:
					EconomyManager.log_item_consumed(b.held_item.item_data.display_name, 1)
				
				# Destroy the visual item
				b.held_item.queue_free()
				b.held_item = null
				
				# Refresh the menu so the button vanishes
		)



## Shows visual cargo info and lets players dump items off conveyor bridge tracks.
func _setup_conveyor_bridge_ui(b: ConveyorBridge):
	var h_item_name = "Empty"
	if b.horizontal_held_item and is_instance_valid(b.horizontal_held_item) and b.horizontal_held_item.item_data:
		h_item_name = b.horizontal_held_item.item_data.display_name
		
	var v_item_name = "Empty"
	if b.vertical_held_item and is_instance_valid(b.vertical_held_item) and b.vertical_held_item.item_data:
		v_item_name = b.vertical_held_item.item_data.display_name
		
	info_label.text = "Horizontal Channel: %s\nVertical Channel: %s" % [h_item_name, v_item_name]
	
	if h_item_name != "Empty" or v_item_name != "Empty":
		info_label.modulate = Color(0.4, 1.0, 0.4)
	else:
		info_label.modulate = Color(0.5, 0.5, 0.5)
		
	if b.horizontal_held_item and is_instance_valid(b.horizontal_held_item):
		_create_button("Void Horizontal", Color(1.0, 0.3, 0.3), func():
			if b.horizontal_held_item and is_instance_valid(b.horizontal_held_item):
				if "item_data" in b.horizontal_held_item and b.horizontal_held_item.item_data:
					EconomyManager.log_item_consumed(b.horizontal_held_item.item_data.display_name, 1)
				b.horizontal_held_item.queue_free()
				b.horizontal_held_item = null
				refresh_ui()
		)
		
	if b.vertical_held_item and is_instance_valid(b.vertical_held_item):
		_create_button("Void Vertical", Color(1.0, 0.3, 0.3), func():
			if b.vertical_held_item and is_instance_valid(b.vertical_held_item):
				if "item_data" in b.vertical_held_item and b.vertical_held_item.item_data:
					EconomyManager.log_item_consumed(b.vertical_held_item.item_data.display_name, 1)
				b.vertical_held_item.queue_free()
				b.vertical_held_item = null
				refresh_ui()
		)



## Displays active route filters and toggle commands for sorting belts.
func _setup_filter_ui(b: FilterBuilding):
	var current_filter = b.filter_options[b.current_filter_index]
	var mode_text = "Output: Sides" if b.is_split_mode else "Output: Forward"
	
	info_label.text = "Filtering: %s\nMode: %s" % [current_filter, mode_text]
	info_label.modulate = Color(0.4, 1.0, 0.4) if current_filter != "None" else Color.WHITE
	
	_create_button("Cycle Item", Color.WHITE, b.cycle_filter)
	_create_button("Change Mode", Color(0.3, 0.8, 1.0), b.toggle_filter_mode)


## Generates rank buttons for re-ordering building task workflows.
func _build_priority_widget(b: Node):
	if building_manager == null: return
	var bm = building_manager
	
	var priority_item = b
	if b is ConveyorBuilding:
		priority_item = "Belts"
	elif b is WallBuilding: 
		priority_item = "Walls"
		
	var current_rank = bm.get_priority_rank(priority_item)
	var max_rank = bm.get_total_priority_ranks()
	if current_rank == 0: return

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var up_btn = Button.new()
	up_btn.text = " ▲ "
	up_btn.disabled = (current_rank == 1) 
	up_btn.pressed.connect(func():
		bm.move_priority_up(priority_item)
		refresh_ui() 
	)
	
	var rank_label = Label.new()
	rank_label.text = "  Priority: %d / %d  " % [current_rank, max_rank]
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	var down_btn = Button.new()
	down_btn.text = " ▼ "
	down_btn.disabled = (current_rank == max_rank) 
	down_btn.pressed.connect(func():
		bm.move_priority_down(priority_item)
		refresh_ui()
	)
	
	hbox.add_child(up_btn)
	hbox.add_child(rank_label)
	hbox.add_child(down_btn)
	action_container.add_child(hbox)


## Initiates an entry transition tween effect for menu panels.
func _play_refresh_flash():
	# Kill any ongoing flashes so they don't overlap if the player clicks super fast
	var tween = create_tween()
	
	# Start the menu at 50% opacity and slightly brighter
	modulate = Color(1.2, 1.2, 1.2, 0.5) 
	
	# Tween it back to pure white and 100% solid over 0.25 seconds
	tween.tween_property(self, "modulate", Color.WHITE, 0.25).set_trans(Tween.TRANS_SINE)
