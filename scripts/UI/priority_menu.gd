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
	
	# --- UP ARROW ---
	var up_btn = Button.new()
	up_btn.text = " ▲ "
	up_btn.disabled = (rank == 1)
	up_btn.pressed.connect(func():
		building_manager.move_priority_up(item)
		refresh_ui()
	)
	
	# --- TEXT LABEL ---
	var label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Format the text depending on if it is a Group String or a Building Node!
	if typeof(item) == TYPE_STRING:
		label.text = "%d. [Group] %s" % [rank, item]
		label.modulate = Color(0.8, 0.8, 1.0) # Light blue for groups
	else:
		if is_instance_valid(item) and "building_name" in item:
			label.text = "%d. %s" % [rank, item.building_name]
		else:
			label.text = "%d. [Invalid]" % rank
			
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
	hbox.add_child(label)
	hbox.add_child(down_btn)
	
	list_container.add_child(hbox)
