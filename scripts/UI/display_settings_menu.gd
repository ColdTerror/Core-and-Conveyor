# ==============================================================================
# Script: UI/display_settings_menu.gd
# Purpose: Interactive popup menu allowing players to switch display modes (Borderless,
#          Exclusive Fullscreen, Windowed), resolutions, V-Sync, and frame limits.
# Dependencies: Requires SettingsManager autoload.
# Signals:
#   - closed(): Emitted when the player closes the display menu.
# ==============================================================================
extends CanvasLayer

signal closed

@onready var window_mode_option: OptionButton = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/GridContainer/WindowModeOption
@onready var resolution_option: OptionButton = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/GridContainer/ResolutionOption
@onready var vsync_check: CheckBox = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/GridContainer/VsyncCheck
@onready var fps_option: OptionButton = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/GridContainer/FpsOption
@onready var resolution_hint: Label = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResolutionHint

@onready var apply_button: Button = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Apply
@onready var close_button: Button = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Close

var _resolutions: Array[Vector2i] = []


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	
	_populate_options()
	_sync_from_settings()
	
	window_mode_option.item_selected.connect(_on_window_mode_changed)
	apply_button.pressed.connect(_on_apply_pressed)
	close_button.pressed.connect(func(): closed.emit())


func _populate_options() -> void:
	# 1. Window Modes
	window_mode_option.clear()
	window_mode_option.add_item("Borderless Fullscreen (Recommended)", SettingsManager.WindowMode.BORDERLESS_FULLSCREEN)
	window_mode_option.add_item("Exclusive Fullscreen", SettingsManager.WindowMode.EXCLUSIVE_FULLSCREEN)
	window_mode_option.add_item("Windowed", SettingsManager.WindowMode.WINDOWED)

	# 2. Resolutions
	resolution_option.clear()
	_resolutions = SettingsManager.get_available_resolutions()
	for i in range(_resolutions.size()):
		var res = _resolutions[i]
		var label = "%d x %d" % [res.x, res.y]
		if res == Vector2i(1920, 1080):
			label += " (1080p)"
		elif res == Vector2i(2560, 1440):
			label += " (1440p)"
		elif res == Vector2i(3840, 2160):
			label += " (4K UHD)"
		elif res == Vector2i(1280, 720):
			label += " (720p)"
		resolution_option.add_item(label, i)

	# 3. FPS Limits
	fps_option.clear()
	fps_option.add_item("Uncapped", 0)
	fps_option.add_item("60 FPS", 1)
	fps_option.add_item("120 FPS", 2)
	fps_option.add_item("144 FPS", 3)


func _sync_from_settings() -> void:
	# Select current window mode
	for i in range(window_mode_option.item_count):
		if window_mode_option.get_item_id(i) == SettingsManager.current_window_mode:
			window_mode_option.select(i)
			break

	# Select current resolution
	var found_res = false
	for i in range(_resolutions.size()):
		if _resolutions[i] == SettingsManager.current_resolution:
			resolution_option.select(i)
			found_res = true
			break
	if not found_res and _resolutions.size() > 0:
		resolution_option.select(0)

	# V-Sync
	vsync_check.button_pressed = SettingsManager.current_vsync

	# FPS limit
	var fps_idx = 0
	match SettingsManager.current_fps_limit:
		60: fps_idx = 1
		120: fps_idx = 2
		144: fps_idx = 3
		_: fps_idx = 0
	fps_option.select(fps_idx)

	_update_resolution_interactivity(SettingsManager.current_window_mode)


func _on_window_mode_changed(index: int) -> void:
	var mode = window_mode_option.get_item_id(index) as SettingsManager.WindowMode
	_update_resolution_interactivity(mode)


func _update_resolution_interactivity(mode: SettingsManager.WindowMode) -> void:
	if mode == SettingsManager.WindowMode.WINDOWED:
		resolution_option.disabled = false
		resolution_hint.text = "Select a window size to fit your screen."
	else:
		resolution_option.disabled = true
		resolution_hint.text = "Fullscreen automatically adapts to your monitor's native display."


func _on_apply_pressed() -> void:
	var selected_mode_id = window_mode_option.get_selected_id() as SettingsManager.WindowMode
	var res_idx = resolution_option.get_selected_id()
	var selected_res = _resolutions[res_idx] if (res_idx >= 0 and res_idx < _resolutions.size()) else Vector2i(1920, 1080)
	var selected_vsync = vsync_check.button_pressed
	
	var selected_fps = 0
	match fps_option.get_selected_id():
		1: selected_fps = 60
		2: selected_fps = 120
		3: selected_fps = 144
		_: selected_fps = 0

	SettingsManager.apply_display_settings(selected_mode_id, selected_res, selected_vsync, selected_fps)
	
	# Visual confirmation
	apply_button.text = "Saved & Applied!"
	var tree = get_tree()
	if tree:
		await tree.create_timer(1.2).timeout
	if is_instance_valid(apply_button):
		apply_button.text = "Apply"
