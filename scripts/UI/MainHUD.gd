# ==============================================================================
# Script: UI/MainHUD.gd
# Purpose: Main HUD layer coordinator that listens to detail menu and research screen
#          signals to toggle layouts and menus.
# Dependencies: DetailMenu, GameUI, HotBar_UI, ResearchScreen, ManagementMenu child nodes.
# Signals: None.
# ==============================================================================
extends CanvasLayer # (Or whatever your main UI script is)

@onready var detail_menu = $Popup_Layer/DetailMenu 
@onready var game_ui = $Hud_Layer/GameUI
@onready var hotbar = $Hud_Layer/HotBar_UI

@onready var research_screen = $ResearchScreen
@onready var management_menu = $Popup_Layer/ManagementMenu


## Connects overlay triggers and hotkey triggers from UI panels.
func _ready():
	detail_menu.research_button_clicked.connect(_on_open_research_tree)
	research_screen.close_research_tree.connect(_on_close_research_tree)
	detail_menu.quota_shortcut_clicked.connect(_on_quota_shortcut_clicked)



## Hides the hotbar and standard HUD to reveal the fullscreen research screen.
func _on_open_research_tree():
	# Close the little popup menu so it's out of the way
	detail_menu.close_menu()
	hotbar.hide()
	game_ui.hide()
	
	# Open the massive fullscreen Tech Tree!
	research_screen.open_screen()


## Restores standard HUD and hotbar layouts.
func _on_close_research_tree():
	game_ui.show()
	hotbar.show()


## Opens the management panel and focuses the quota tracking schedule tab.
func _on_quota_shortcut_clicked():
	management_menu.open_menu()
	
	# Force it to switch immediately to Tab 4 (The Quota Tab)
	management_menu._on_tab_clicked(4)
