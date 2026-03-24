extends CanvasLayer

@onready var close_button = $BackgroundBlocker/MarginContainer/VBoxContainer/Header/CloseButton

signal close_research_tree

func _ready():
	hide() # Hide when the game starts
	close_button.pressed.connect(close_screen)

func open_screen():
	GameState.is_menu_open = true
	show()

func close_screen():
	GameState.is_menu_open = false
	close_research_tree.emit()
	hide()
