extends CanvasLayer

# Make sure this path points exactly to your GraphEdit node!
@onready var graph_edit = $BackgroundBlocker/MarginContainer/VBoxContainer/GraphEdit
@onready var close_button = $BackgroundBlocker/MarginContainer/VBoxContainer/Header/CloseButton

signal close_research_tree

func _ready():
	#hide() # Hide when the game starts
	close_button.pressed.connect(close_screen)
	
	for node in graph_edit.get_children():
		if node is GraphNode and node.has_signal("research_started"):
			node.research_started.connect(close_screen)
	
	# COLUMN X POSITIONS (left to right = tier depth)
	var col_0 = 0    # Branch headers (parents)
	var col_1 = 500  # Tier 1 children
	var col_2 = 1000  # Tier 2 children
	var col_3 = 1500 # Tier 3 children

	# ROW Y POSITIONS (top to bottom = different branches)
	var row_core     = 0
	var row_bots     = 200
	var row_buildings = 400
	var row_towers   = 600
	var row_global   = 800
	
	
	# ==========================================
	# POSITION EACH NODE
	# ==========================================
	
	_place("Core1", col_0, row_core)
	_place("Core2", col_1, row_core)
	
	
	_place("Bot1", col_0, row_bots)
	_place("Bot2", col_1, row_bots)
	
	_place("Building1", col_0, row_buildings)
	_place("Building2", col_1, row_buildings)
	
	_place("Tower1", col_0, row_towers)
	_place("Tower2", col_1, row_towers)
	
	_place("Global1", col_0, row_global)
	_place("Global2", col_1, row_global)
	
	# ==========================================
	# WIRE THE CONNECTIONS
	# ==========================================
	graph_edit.connect_node("Core1", 0, "Core2", 0)
	
	graph_edit.connect_node("Bot1", 0, "Bot2", 0)
	
	graph_edit.connect_node("Building1", 0, "Building2", 0)
	
	graph_edit.connect_node("Tower1", 0, "Tower2", 0)
	
	graph_edit.connect_node("Global1", 0, "Global2", 0)

	

# ==========================================
# HELPER
# ==========================================
func _place(node_name: String, x: float, y: float):
	var node = graph_edit.get_node(node_name)
	if node:
		node.position_offset = Vector2(x, y)
		node.draggable = false  # ← Add this
	else:
		push_warning("Research node not found: " + node_name)

func open_screen():
	GameState.is_menu_open = true
	show()

func close_screen():
	GameState.is_menu_open = false
	close_research_tree.emit()
	hide()
	
func _unhandled_input(event):
	# If the user presses Escape, AND this specific menu is currently open on screen...
	if event.is_action_pressed("ui_cancel") and visible:
		
		# 1. Close the menu! 
		# (Change 'hide()' to 'close_menu()' if your script has a custom cleanup function)
		close_screen()
		
		# 2. Consume the input so it doesn't leak into the game world
		get_viewport().set_input_as_handled()
