# ==============================================================================
# Script: UI/keybind_settings_menu.gd
# Purpose: Handles programmatic construction and event mapping for the key rebinding GUI.
#          Interacts with InputManager autoload to load, save, and update the InputMap.
# ==============================================================================
extends CanvasLayer
signal closed

var scroll_container: VBoxContainer
var reset_btn: Button
var close_btn: Button

var binding_action: String = ""
var binding_button: Button = null

func _ready():
	process_mode = PROCESS_MODE_ALWAYS
	
	# Wrap everything in a full screen Control inside the CanvasLayer
	var root_control = Control.new()
	root_control.anchors_preset = Control.PRESET_FULL_RECT
	root_control.layout_mode = 1
	root_control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root_control.grow_vertical = Control.GROW_DIRECTION_BOTH
	root_control.size = get_viewport().get_visible_rect().size
	add_child(root_control)
	
	# Dark background dimming
	var bg_dim = ColorRect.new()
	bg_dim.color = Color(0, 0, 0, 0.7)
	bg_dim.anchors_preset = Control.PRESET_FULL_RECT
	bg_dim.layout_mode = 1
	bg_dim.size = root_control.size
	root_control.add_child(bg_dim)
	
	# CenterContainer to perfectly position the panel
	var center = CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.layout_mode = 1
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.size = root_control.size
	root_control.add_child(center)
	
	# Panel Container inside CenterContainer
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(550, 650)
	center.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "Keyboard Controls"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# Scroll area for rows
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	scroll_container = VBoxContainer.new()
	scroll_container.add_theme_constant_override("separation", 10)
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_container)
	
	var separator = ColorRect.new()
	separator.color = Color(0.25, 0.25, 0.25, 1.0)
	separator.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(separator)
	
	# Action buttons HBox
	var hbox_btns = HBoxContainer.new()
	hbox_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_btns.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox_btns)
	
	reset_btn = Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(180, 42)
	reset_btn.pressed.connect(_on_reset_pressed)
	hbox_btns.add_child(reset_btn)
	
	close_btn = Button.new()
	close_btn.text = "Back / Save"
	close_btn.custom_minimum_size = Vector2(180, 42)
	close_btn.pressed.connect(func():
		closed.emit()
	)
	hbox_btns.add_child(close_btn)
	
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
