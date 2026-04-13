extends CanvasLayer

signal save_requested(slot: int)

@onready var quick_save_btn = $CenterContainer/VBoxContainer/QuickSave
@onready var save_1_btn = $CenterContainer/VBoxContainer/Save1
@onready var save_2_btn = $CenterContainer/VBoxContainer/Save2
@onready var save_3_btn = $CenterContainer/VBoxContainer/Save3

@onready var load_1_btn = $CenterContainer/VBoxContainer/Load1
@onready var load_2_btn = $CenterContainer/VBoxContainer/Load2
@onready var load_3_btn = $CenterContainer/VBoxContainer/Load3

func _ready():
	# Hide the menu when the game starts
	hide()
	
	# Wire up all the buttons
	$CenterContainer/VBoxContainer/Resume.pressed.connect(resume_game)
	$CenterContainer/VBoxContainer/Exit.pressed.connect(exit_game)
	
	# Quick Save: Emits the signal, then instantly resumes the game!
	quick_save_btn.pressed.connect(func(): 
		save_requested.emit(SaveManager.current_slot)
		resume_game()
	)
	
	# Manual Saves: Emits the signal, keeps the menu open, and flashes the checkmark!
	save_1_btn.pressed.connect(func(): _perform_manual_save(1, save_1_btn))
	save_2_btn.pressed.connect(func(): _perform_manual_save(2, save_2_btn))
	save_3_btn.pressed.connect(func(): _perform_manual_save(3, save_3_btn))
	
	load_1_btn.pressed.connect(func(): _perform_manual_load(1, load_1_btn))
	load_2_btn.pressed.connect(func(): _perform_manual_load(2, load_2_btn))
	load_3_btn.pressed.connect(func(): _perform_manual_load(3, load_3_btn))

func _input(event):
	# Assuming you have an input action mapped to the Escape key called "ui_cancel"
	if event.is_action_pressed("pause_button"):
		if visible:
			resume_game()
		else:
			pause_game()

func pause_game():
	show()
	get_tree().paused = true
	# Update the quick save button text so the player knows which slot it will use
	$CenterContainer/VBoxContainer/QuickSave.text = "Quick Save (Slot %d)" % SaveManager.current_slot

func resume_game():
	hide()
	get_tree().paused = false

func exit_game():
	get_tree().quit()

func _perform_manual_save(slot: int, button: Button):
	# 1. Tell the Level to save the game
	save_requested.emit(slot)
	
	# 2. Trigger the visual feedback
	_flash_button_success(button)

func _flash_button_success(button: Button):
	# Remember what the button originally looked like
	var original_text = button.text
	var original_color = button.modulate
	
	# Change it to a success state!
	button.text = original_text + "  [ SAVED \u2713 ]" # \u2713 is a Unicode Checkmark!
	button.modulate = Color(0.4, 1.0, 0.4) # Bright Green
	
	# Wait for 1.5 seconds... (using process_always so it works while paused!)
	await get_tree().create_timer(1.5).timeout
	
	# Make sure the menu/button wasn't destroyed while we were waiting
	if is_instance_valid(button):
		button.text = original_text
		button.modulate = original_color
	
func _perform_manual_load(slot: int, button: Button):
	# SaveManager.load_game returns a boolean!
	var success = SaveManager.load_game(slot)
	
	# If it failed (file doesn't exist or is corrupted), flash the error!
	# (If it succeeded, the scene is reloading right now, so we do nothing!)
	if not success:
		_flash_button_error(button)

func _flash_button_error(button: Button):
	# Remember what the button originally looked like
	var original_text = button.text
	var original_color = button.modulate
	
	# Change it to an error state!
	button.text = original_text + "  [ EMPTY \u2717 ]" # \u2717 is a Unicode 'X'!
	button.modulate = Color(1.0, 0.4, 0.4) # Bright Red
	
	# Wait for 1.5 seconds... 
	await get_tree().create_timer(1.5).timeout
	
	# Make sure the menu/button wasn't destroyed while we were waiting
	if is_instance_valid(button):
		button.text = original_text
		button.modulate = original_color
		
func _on_load_slot(slot: int):
	SaveManager.load_game(slot)
