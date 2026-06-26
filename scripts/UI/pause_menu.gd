# ==============================================================================
# Script: UI/pause_menu.gd
# Purpose: Dictates CanvasLayer pause screen interactions, handling manual/quick state saving and loading, audio volumes (SFX/Music mute toggles and linear sliders), and game exits.
# Dependencies: Requires Autoloads AudioManager and SaveManager. Needs child button/slider UI node controls.
# Signals:
#   - save_requested(slot: int): Emitted when the user triggers a manual/quick save event.
# ==============================================================================
extends CanvasLayer

signal save_requested(slot: int)

@onready var quick_save_btn = $CenterContainer/VBoxContainer/QuickSave
@onready var save_1_btn = $CenterContainer/VBoxContainer/Save1
@onready var save_2_btn = $CenterContainer/VBoxContainer/Save2
@onready var save_3_btn = $CenterContainer/VBoxContainer/Save3

@onready var load_1_btn = $CenterContainer/VBoxContainer/Load1Bar/Load1
@onready var load_2_btn = $CenterContainer/VBoxContainer/Load2Bar/Load2
@onready var load_3_btn = $CenterContainer/VBoxContainer/Load3Bar/Load3

@onready var del_1_btn = $CenterContainer/VBoxContainer/Load1Bar/Del1
@onready var del_2_btn = $CenterContainer/VBoxContainer/Load2Bar/Del2
@onready var del_3_btn = $CenterContainer/VBoxContainer/Load3Bar/Del3

@onready var music_mute = $CenterContainer/VBoxContainer/MusicMute
@onready var music_slider = $CenterContainer/VBoxContainer/MusicSlider
@onready var sfx_mute = $CenterContainer/VBoxContainer/SfxMute
@onready var sfx_slider = $CenterContainer/VBoxContainer/SfxSlider

@onready var resume_button = $CenterContainer/VBoxContainer/Resume
@onready var menu_button = $CenterContainer/VBoxContainer/Menu
@onready var exit_button = $CenterContainer/VBoxContainer/Exit

var confirm_dialog: ConfirmationDialog
var _pending_load_slot: int = -1
var _pending_load_button: Button = null

var confirm_save_dialog: ConfirmationDialog
var _pending_save_slot: int = -1
var _pending_save_button: Button = null

var quit_dialog: ConfirmationDialog
var _is_quitting_to_desktop: bool = false



## Connects save/load buttons, slider volume signals, quicksave actions, and delete actions.
func _ready():
	hide()
	
	music_slider.value = AudioManager.get_music_volume_linear()
	sfx_slider.value = AudioManager.get_sfx_volume_linear()
	
	# Checkbox toggle setups
	music_mute.button_pressed = not AudioManager.is_music_muted
	sfx_mute.button_pressed = not AudioManager.is_sfx_muted
	
	resume_button.pressed.connect(resume_game)
	menu_button.pressed.connect(_on_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	music_slider.value_changed.connect(func(val):
		AudioManager.set_music_volume(val)
	)
	sfx_slider.value_changed.connect(func(val):
		AudioManager.set_sfx_volume(val)
	)
	
	music_mute.toggled.connect(func(is_enabled: bool):
		AudioManager.set_music_muted(not is_enabled)
	)
	sfx_mute.toggled.connect(func(is_enabled: bool):
		AudioManager.set_sfx_muted(not is_enabled)
	)
	
	# Quick save action
	quick_save_btn.pressed.connect(func(): 
		save_requested.emit(SaveManager.current_slot)
		resume_game()
	)
	
	# Manual save callbacks
	save_1_btn.pressed.connect(func(): _perform_manual_save(1, save_1_btn))
	save_2_btn.pressed.connect(func(): _perform_manual_save(2, save_2_btn))
	save_3_btn.pressed.connect(func(): _perform_manual_save(3, save_3_btn))
	
	load_1_btn.pressed.connect(func(): _perform_manual_load(1, load_1_btn))
	load_2_btn.pressed.connect(func(): _perform_manual_load(2, load_2_btn))
	load_3_btn.pressed.connect(func(): _perform_manual_load(3, load_3_btn))
	
	# Delete button connections
	del_1_btn.pressed.connect(func(): _perform_delete(1))
	del_2_btn.pressed.connect(func(): _perform_delete(2))
	del_3_btn.pressed.connect(func(): _perform_delete(3))
	
	#Add confirm load dialog to scene tree
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Confirm Load"
	confirm_dialog.dialog_text = "Are you sure you want to load? Any unsaved progress will be lost."
	confirm_dialog.ok_button_text = "Yes"
	confirm_dialog.cancel_button_text = "No"
	confirm_dialog.process_mode = PROCESS_MODE_ALWAYS
	confirm_dialog.confirmed.connect(_on_load_confirmed)
	confirm_dialog.canceled.connect(func():
		_pending_load_slot = -1
		_pending_load_button = null
	)
	add_child(confirm_dialog)
	
	#Add confirm save dialog to scene tree
	confirm_save_dialog = ConfirmationDialog.new()
	confirm_save_dialog.title = "Confirm Overwrite"
	confirm_save_dialog.dialog_text = "Are you sure you want to overwrite this save slot? The existing save data will be replaced."
	confirm_save_dialog.ok_button_text = "Yes"
	confirm_save_dialog.cancel_button_text = "No"
	confirm_save_dialog.process_mode = PROCESS_MODE_ALWAYS
	confirm_save_dialog.confirmed.connect(_on_save_confirmed)
	confirm_save_dialog.canceled.connect(func():
		_pending_save_slot = -1
		_pending_save_button = null
	)
	add_child(confirm_save_dialog)
	
	#Add quit without saving dialog to scene tree
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "Confirm Action"
	quit_dialog.dialog_text = "Are you sure?"
	quit_dialog.ok_button_text = "Yes"
	quit_dialog.cancel_button_text = "No"
	quit_dialog.process_mode = PROCESS_MODE_ALWAYS
	quit_dialog.confirmed.connect(_on_quit_confirmed)
	add_child(quit_dialog)


## Listens for the pause action to pause/resume the game.
func _input(event):
	if event.is_action_pressed("pause_button"):
		if visible:
			resume_game()
		else:
			pause_game()



## Halts gameplay, muffles jukebox background audio, and displays the options screen.
func pause_game():
	show()
	get_tree().paused = true
	# Sync quick save text
	quick_save_btn.text = "Quick Save (Slot %d)" % SaveManager.current_slot
	_refresh_menu_state()
	AudioManager.set_music_muffled(true)



## Restores active game execution and resets music filter setups.
func resume_game():
	hide()
	get_tree().paused = false
	AudioManager.set_music_muffled(false)


## Back to Main Menu 
func back_to_menu():
	hide()
	get_tree().paused = false
	#AudioManager.set_music_muffled(false)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	

## Exits the game.
func exit_game():
	get_tree().quit()


func _on_menu_pressed():
	_is_quitting_to_desktop = false
	quit_dialog.title = "Confirm Return to Menu"
	quit_dialog.dialog_text = "Are you sure you want to return to the Main Menu? Any unsaved progress will be lost."
	quit_dialog.reset_size()
	quit_dialog.popup_centered()


func _on_exit_pressed():
	_is_quitting_to_desktop = true
	quit_dialog.title = "Confirm Exit Game"
	quit_dialog.dialog_text = "Are you sure you want to Exit Game? Any unsaved progress will be lost."
	quit_dialog.reset_size()
	quit_dialog.popup_centered()


func _on_quit_confirmed():
	if _is_quitting_to_desktop:
		exit_game()
	else:
		back_to_menu()



## Pulls saved slot indexes and syncs sound sliders with manager settings.
func _refresh_menu_state():
	# Re-verify profiles
	_update_load_slot_ui(1, load_1_btn, del_1_btn)
	_update_load_slot_ui(2, load_2_btn, del_2_btn)
	_update_load_slot_ui(3, load_3_btn, del_3_btn)
	
	music_slider.value = AudioManager.get_music_volume_linear()
	sfx_slider.value = AudioManager.get_sfx_volume_linear()
	
	music_mute.button_pressed = not AudioManager.is_music_muted
	sfx_mute.button_pressed = not AudioManager.is_sfx_muted



## Toggles visual disable states and labels for empty or populated save files.
func _update_load_slot_ui(slot: int, load_btn: Button, del_btn: Button):
	var exists = SaveManager.does_save_exist(slot)
	
	if exists:
		load_btn.disabled = false
		load_btn.text = "Load Game %d" % slot
		load_btn.modulate = Color.WHITE
		del_btn.show()
	else:
		load_btn.disabled = true
		load_btn.text = "[ Empty Slot %d ]" % slot
		load_btn.modulate = Color(0.5, 0.5, 0.5)
		del_btn.hide()



## Purges a specific slot profile through the SaveManager.
func _perform_delete(slot: int):
	# Delete profile
	SaveManager.delete_save(slot)
	_refresh_menu_state()



## Emits file write requests and displays flash green ticks upon completion.
func _perform_manual_save(slot: int, button: Button):
	if SaveManager.does_save_exist(slot):
		_pending_save_slot = slot
		_pending_save_button = button
		confirm_save_dialog.dialog_text = "Are you sure you want to overwrite Save %d? The existing save data will be replaced." % slot
		confirm_save_dialog.popup_centered()
	else:
		_execute_save(slot, button)


func _execute_save(slot: int, button: Button):
	# Trigger manual save
	save_requested.emit(slot)
	
	# Trigger visual feedback
	_flash_button_success(button)
	_refresh_menu_state()


func _on_save_confirmed():
	if _pending_save_slot == -1: return
	_execute_save(_pending_save_slot, _pending_save_button)
	_pending_save_slot = -1
	_pending_save_button = null



## Overlays a green checkmark indicating successful data saving.
func _flash_button_success(button: Button):
	if button.disabled: return
	
	# Store original style
	button.disabled = true
	var original_text = button.text
	var original_color = button.modulate
	
	# Change to success visuals
	button.text = original_text + "  [ SAVED \u2713 ]"
	button.modulate = Color(0.4, 1.0, 0.4)
	
	# Wait 1.5 seconds
	await get_tree().create_timer(1.5).timeout
	
	# Restore original visuals
	if is_instance_valid(button):
		button.text = original_text
		button.modulate = original_color
		button.disabled = false



## Initiates profiles recovery and handles failure alerts.
func _perform_manual_load(slot: int, button: Button):
	_pending_load_slot = slot
	_pending_load_button = button
	confirm_dialog.popup_centered()



## Confirms and recovers the selected profile slot.
func _on_load_confirmed():
	if _pending_load_slot == -1: return
	
	AudioManager.set_music_muffled(false)
	var success = SaveManager.load_game(_pending_load_slot)
	
	if not success and is_instance_valid(_pending_load_button):
		_flash_button_error(_pending_load_button)
		
	_pending_load_slot = -1
	_pending_load_button = null



## Displays red alert labels showing that a slot profile is invalid or empty.
func _flash_button_error(button: Button):
	if button.disabled: return
	# Store original style
	var original_text = button.text
	var original_color = button.modulate
	
	# Change it to an error state!
	button.disabled = true
	button.text = original_text + "  [ EMPTY \u2717 ]"
	button.modulate = Color(1.0, 0.4, 0.4)
	
	# Wait 1.5 seconds
	await get_tree().create_timer(1.5).timeout
	
	# Restore original visuals
	if is_instance_valid(button):
		button.text = original_text
		button.modulate = original_color
		button.disabled = false



## Triggers save file recovery by slot ID.
func _on_load_slot(slot: int):
	SaveManager.load_game(slot)
