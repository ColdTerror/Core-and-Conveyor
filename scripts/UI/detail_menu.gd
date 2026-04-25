extends PanelContainer

@onready var title_label = $VBoxContainer/TitleLabel
@onready var info_label = $VBoxContainer/InfoLabel 
@onready var action_container = $VBoxContainer/ActionContainer

@onready var close_button = $VBoxContainer/CloseButton

@export var building_manager: BuildingManager

var selected_object: Node2D = null

signal menu_closed
signal research_button_clicked

func _ready():
	hide()
	close_button.pressed.connect(close_menu)
	info_label.custom_minimum_size = Vector2(225, 50) 
	

func _process(_delta):
	if visible:
		# 1. Safely close if the target was destroyed while we were looking at it
		if not is_instance_valid(selected_object):
			close_menu()
			return
			
		# 2. Live update for Enemies
		if selected_object is Enemy:
			info_label.text = "Health: %d / %d\nDamage: %d" % [selected_object.health, selected_object.max_health, selected_object.damage]
			
		# 3. Live update for Worker Bots
		elif selected_object.has_method("set_priority"): 
			var info = selected_object.get_inventory_info()
			info_label.text = "Health: %d / %d\nTarget: %s\nCarrying: %s" % [selected_object.health, selected_object.max_health, info["Target"], info["Carrying"]]

func open_menu(target: Node2D):
	if target == null:
		close_menu()
		return
	
	var is_new_target = (selected_object != target)
	var was_closed = not visible
		
	
	if is_instance_valid(selected_object) and selected_object != target:
		if "is_selected" in selected_object:
			selected_object.is_selected = false
			selected_object.queue_redraw()
	
	selected_object = target
	
	# --- UPDATE: Handle Enemy vs Building names ---
	if selected_object is Enemy:
		title_label.text = selected_object.enemy_name
	elif "building_name" in selected_object:
		title_label.text = selected_object.building_name
	else:
		title_label.text = "Unknown Entity"
	# ----------------------------------------------
	
	if "is_selected" in selected_object:
		selected_object.is_selected = true
		selected_object.queue_redraw()
		
	if selected_object.has_signal("inventory_changed"):
		if not selected_object.inventory_changed.is_connected(refresh_ui):
			selected_object.inventory_changed.connect(refresh_ui)

	refresh_ui()
	show()
	
	#only play the flash when switching targets or opening menu
	if is_new_target or was_closed:
		_play_refresh_flash()

func close_menu():
	
	if is_instance_valid(selected_object):
		if selected_object.has_signal("inventory_changed"):
			if selected_object.inventory_changed.is_connected(refresh_ui):
				selected_object.inventory_changed.disconnect(refresh_ui)
		
		if "is_selected" in selected_object:
			selected_object.is_selected = false
			selected_object.queue_redraw()
	
	var cam = get_tree().get_first_node_in_group("Camera")
	if cam and cam.has_method("set_follow_target"):
		cam.set_follow_target(null)
	
	selected_object = null
	hide()
	menu_closed.emit()


func refresh_ui():
	if not is_instance_valid(selected_object): return
	
	for child in action_container.get_children():
		child.queue_free()

	info_label.modulate = Color.WHITE
	info_label.visible = true

	# --- Change the focus text based on what we clicked! ---
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
		_create_button("Relocate (Lose Inventory)", Color(0.8, 0.4, 1.0), func():
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
	elif selected_object.has_method("set_priority"):
		_setup_bot_ui(selected_object)
	elif selected_object is Enemy:
		_setup_enemy_ui(selected_object)
	elif selected_object is FilterBuilding:
		_setup_filter_ui(selected_object as FilterBuilding)
	else:
		info_label.text = "No configurable options."
		
	if not selected_object.has_method("set_priority"):
		_build_priority_widget(selected_object)

func _create_button(btn_text: String, btn_color: Color, action_callable: Callable):
	var btn = Button.new()
	btn.text = btn_text
	btn.modulate = btn_color
	btn.pressed.connect(func():
		action_callable.call()
		refresh_ui() 
	)
	action_container.add_child(btn)

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

func _setup_stockpile_ui(b: StockpileBuilding):
	if b.selected_output_name == "":
		info_label.text = "Output: OFF"
		info_label.modulate = Color(1, 0.5, 0.5) 
	else:
		info_label.text = "Output: %s" % b.selected_output_name
		info_label.modulate = Color(0.5, 1, 0.5) 

	if b.has_method("toggle_inventory_mode"):
		var mode_text = "Mode: Dedicated (100)" if b.is_dedicated_mode else "Mode: Mixed (25)"
		var mode_color = Color(0.3, 0.8, 1.0) if b.is_dedicated_mode else Color(1.0, 0.8, 0.3)
		_create_button(mode_text, mode_color, b.toggle_inventory_mode)
		
	if b.has_method("cycle_output_mode") and b.has_method("get_economy_assets"):
		var unique_item_types_count = b.get_economy_assets().keys().size()
		if unique_item_types_count > 0: 
			_create_button("Cycle Output", Color.WHITE, b.cycle_output_mode)
			
	if b.has_method("void_inventory"):
		_create_button("Void All Items", Color(1.0, 0.3, 0.3), b.void_inventory)

func _setup_tower_ui(b: TowerBuilding):
	info_label.text = "Priority: %s" % b.targeting_mode
	match b.targeting_mode:
		"Closest": info_label.modulate = Color(0.8, 0.8, 1.0)
		"Strongest": info_label.modulate = Color(1.0, 0.4, 0.4)
		"Weakest": info_label.modulate = Color(0.4, 1.0, 0.4)
		"Furthest": info_label.modulate = Color(0.8, 0.4, 1.0)

	_create_button("Cycle Targeting", Color.WHITE, b.cycle_targeting_mode)

func _setup_core_ui(b: CoreBuilding):
	info_label.modulate = Color(0.8, 0.8, 1.0)
	if b.active_research_name != "":
		info_label.text = ""
		info_label.text += "\n\nResearching: %s" % b.active_research_name
		
		for item_name in b.research_bill_max.keys():
			var max_required = b.research_bill_max[item_name]
			var still_needed = b.research_bill.get(item_name, 0)
			var currently_deposited = max_required - still_needed
			info_label.text += "\n%s: %d / %d" % [item_name.display_name, currently_deposited, max_required]
			
		_create_button("Cancel Research", Color(1.0, 0.4, 0.4), func():
			b.active_research_name = ""
			b.research_bill.clear()
			b.research_bill_max.clear()
			refresh_ui()
		)
	else:
		info_label.text = "No Current Research"
		_create_button("Open Research Tree", Color(1.0, 0.84, 0.0), func(): 
			research_button_clicked.emit()
		)

func _setup_bot_ui(b: Node2D):
	var info = b.get_inventory_info()
	info_label.text = "Health: %d / %d\nTarget: %s\nCarrying: %s" % [b.health, b.max_health, info["Target"], info["Carrying"]]
	
	if info["Target"] == "Wood Only": info_label.modulate = Color(0.6, 1.0, 0.6)
	elif info["Target"] == "Stone Only": info_label.modulate = Color(0.785, 0.785, 0.785, 1.0)
	elif info["Target"] == "Maintain": info_label.modulate = Color(0.2, 0.6, 1.0)
	elif info["Target"] == "Home": info_label.modulate = Color(1.0, 0.4, 0.4)
	else: info_label.modulate = Color(1.0, 1.0, 1.0)

	_create_button("Wood Only", Color(0.6, 1.0, 0.6), func(): b.set_priority(0))
	_create_button("Stone Only", Color(0.785, 0.785, 0.785, 1.0), func(): b.set_priority(1))
	_create_button("Maintain", Color(0.2, 0.6, 1.0), func(): b.set_priority(2))
	_create_button("Go Home", Color(1.0, 0.4, 0.4), func(): b.set_priority(3))
	
	# --- UPDATE: Tell InputController to take over! ---
	_create_button("Set Home", Color(1.0, 0.8, 0.2), func(): 
		var input = get_tree().get_first_node_in_group("InputManager")
		if input:
			input.bot_awaiting_home = b
			input.current_mode = input.InteractionMode.SET_HOME
			
		if b.has_method("toggle_set_home_mode"):
			b.toggle_set_home_mode(true)
	)

# --- Enemy UI Helper ---
func _setup_enemy_ui(e: Enemy):
	# We leave info_label blank here because _process() is updating it!
	info_label.modulate = Color(1.0, 0.4, 0.4) # Red text!
	
	# Optional: You could add a button here to "Mark Priority Target" for towers later!

func _setup_filter_ui(b: FilterBuilding):
	var current_filter = b.filter_options[b.current_filter_index]
	var mode_text = "Output: Sides" if b.is_split_mode else "Output: Forward"
	
	info_label.text = "Filtering: %s\nMode: %s" % [current_filter, mode_text]
	info_label.modulate = Color(0.4, 1.0, 0.4) if current_filter != "None" else Color.WHITE
	
	_create_button("Cycle Item", Color.WHITE, b.cycle_filter)
	_create_button("Change Mode", Color(0.3, 0.8, 1.0), b.toggle_filter_mode)

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
	
func _play_refresh_flash():
	# Kill any ongoing flashes so they don't overlap if the player clicks super fast
	var tween = create_tween()
	
	# Start the menu at 50% opacity and slightly brighter
	modulate = Color(1.2, 1.2, 1.2, 0.5) 
	
	# Tween it back to pure white and 100% solid over 0.25 seconds
	tween.tween_property(self, "modulate", Color.WHITE, 0.25).set_trans(Tween.TRANS_SINE)
