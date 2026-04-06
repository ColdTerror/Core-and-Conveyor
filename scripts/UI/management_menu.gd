extends PanelContainer
# ==========================================
# MANAGEMENT MENU (Priorities & Workers)
# ==========================================

@export var building_manager: BuildingManager

# --- UI REFERENCES ---
@onready var tab_container = $TabContainer

# Priorities Tab
@onready var priority_list_container = $TabContainer/Priorities/VBoxContainer/ScrollContainer/ListContainer

# Workers Tab
@onready var bot_list_container = $TabContainer/Workers/VBoxContainer/ScrollContainer/ListContainer

@onready var close_button = $Close
func _ready():
	#hide()
		
	if close_button:
		close_button.pressed.connect(close_menu)
		
	if tab_container:
		var tab_bar = tab_container.get_tab_bar()
		
		tab_bar.tab_clicked.connect(_on_tab_clicked)

		
func _on_tab_clicked(tab_index):
	# 1. Stop the TabContainer from automatically handling the click for a second
	# and manually store what the user WANTED to click.
	var target_tab = tab_index
	
	# 2. Perform the refresh
	if target_tab == 0:
		_refresh_priority_tab()
	elif target_tab == 1:
		_refresh_bot_tab()
		
	# 3. FORCE the tab to stay on the index the user clicked
	# We use call_deferred to make sure this is the LAST thing that happens this frame
	tab_container.call_deferred("set_current_tab", target_tab)

func toggle_menu():
	if visible:
		close_menu()
	else:
		open_menu()

func open_menu():
	_refresh_priority_tab()
	_refresh_bot_tab()
	show()

func close_menu():
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
	rank_label.custom_minimum_size = Vector2(30, 0) # Keeps alignment locked for double digits
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

func _refresh_bot_tab():
	if not bot_list_container: return
	
	# 1. Clean up old UI rows
	for child in bot_list_container.get_children():
		child.queue_free()
		
	# 2. Find all the bots currently in the world (Make sure your bots are in the "Workers" group!)
	var bots = get_tree().get_nodes_in_group("Bots")
	var bot_index = 1
	
	if bots.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No active worker bots."
		bot_list_container.add_child(empty_label)
		return

	# 3. Build a row for each bot
	for bot in bots:
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# --- NAME ---
		var name_label = Label.new()
		name_label.text = "Bot #" + str(bot_index)
		name_label.custom_minimum_size = Vector2(80, 0)
		
		# --- STATUS ---
		var status_label = Label.new()
		if bot.has_method("get_inventory_info"):
			var info = bot.get_inventory_info()
			status_label.text = "Task: %s | Carrying: %s" % [info.get("Target", "Idle"), info.get("Carrying", "Nothing")]
		else:
			status_label.text = "Task: Unknown"
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# --- FOLLOW BUTTON ---
		var follow_btn = Button.new()
		follow_btn.text = " Follow "
		follow_btn.modulate = Color(0.3, 0.8, 1.0) 
		
		follow_btn.pressed.connect(func():
			var cam = get_tree().get_first_node_in_group("Camera")
			if cam and cam.has_method("set_follow_target"):
				cam.set_follow_target(bot)
			close_menu() # Close the menu to see the bot immediately!
		)
		
		# Assemble the row
		row.add_child(name_label)
		row.add_child(status_label)
		row.add_child(follow_btn)
		
		var separator = HSeparator.new()
		
		bot_list_container.add_child(row)
		bot_list_container.add_child(separator)
		
		bot_index += 1

# ==========================================
# INPUT LOGIC
# ==========================================

func _unhandled_input(event):
	# Escape to close
	if event.is_action_pressed("ui_cancel") and visible:
		close_menu()
		get_viewport().set_input_as_handled()
