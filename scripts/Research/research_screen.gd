extends CanvasLayer

# Make sure this path points exactly to your GraphEdit node!
@onready var graph_edit = $BackgroundBlocker/MarginContainer/VBoxContainer/GraphEdit
@onready var close_button = $BackgroundBlocker/MarginContainer/VBoxContainer/Header/CloseButton

signal close_research_tree

func _ready():
	hide() # Hide when the game starts
	close_button.pressed.connect(close_screen)
	
	# ==========================================
	# AUTOMATIC WIRE DRAWING
	# ==========================================
	# Syntax: connect_node("FromNodeName", from_port_id, "ToNodeName", to_port_id)
	# IMPORTANT: The string names here must EXACTLY match the names of the nodes in your scene tree!
	
	# 1. Wire to the Bots Branch
	graph_edit.connect_node("CoreStart", 0, "BotBranch", 0)
	
	# 2. Wire to the Buildings Branch
	graph_edit.connect_node("CoreStart", 0, "BuildingBranch", 0)
	
	# 3. Wire to the Global Upgrades Branch
	graph_edit.connect_node("CoreStart", 0, "GlobalBranch", 0)


func open_screen():
	GameState.is_menu_open = true
	show()

func close_screen():
	GameState.is_menu_open = false
	close_research_tree.emit()
	hide()
