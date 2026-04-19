extends Control
# ==========================================
# MANAGEMENT MENU (Priorities & Workers)
# ==========================================

@export var building_manager: BuildingManager

# --- UI REFERENCES ---
@onready var tab_container = $PanelContainer/TabContainer

# Priorities Tab
@onready var priority_list_container = $PanelContainer/TabContainer/Priorities/VBoxContainer/ScrollContainer/ListContainer

# Workers Tab
@onready var bot_list_container = $PanelContainer/TabContainer/Workers/VBoxContainer/ScrollContainer/ListContainer

# Resources Tab
@onready var resource_list_container = $PanelContainer/TabContainer/Resources/VBoxContainer/ScrollContainer/ListContainer

# Floating Close Button
@onready var close_button = $PanelContainer/Close

# --- LIVE UPDATE TRACKING ---
var update_timer: float = 0.0
var update_interval: float = 0.5 
var bot_status_labels: Dictionary = {}

func _ready():
	hide()
		
	if close_button:
		close_button.pressed.connect(close_menu)
		
	if tab_container:
		tab_container.focus_mode = Control.FOCUS_NONE
		
		var tab_bar = tab_container.get_tab_bar()
		tab_bar.focus_mode = Control.FOCUS_NONE
		tab_bar.tab_clicked.connect(_on_tab_clicked)

func _process(delta):
	# Only refresh the live data if the menu is actually open
	if not visible:
		return
		
	update_timer -= delta
	
	if update_timer <= 0.0:
		update_timer = update_interval 
		
		# ONLY run the soft update if they are looking at the Workers tab!
		if tab_container and tab_container.current_tab == 1:
			_refresh_bot_tab(false) # Soft update = false

func _on_tab_clicked(tab_index):
	var target_tab = tab_index
	
	if target_tab == 0:
		_refresh_priority_tab()
	elif target_tab == 1:
		_refresh_bot_tab(true) # Force rebuild = true
	elif target_tab == 2:
		_refresh_resource_tab()
		
	# Force the tab to stay on the index the user clicked
	tab_container.call_deferred("set_current_tab", target_tab)

func toggle_menu():
	if visible:
		close_menu()
	else:
		if not GameState.is_menu_open:
			open_menu()

func open_menu():
	GameState.is_menu_open = true
	_refresh_priority_tab()
	_refresh_bot_tab(true) # Force rebuild when opening
	_refresh_resource_tab()
	show()

func close_menu():
	GameState.is_menu_open = false
	hide()

# ==========================================
# PRIORITIES TAB LOGIC
# ==========================================

func _refresh_priority_tab():
	if not priority_list_container: return
	
	# 1. Clean up old rows
	for child in priority_list_container.get_children():
		child.queue_free()
		
	if not building_manager: 
		print("PriorityMenu: Building Manager not assigned!")
		return
		
	# 2. Grab the queue
	var queue = building_manager.master_priority_queue
	var max_rank = queue.size()
	
	# 3. Build a row for every item
	for i in range(max_rank):
		var item = queue[i]
		var rank = i + 1
		_create_priority_row(item, rank, max_rank)

func _create_priority_row(item: Variant, rank: int, max_rank: int):
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# --- UP ARROW ---
	var up_btn = Button.new()
	up_btn.text = " ▲ "
	up_btn.disabled = (rank == 1)
	up_btn.pressed.connect(func():
		building_manager.move_priority_up(item)
		_refresh_priority_tab()
	)
	
	# --- DEDICATED RANK LABEL ---
	var rank_label = Label.new()
	rank_label.text = str(rank) + "."
	rank_label.custom_minimum_size = Vector2(30, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# --- NAME BUTTON ---
	var name_btn = Button.new()
	name_btn.custom_minimum_size = Vector2(200, 0)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_btn.flat = true 
	
	if typeof(item) == TYPE_STRING:
		name_btn.text = "[Group] %s" % item
		name_btn.modulate = Color(0.8, 0.8, 1.0) 
		name_btn.focus_mode = Control.FOCUS_NONE
		name_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		if is_instance_valid(item) and "building_name" in item:
			name_btn.text = item.building_name
			name_btn.pressed.connect(func():
				var cam = get_tree().get_first_node_in_group("Camera")
				if cam and cam.has_method("set_follow_target"):
					cam.set_follow_target(item)
			)
		else:
			name_btn.text = "[Invalid]"
			name_btn.disabled = true
			
	# --- DOWN ARROW ---
	var down_btn = Button.new()
	down_btn.text = " ▼ "
	down_btn.disabled = (rank == max_rank)
	down_btn.pressed.connect(func():
		building_manager.move_priority_down(item)
		_refresh_priority_tab()
	)
	
	# Assemble the row
	hbox.add_child(up_btn)
	hbox.add_child(rank_label)
	hbox.add_child(name_btn)  
	hbox.add_child(down_btn)
	
	priority_list_container.add_child(hbox)

# ==========================================
# WORKERS TAB LOGIC
# ==========================================

func _refresh_bot_tab(force_rebuild: bool = false):
	if not bot_list_container: return
	
	var bots = get_tree().get_nodes_in_group("Bots")
	
	# 1. Hard Rebuild if forced (tab clicked/menu opened) OR if a bot was born/died
	if force_rebuild or bots.size() != bot_status_labels.size():
		_rebuild_bot_list(bots)
	else:
		# 2. Soft Update! Change the text without deleting the buttons
		for bot in bots:
			if bot_status_labels.has(bot) and is_instance_valid(bot_status_labels[bot]):
				if bot.has_method("get_inventory_info"):
					var info = bot.get_inventory_info()
					var new_text = "Task: %s | Carrying: %s" % [info.get("Target", "Idle"), info.get("Carrying", "Nothing")]
					bot_status_labels[bot].text = new_text

func _rebuild_bot_list(bots: Array):
	# Clean up old UI rows and reset tracking
	bot_status_labels.clear()
	for child in bot_list_container.get_children():
		child.queue_free()
		
	if bots.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No active worker bots."
		bot_list_container.add_child(empty_label)
		return

	var bot_index = 1
	for bot in bots:
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# --- NAME ---
		var name_label = Label.new()
		name_label.text = "Bot #" + str(bot_index)
		name_label.custom_minimum_size = Vector2(80, 0)
		
		# --- STATUS ---
		var status_label = Label.new()
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bot.has_method("get_inventory_info"):
			var info = bot.get_inventory_info()
			status_label.text = "Task: %s | Carrying: %s" % [info.get("Target", "Idle"), info.get("Carrying", "Nothing")]
		else:
			status_label.text = "Task: Unknown"
			
		# SAVE LABEL IN DICTIONARY
		bot_status_labels[bot] = status_label
		
		# --- FOLLOW BUTTON ---
		var follow_btn = Button.new()
		follow_btn.text = " Follow "
		follow_btn.modulate = Color(0.3, 0.8, 1.0) 
		
		follow_btn.pressed.connect(func():
			var cam = get_tree().get_first_node_in_group("Camera")
			if cam and cam.has_method("set_follow_target"):
				cam.set_follow_target(bot)
			close_menu()
		)
		
		row.add_child(name_label)
		row.add_child(status_label)
		row.add_child(follow_btn)
		
		bot_list_container.add_child(row)
		bot_list_container.add_child(HSeparator.new())
		
		bot_index += 1

# ==========================================
# RESOURCES TAB LOGIC
# ==========================================

func _refresh_resource_tab():
	print('refresh resource')
	if not resource_list_container: return
	
	# 1. Clean up old rows
	for child in resource_list_container.get_children():
		child.queue_free()
		
	# 2. Add a Header Row
	var header = Label.new()
	header.text = "Top Bar Pinned Resources (Max 10)"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.modulate = Color(0.8, 0.8, 0.8)
	resource_list_container.add_child(header)
	resource_list_container.add_child(HSeparator.new())
	
	# 3. Get all discovered items from the EconomyManager
	var all_items = EconomyManager.global_inventory.keys()
	
	# Optional: You can sort them alphabetically so the list is always clean!
	all_items.sort()
	
	if all_items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No resources discovered yet."
		resource_list_container.add_child(empty_label)
		return

	# 4. Build a row for every item
	for item_name in all_items:
		var amount = EconomyManager.global_inventory[item_name]
		var is_pinned = EconomyManager.pinned_resources.has(item_name)
		_create_resource_row(item_name, amount, is_pinned)

func _create_resource_row(item_name: String, amount: int, is_pinned: bool):
	# The wrapper holds the main row AND the hidden dropdown list
	var wrapper = VBoxContainer.new()
	
	var main_row = HBoxContainer.new()
	main_row.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# --- PIN BUTTON ---
	var pin_btn = Button.new()
	pin_btn.text = " [\u2605] " if is_pinned else " [  ] " 
	pin_btn.modulate = Color(1.0, 0.8, 0.2) if is_pinned else Color(0.5, 0.5, 0.5)
	pin_btn.pressed.connect(func(): _toggle_pin(item_name))
	
	# --- NAME BUTTON (Replacing the Label) ---
	var name_btn = Button.new()
	name_btn.text = item_name + " \u25BC" # Adds a little down arrow!
	name_btn.custom_minimum_size = Vector2(150, 0)
	name_btn.flat = true # Makes it look like normal text until you hover over it
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# --- AMOUNT LABEL ---
	var amount_label = Label.new()
	amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_label.text = "Total: %d" % amount
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	# Assemble the main row
	main_row.add_child(pin_btn)
	main_row.add_child(name_btn)
	main_row.add_child(amount_label)
	
	# --- THE HIDDEN DROPDOWN ---
	var details_vbox = VBoxContainer.new()
	details_vbox.hide()
	
	# Wire up the dropdown toggle!
	name_btn.pressed.connect(func():
		_toggle_resource_details(item_name, details_vbox, name_btn)
	)
	
	# Put it all together
	wrapper.add_child(main_row)
	wrapper.add_child(details_vbox)
	
	resource_list_container.add_child(wrapper)
	resource_list_container.add_child(HSeparator.new())

func _toggle_resource_details(item_name: String, container: VBoxContainer, btn: Button):
	# If it's already open, close it!
	if container.visible:
		container.hide()
		btn.text = item_name + " \u25BC" # Down arrow
		return
		
	# If it's closed, open it and change the arrow!
	container.show()
	btn.text = item_name + " \u25B2" # Up arrow
	
	# Clear old data
	for child in container.get_children():
		child.queue_free()
		
	var found_any = false
	
	# Scan every building on the map!
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		
		var b_amount = 0
		
		# Type 1: Standard dictionary inventory (Stockpiles, Processors)
		if "inventory" in b and typeof(b.inventory) == TYPE_DICTIONARY:
			for key in b.inventory.keys():
				if key is ItemResource and key.display_name == item_name:
					b_amount += b.inventory[key]
				elif typeof(key) == TYPE_STRING and key == item_name:
					b_amount += b.inventory[key]
					
		# Type 2: Economy Assets (Mines that generate items directly)
		if b_amount == 0 and b.has_method("get_economy_assets"):
			var assets = b.get_economy_assets()
			if assets.has(item_name):
				b_amount += assets[item_name]
				
		# If this building has the item, spawn a row for it!
		if b_amount > 0:
			found_any = true
			var b_row = HBoxContainer.new()
			b_row.alignment = BoxContainer.ALIGNMENT_END
			
			var b_label = Label.new()
			b_label.text = "   \u2514 %s: %d" % [b.building_name, b_amount] # Creates an L-bracket tree look
			b_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b_label.modulate = Color(0.8, 0.8, 0.8)
			
			var locate_btn = Button.new()
			locate_btn.text = " Locate "
			locate_btn.modulate = Color(0.3, 0.8, 1.0)
			locate_btn.pressed.connect(func():
				var cam = get_tree().get_first_node_in_group("Camera")
				if cam and cam.has_method("set_follow_target"):
					cam.set_follow_target(b)
				close_menu()
			)
			
			b_row.add_child(b_label)
			b_row.add_child(locate_btn)
			container.add_child(b_row)
			
	# If the item only exists in Worker Bot hands or the void
	if not found_any:
		var empty = Label.new()
		empty.text = "   \u2514 Not currently stored in any building."
		empty.modulate = Color(0.5, 0.5, 0.5)
		container.add_child(empty)

func _toggle_pin(item_name: String):
	# If it's already pinned, remove it
	if EconomyManager.pinned_resources.has(item_name):
		EconomyManager.pinned_resources.erase(item_name)
	# If it's not pinned, add it (but enforce the 10 item max limit!)
	else:
		if EconomyManager.pinned_resources.size() < 10:
			EconomyManager.pinned_resources.append(item_name)
		else:
			print("Pin limit reached! Unpin something else first.")
			# Optional: You could spawn a floating text here to warn the player!
			return
			
	# Tell the UI to immediately redraw both the tab and the top bar!
	EconomyManager.inventory_changed.emit()
	_refresh_resource_tab()
# ==========================================
# INPUT LOGIC
# ==========================================

func _unhandled_input(event):
	# Escape to close
	if event.is_action_pressed("ui_cancel") and visible:
		close_menu()
		get_viewport().set_input_as_handled()
