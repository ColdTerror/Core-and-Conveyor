# ==============================================================================
# Script: UI/main_menu.gd
# Purpose: Manages Main Menu options, including starting new games, loading
#          saved slots, modifying audio configurations, and playing tactile transitions.
# Dependencies: Requires Autoloads AudioManager and SaveManager.
# ==============================================================================
extends Control

@onready var main_container = $CenterContainer/MainContainer
@onready var load_panel = $CenterContainer/LoadPanel
@onready var settings_panel = $CenterContainer/SettingsPanel

# Main buttons
@onready var new_game_btn = $CenterContainer/MainContainer/NewGame
@onready var load_game_btn = $CenterContainer/MainContainer/LoadGame
@onready var settings_btn = $CenterContainer/MainContainer/Settings
@onready var exit_btn = $CenterContainer/MainContainer/Exit

# Load slot references
@onready var load_1_btn = $CenterContainer/LoadPanel/VBoxContainer/Load1Bar/Load1
@onready var load_2_btn = $CenterContainer/LoadPanel/VBoxContainer/Load2Bar/Load2
@onready var load_3_btn = $CenterContainer/LoadPanel/VBoxContainer/Load3Bar/Load3
@onready var del_1_btn = $CenterContainer/LoadPanel/VBoxContainer/Load1Bar/Del1
@onready var del_2_btn = $CenterContainer/LoadPanel/VBoxContainer/Load2Bar/Del2
@onready var del_3_btn = $CenterContainer/LoadPanel/VBoxContainer/Load3Bar/Del3
@onready var load_back_btn = $CenterContainer/LoadPanel/VBoxContainer/Back

# Settings references
@onready var music_slider = $CenterContainer/SettingsPanel/VBoxContainer/MusicSlider
@onready var music_mute = $CenterContainer/SettingsPanel/VBoxContainer/MusicMute
@onready var sfx_slider = $CenterContainer/SettingsPanel/VBoxContainer/SfxSlider
@onready var sfx_mute = $CenterContainer/SettingsPanel/VBoxContainer/SfxMute
@onready var settings_back_btn = $CenterContainer/SettingsPanel/VBoxContainer/Back
@onready var keybinds_btn = $CenterContainer/SettingsPanel/VBoxContainer/Keybinds

var delete_confirm_dialog: ConfirmationDialog
var _pending_delete_slot: int = -1

func _ready():
	# Initialize confirm delete dialog
	delete_confirm_dialog = ConfirmationDialog.new()
	delete_confirm_dialog.title = "Confirm Delete"
	delete_confirm_dialog.dialog_text = "Are you sure you want to delete this save slot? This cannot be undone."
	delete_confirm_dialog.ok_button_text = "Delete"
	delete_confirm_dialog.cancel_button_text = "Cancel"
	delete_confirm_dialog.process_mode = PROCESS_MODE_ALWAYS
	delete_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	delete_confirm_dialog.canceled.connect(func(): _pending_delete_slot = -1)
	add_child(delete_confirm_dialog)
	# Hide overlays by default
	load_panel.hide()
	settings_panel.hide()
	main_container.show()
	
	# Connect main buttons
	new_game_btn.pressed.connect(_on_new_game)
	load_game_btn.pressed.connect(_on_open_load)
	settings_btn.pressed.connect(_on_open_settings)
	exit_btn.pressed.connect(_on_exit)
	
	# Connect sub-panels
	load_back_btn.pressed.connect(_on_close_subpanels)
	settings_back_btn.pressed.connect(_on_close_subpanels)
	
	# Load panel connections
	load_1_btn.pressed.connect(func(): _on_load_slot(1))
	load_2_btn.pressed.connect(func(): _on_load_slot(2))
	load_3_btn.pressed.connect(func(): _on_load_slot(3))
	del_1_btn.pressed.connect(func(): _on_delete_slot(1))
	del_2_btn.pressed.connect(func(): _on_delete_slot(2))
	del_3_btn.pressed.connect(func(): _on_delete_slot(3))
	
	# Settings panel connections
	music_slider.value = AudioManager.get_music_volume_linear()
	sfx_slider.value = AudioManager.get_sfx_volume_linear()
	music_mute.button_pressed = not AudioManager.is_music_muted
	sfx_mute.button_pressed = not AudioManager.is_sfx_muted
	
	music_slider.value_changed.connect(func(val): AudioManager.set_music_volume(val))
	sfx_slider.value_changed.connect(func(val): AudioManager.set_sfx_volume(val))
	music_mute.toggled.connect(func(is_enabled): AudioManager.set_music_muted(not is_enabled))
	sfx_mute.toggled.connect(func(is_enabled): AudioManager.set_sfx_muted(not is_enabled))
	
	keybinds_btn.pressed.connect(func():
		if get_node_or_null("KeybindSettingsMenu"): return
		var keybind_scene = load("res://scenes/ui/keybind_settings_menu.tscn")
		var menu = keybind_scene.instantiate()
		menu.name = "KeybindSettingsMenu"
		add_child(menu)
		menu.closed.connect(func(): menu.queue_free())
	)
	
	# Connect hover effects to all buttons
	var all_buttons = [
		new_game_btn, load_game_btn, settings_btn, exit_btn,
		load_1_btn, load_2_btn, load_3_btn, del_1_btn, del_2_btn, del_3_btn, load_back_btn,
		settings_back_btn, keybinds_btn
	]
	for btn in all_buttons:
		if is_instance_valid(btn):
			_setup_button_effects(btn)

func _setup_button_effects(btn: Button):
	var original_color = btn.self_modulate
	# Save original pivot and scaling settings so scale anchors from the center
	btn.pivot_offset = btn.size / 2.0
	btn.item_rect_changed.connect(func():
		btn.pivot_offset = btn.size / 2.0
	)
	
	btn.mouse_entered.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var hover_color = original_color * 1.2
		hover_color.a = original_color.a
		tween.tween_property(btn, "self_modulate", hover_color, 0.15)
	)
	btn.mouse_exited.connect(func():
		var tween = create_tween().set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "self_modulate", original_color, 0.15)
	)

func _on_new_game():
	# Fresh game, ensure save briefcase is clear
	SaveManager.pending_load_data.clear()
	get_tree().change_scene_to_file("res://scenes/level.tscn")

func _on_open_load():
	_refresh_load_menu()
	main_container.hide()
	load_panel.show()
	_animate_panel_entry(load_panel)

func _on_open_settings():
	# Sync UI settings state
	music_slider.value = AudioManager.get_music_volume_linear()
	sfx_slider.value = AudioManager.get_sfx_volume_linear()
	music_mute.button_pressed = not AudioManager.is_music_muted
	sfx_mute.button_pressed = not AudioManager.is_sfx_muted
	
	main_container.hide()
	settings_panel.show()
	_animate_panel_entry(settings_panel)

func _on_close_subpanels():
	load_panel.hide()
	settings_panel.hide()
	main_container.show()
	_animate_panel_entry(main_container)

func _on_exit():
	get_tree().quit()

func _on_load_slot(slot: int):
	var success = SaveManager.load_game(slot)
	if not success:
		# Flash error feedback
		var target_btn = null
		match slot:
			1: target_btn = load_1_btn
			2: target_btn = load_2_btn
			3: target_btn = load_3_btn
		if target_btn:
			_flash_button_error(target_btn)

func _on_delete_slot(slot: int):
	_pending_delete_slot = slot
	delete_confirm_dialog.popup_centered()

func _on_delete_confirmed():
	if _pending_delete_slot != -1:
		SaveManager.delete_save(_pending_delete_slot)
		_pending_delete_slot = -1
		_refresh_load_menu()

func _refresh_load_menu():
	_update_slot_ui(1, load_1_btn, del_1_btn)
	_update_slot_ui(2, load_2_btn, del_2_btn)
	_update_slot_ui(3, load_3_btn, del_3_btn)

func _update_slot_ui(slot: int, load_btn: Button, del_btn: Button):
	var exists = SaveManager.does_save_exist(slot)
	if exists:
		load_btn.disabled = false
		load_btn.text = "Load Save %d" % slot
		load_btn.modulate = Color.WHITE
		del_btn.disabled = false
		del_btn.modulate = Color.WHITE
	else:
		load_btn.disabled = true
		load_btn.text = "[ Empty Slot %d ]" % slot
		load_btn.modulate = Color(0.5, 0.5, 0.5)
		del_btn.disabled = true
		del_btn.modulate = Color(0.5, 0.5, 0.5, 0.5)

func _animate_panel_entry(panel: Control):
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.95, 0.95)
	panel.pivot_offset = panel.size / 2.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _flash_button_error(button: Button):
	var original_text = button.text
	var original_color = button.modulate
	button.disabled = true
	button.text = original_text + "  [ FAILED ]"
	button.modulate = Color(1.0, 0.4, 0.4)
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(button):
		button.text = original_text
		button.modulate = original_color
		button.disabled = false
