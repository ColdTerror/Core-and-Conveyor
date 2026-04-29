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


# --- AUDIO UI REFERENCES ---
@onready var music_mute = $CenterContainer/VBoxContainer/MusicMute
@onready var music_slider = $CenterContainer/VBoxContainer/MusicSlider
@onready var sfx_mute = $CenterContainer/VBoxContainer/SfxMute
@onready var sfx_slider = $CenterContainer/VBoxContainer/SfxSlider


func _ready():
	# Hide the menu when the game starts
	hide()
	# Set default music volume to 50%
	music_slider.value = 0.5
	AudioManager.set_music_volume(music_slider.value)
	
	# Set default sfx volume to 50%
	sfx_slider.value = 0.5
	AudioManager.set_music_volume(sfx_slider.value)
	# Wire up all the buttons
	$CenterContainer/VBoxContainer/Resume.pressed.connect(resume_game)
	$CenterContainer/VBoxContainer/Exit.pressed.connect(exit_game)
	
	
	# Wire up all the audio signals
	music_slider.value_changed.connect(AudioManager.set_music_volume)
	sfx_slider.value_changed.connect(AudioManager.set_sfx_volume)
	
	# When checked (true), muted is false. When unchecked (false), muted is true!
	music_mute.toggled.connect(func(is_enabled: bool):
		AudioManager.set_music_muted(not is_enabled)
	)
	sfx_mute.toggled.connect(func(is_enabled: bool):
		AudioManager.set_sfx_muted(not is_enabled)
	)
	
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
	
	# Wire up the Delete buttons
	del_1_btn.pressed.connect(func(): _perform_delete(1))
	del_2_btn.pressed.connect(func(): _perform_delete(2))
	del_3_btn.pressed.connect(func(): _perform_delete(3))

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
	_refresh_menu_state()
	AudioManager.set_music_muffled(true)

func resume_game():
	hide()
	get_tree().paused = false
	AudioManager.set_music_muffled(false)

func exit_game():
	get_tree().quit()

# ==========================================
# THE MAGIC REFRESH FUNCTION
# ==========================================
func _refresh_menu_state():
	# Loop through all 3 slots and check if they exist
	_update_load_slot_ui(1, load_1_btn, del_1_btn)
	_update_load_slot_ui(2, load_2_btn, del_2_btn)
	_update_load_slot_ui(3, load_3_btn, del_3_btn)

func _update_load_slot_ui(slot: int, load_btn: Button, del_btn: Button):
	var exists = SaveManager.does_save_exist(slot)
	
	if exists:
		load_btn.disabled = false
		load_btn.text = "Load Game %d" % slot
		load_btn.modulate = Color.WHITE
		del_btn.show() # Show the X button!
	else:
		load_btn.disabled = true
		load_btn.text = "[ Empty Slot %d ]" % slot
		load_btn.modulate = Color(0.5, 0.5, 0.5) # Gray it out
		del_btn.hide() # Hide the X button

func _perform_delete(slot: int):
	# Tell the manager to delete the file
	SaveManager.delete_save(slot)
	
	# Instantly refresh the UI so the button grays out!
	_refresh_menu_state()
	
func _perform_manual_save(slot: int, button: Button):
	# 1. Tell the Level to save the game
	save_requested.emit(slot)
	
	# 2. Trigger the visual feedback
	_flash_button_success(button)
	
	_refresh_menu_state()

func _flash_button_success(button: Button):
	if button.disabled: return
	
	# Remember what the button originally looked like
	button.disabled = true
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
		button.disabled = false
	
func _perform_manual_load(slot: int, button: Button):
	# SaveManager.load_game returns a boolean!
	var success = SaveManager.load_game(slot)
	
	# If it failed (file doesn't exist or is corrupted), flash the error!
	# (If it succeeded, the scene is reloading right now, so we do nothing!)
	if not success:
		_flash_button_error(button)

func _flash_button_error(button: Button):
	if button.disabled: return
	# Remember what the button originally looked like
	var original_text = button.text
	var original_color = button.modulate
	
	# Change it to an error state!
	button.disabled = true
	button.text = original_text + "  [ EMPTY \u2717 ]" # \u2717 is a Unicode 'X'!
	button.modulate = Color(1.0, 0.4, 0.4) # Bright Red
	
	# Wait for 1.5 seconds... 
	await get_tree().create_timer(1.5).timeout
	
	# Make sure the menu/button wasn't destroyed while we were waiting
	if is_instance_valid(button):
		button.text = original_text
		button.modulate = original_color
		button.disabled = false
		
func _on_load_slot(slot: int):
	SaveManager.load_game(slot)
