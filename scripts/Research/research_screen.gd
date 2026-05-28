# ==============================================================================
# Script: research_screen.gd
# Purpose: Handles rendering and arranging the interactive graph-based research tree 
#          menu, toggling screens, and syncing with the global game state menus.
# Dependencies: GameState Autoload. Expects a child GraphEdit node and a CloseButton.
# Signals:
#   - close_research_tree: Emitted when the research overlay is closed.
# ==============================================================================
@tool
extends CanvasLayer

# Clicking this checkbox in the Inspector triggers the layout function
@export var click_to_arrange_tree: bool = false:
	set(value):
		_arrange_nodes()

@onready var graph_edit = $BackgroundBlocker/MarginContainer/VBoxContainer/GraphEdit
@onready var close_button = $BackgroundBlocker/MarginContainer/VBoxContainer/Header/CloseButton

signal close_research_tree


## Sets up connections and sets initial visibility state during runtime initialization.
func _ready():
	# We don't want to connect game signals or hide the UI while we are working in the editor!
	if Engine.is_editor_hint():
		return 
		
	GameState.menu_changed.connect(_on_global_menu_changed)
	hide() # Hide when the game starts
	close_button.pressed.connect(close_screen)
	
	for node in graph_edit.get_children():
		if node is GraphNode and node.has_signal("research_started"):
			node.research_started.connect(close_screen)
			
	# Restore the custom centered scroll offset at runtime
	graph_edit.scroll_offset = Vector2(-375, -50)



## Automatically positions nodes and configures tree connections inside the editor or at runtime.
func _arrange_nodes():
	# Safely grab the GraphEdit (since @onready vars aren't always ready for @tool setters)
	var ge = get_node_or_null("BackgroundBlocker/MarginContainer/VBoxContainer/GraphEdit")
	if not ge:
		print("Could not find GraphEdit node to arrange!")
		return
		
	# Clear existing connections so Godot doesn't throw errors if you click the button twice
	ge.clear_connections()

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
	var row_belt     = 1000
	
	# POSITION EACH NODE
	_place(ge, "Core1", col_0, row_core)
	_place(ge, "Core2", col_1, row_core)
	_place(ge, "Core3", col_2, row_core)
	
	_place(ge, "Bot1", col_0, row_bots)
	_place(ge, "Bot2", col_1, row_bots)
	_place(ge, "Bot3", col_2, row_bots)
	
	_place(ge, "Building1", col_0, row_buildings)
	_place(ge, "Building2", col_1, row_buildings)
	_place(ge, "Building3", col_2, row_buildings)
	
	_place(ge, "Tower1", col_0, row_towers)
	_place(ge, "Tower2", col_1, row_towers)
	_place(ge, "Tower3", col_2, row_towers)
	
	_place(ge, "Global1", col_0, row_global)
	_place(ge, "Global2", col_1, row_global)
	_place(ge, "Global3", col_2, row_global)
	
	_place(ge, "Belt1", col_0, row_belt)
	_place(ge, "Belt2", col_1, row_belt)
	_place(ge, "Belt3", col_2, row_belt)

	# WIRE THE CONNECTIONS
	ge.connect_node("Core1", 0, "Core2", 0)
	ge.connect_node("Core2", 0, "Core3", 0)
	
	ge.connect_node("Bot1", 0, "Bot2", 0)
	ge.connect_node("Bot2", 0, "Bot3", 0)
	
	ge.connect_node("Building1", 0, "Building2", 0)
	ge.connect_node("Building2", 0, "Building3", 0)
	
	ge.connect_node("Tower1", 0, "Tower2", 0)
	ge.connect_node("Tower2", 0, "Tower3", 0)
	
	ge.connect_node("Global1", 0, "Global2", 0)
	ge.connect_node("Global2", 0, "Global3", 0)
	
	ge.connect_node("Belt1", 0, "Belt2", 0)
	ge.connect_node("Belt2", 0, "Belt3", 0)
	
	print("Research Tree Successfully Arranged!")



## Places a specific GraphNode at coordinates (x, y) and disables manual dragging.
func _place(ge: GraphEdit, node_name: String, x: float, y: float):
	var node = ge.get_node_or_null(node_name)
	if node:
		node.position_offset = Vector2(x, y)
		node.draggable = false 
	else:
		push_warning("Research node not found: " + node_name)



## Opens the research screen, updates all upgrade nodes, and registers menu focus.
func open_screen():
	if GameState.open_menu(GameState.MenuType.RESEARCH):
		_refresh_all_nodes()
		show()
		await get_tree().process_frame
		graph_edit.scroll_offset = Vector2(-375, -50)


## Iterates through children to refresh each upgrade node's research state.
func _refresh_all_nodes():
	for node in graph_edit.get_children():
		if node is GraphNode and node.has_method("_refresh_button"):
			node._refresh_button()


## Closes the research screen and releases menu focus.
func close_screen():
	GameState.close_menu()



## Hides the research screen and emits closing notifications if focus shifts.
func _on_global_menu_changed(active_menu):
	if active_menu != GameState.MenuType.RESEARCH:
		hide()
		close_research_tree.emit()
