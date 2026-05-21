# ==============================================================================
# Script: Managers/game_state.gd
# Purpose: Global state manager that routes full-screen UI panels, controls backwards-compatible menu open queries, and notifies UI overlay systems of layout updates.
# Dependencies: Requires standard Godot Node parent.
# Signals:
#   - menu_changed: Emitted when active fullscreen panel type changes.
# ==============================================================================
extends Node

# Add every full-screen or intercepting menu here
enum MenuType {
	NONE,
	RESEARCH,
	MANAGEMENT,
	STATS,
	DETAIL
}

var current_menu: MenuType = MenuType.NONE

# We emit this so menus know when to forcefully close themselves!
signal menu_changed(new_menu: MenuType)

# --- BACKWARDS COMPATIBILITY ---
# Your Camera script can still check GameState.is_menu_open without breaking!
var is_menu_open: bool:
	get:
		return current_menu != MenuType.NONE



## Opens the specified menu and routes screen transitions, notifying UI overlays of updates.
func open_menu(menu: MenuType) -> bool:
	if current_menu == menu: 
		return false # Menu is already open
		
	current_menu = menu
	menu_changed.emit(current_menu)
	return true



## Closes the currently active menu panel and resets global routing state to NONE.
func close_menu():
	if current_menu != MenuType.NONE:
		current_menu = MenuType.NONE
		menu_changed.emit(current_menu)
