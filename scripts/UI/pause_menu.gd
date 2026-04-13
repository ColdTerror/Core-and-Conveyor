extends CanvasLayer

signal save_requested(slot: int)

func _ready():
	# Hide the menu when the game starts
	hide()
	
	# Wire up all the buttons
	$CenterContainer/VBoxContainer/Resume.pressed.connect(resume_game)
	$CenterContainer/VBoxContainer/Exit.pressed.connect(exit_game)
	
	$CenterContainer/VBoxContainer/QuickSave.pressed.connect(func(): save_requested.emit(SaveManager.current_slot))
	$CenterContainer/VBoxContainer/Save1.pressed.connect(func(): save_requested.emit(1))
	$CenterContainer/VBoxContainer/Save2.pressed.connect(func(): save_requested.emit(2))
	$CenterContainer/VBoxContainer/Save3.pressed.connect(func(): save_requested.emit(3))
	
	$CenterContainer/VBoxContainer/Load1.pressed.connect(func(): _on_load_slot(1))
	$CenterContainer/VBoxContainer/Load2.pressed.connect(func(): _on_load_slot(2))
	$CenterContainer/VBoxContainer/Load3.pressed.connect(func(): _on_load_slot(3))

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

func _on_load_slot(slot: int):
	SaveManager.load_game(slot)
