extends CanvasLayer # (Or whatever your main UI script is)

@onready var detail_menu = $Popup_Layer/DetailMenu 
@onready var game_ui = $Hud_Layer/GameUI

@onready var research_screen = $ResearchScreen


func _ready():

	detail_menu.research_button_clicked.connect(_on_open_research_tree)
	research_screen.close_research_tree.connect(_on_close_research_tree)

# The function that runs when the signal is heard
func _on_open_research_tree():
	# 1. Close the little popup menu so it's out of the way
	detail_menu.close_menu()
	
	game_ui.hide()
	
	# 2. Open the massive fullscreen Tech Tree!
	research_screen.open_screen()

func _on_close_research_tree():
	game_ui.show()
