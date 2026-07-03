# ==============================================================================
# Script: UI/keybind_settings_menu.gd
# Purpose: Handles event mapping and dynamic row population for the key rebinding GUI.
#          Interacts with InputManager autoload to load, save, and update the InputMap.
# ==============================================================================
extends CanvasLayer
signal closed

@onready var scroll_container = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/ScrollList
@onready var reset_btn = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Reset
@onready var close_btn = $RootControl/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/Close

var binding_action: String = ""
var binding_button: Button = null

func _ready():
	process_mode = PROCESS_MODE_ALWAYS
	
	reset_btn.pressed.connect(_on_reset_pressed)
	close_btn.pressed.connect(func():
		closed.emit()
	)
	
	_populate_list()


func _populate_list():
	for child in scroll_container.get_children():
		child.queue_free()
		
	# Retrieve mapping registry from InputManager autoload
	var actions = InputManager.get("KEYBIND_ACTIONS")
	if not actions: return
	
	for action in actions:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		
		var lbl = Label.new()
		lbl.text = actions[action]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(lbl)
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(180, 36)
		btn.add_theme_font_size_override("font_size", 14)
		btn.text = _get_action_key_text(action)
		btn.pressed.connect(_on_bind_button_pressed.bind(action, btn))
		row.add_child(btn)
		
		scroll_container.add_child(row)


func _get_action_key_text(action: String) -> String:
	var events = InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
	return "[ Unbound ]"


func _on_bind_button_pressed(action: String, btn: Button):
	if binding_action != "":
		binding_button.text = _get_action_key_text(binding_action)
		
	binding_action = action
	binding_button = btn
	btn.text = "Press any key..."


func _input(event: InputEvent):
	if binding_action == "": return
	
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
		
		var new_key = event.physical_keycode
		_rebind_action(binding_action, new_key)
		
		binding_button.text = OS.get_keycode_string(new_key)
		binding_action = ""
		binding_button = null


func _rebind_action(action: String, physical_keycode: int):
	InputMap.action_erase_events(action)
	var ev = InputEventKey.new()
	ev.physical_keycode = physical_keycode
	InputMap.action_add_event(action, ev)
	
	# Trigger save on InputManager
	if InputManager.has_method("save_keybinds"):
		InputManager.save_keybinds()


func _on_reset_pressed():
	if InputManager.has_method("initialize_default_actions"):
		InputManager.initialize_default_actions(true)
	if InputManager.has_method("save_keybinds"):
		InputManager.save_keybinds()
	_populate_list()
