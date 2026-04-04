extends PanelContainer

@export var building_manager: BuildingManager

@onready var list_container = $VBoxContainer/ScrollContainer/ListContainer
@onready var close_button = $VBoxContainer/Header/CloseButton

func _ready():
	hide()
	close_button.pressed.connect(close_menu)

func toggle_menu():
	if visible:
		close_menu()
	else:
		open_menu()

func open_menu():
	refresh_ui()
	show()

func close_menu():
	hide()

func refresh_ui():
	# 1. Clean up old rows
	for child in list_container.get_children():
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
		refresh_ui()
	)
	
	# DEDICATED RANK LABEL
	var rank_label = Label.new()
	rank_label.text = str(rank) + "."
	rank_label.custom_minimum_size = Vector2(30, 0) # Keeps alignment locked for double digits
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	

	# NAME BUTTON
	var name_btn = Button.new()
	name_btn.custom_minimum_size = Vector2(200, 0)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER # Centers the text inside the expanding button
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
		refresh_ui()
	)
	
	# Assemble the row
	hbox.add_child(up_btn)
	hbox.add_child(rank_label) # Add the rank on the left
	hbox.add_child(name_btn)   # Add the centered name in the middle
	hbox.add_child(down_btn)
	
	list_container.add_child(hbox)
	
func _unhandled_input(event):
	# If the user presses Escape, AND this specific menu is currently open on screen...
	if event.is_action_pressed("ui_cancel") and visible:
		
		# 1. Close the menu! 
		# (Change 'hide()' to 'close_menu()' if your script has a custom cleanup function)
		close_menu()
		
		# 2. Consume the input so it doesn't leak into the game world
		get_viewport().set_input_as_handled()
