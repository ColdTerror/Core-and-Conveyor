# ==============================================================================
# Script: UI/map_preview_panel.gd
# Purpose: Pre-settlement Map Survey overlay inspired by Factorio. Allows players
#          to scout terrain, toggle between Map Types (River Divide, Mainland, Lakes)
#          and Biomes (Forest, Desert, Alpine), generate fresh seeds, and settle
#          by placing their initial Core.
# Dependencies: Requires Level and BuildingManager references.
# Signals: None.
# ==============================================================================
class_name MapPreviewPanel
extends PanelContainer

var level_ref: Level
var is_collapsed: bool = false

# UI Components
var root_vbox: VBoxContainer
var header_container: HBoxContainer
var body_container: VBoxContainer
var title_label: Label
var center_btn: Button
var collapse_btn: Button
var status_label: Label

var map_type_group: ButtonGroup
var biome_group: ButtonGroup

var map_type_buttons: Dictionary = {} # Level.MapGenType -> Button
var biome_buttons: Dictionary = {}    # Level.MapBiome -> Button

var reroll_btn: Button
var place_core_btn: Button

# Styles
var btn_normal_style: StyleBoxFlat
var btn_pressed_style: StyleBoxFlat
var btn_hover_style: StyleBoxFlat


func _init() -> void:
	_init_styles()
	_build_ui()


## Pre-builds reusable styleboxes for consistent panel and toggle button theming.
func _init_styles() -> void:
	# Panel background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.13, 0.94)
	panel_style.border_color = Color(0.28, 0.38, 0.52, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 14
	panel_style.content_margin_right = 14
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", panel_style)

	# Toggle Normal Style
	btn_normal_style = StyleBoxFlat.new()
	btn_normal_style.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	btn_normal_style.border_color = Color(0.24, 0.28, 0.36, 0.6)
	btn_normal_style.set_border_width_all(1)
	btn_normal_style.set_corner_radius_all(5)
	btn_normal_style.content_margin_left = 8
	btn_normal_style.content_margin_right = 8
	btn_normal_style.content_margin_top = 5
	btn_normal_style.content_margin_bottom = 5

	# Toggle Hover Style
	btn_hover_style = StyleBoxFlat.new()
	btn_hover_style.bg_color = Color(0.18, 0.22, 0.28, 0.95)
	btn_hover_style.border_color = Color(0.38, 0.5, 0.68, 0.85)
	btn_hover_style.set_border_width_all(1)
	btn_hover_style.set_corner_radius_all(5)
	btn_hover_style.content_margin_left = 8
	btn_hover_style.content_margin_right = 8
	btn_hover_style.content_margin_top = 5
	btn_hover_style.content_margin_bottom = 5

	# Toggle Pressed (Active) Style - Vibrant Emerald Accent
	btn_pressed_style = StyleBoxFlat.new()
	btn_pressed_style.bg_color = Color(0.12, 0.26, 0.20, 0.95)
	btn_pressed_style.border_color = Color(0.3, 0.85, 0.5, 0.95)
	btn_pressed_style.set_border_width_all(2)
	btn_pressed_style.set_corner_radius_all(5)
	btn_pressed_style.content_margin_left = 8
	btn_pressed_style.content_margin_right = 8
	btn_pressed_style.content_margin_top = 5
	btn_pressed_style.content_margin_bottom = 5


## Constructs the node hierarchy for the Map Survey overlay.
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_left = -225
	offset_right = 225
	offset_top = 46
	mouse_filter = Control.MOUSE_FILTER_STOP

	root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	# --- HEADER ROW ---
	header_container = HBoxContainer.new()
	header_container.add_theme_constant_override("separation", 6)
	root_vbox.add_child(header_container)

	title_label = Label.new()
	title_label.text = "🗺️  MAP SURVEY"
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	header_container.add_child(title_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(spacer)

	center_btn = Button.new()
	center_btn.text = "🎯 Center"
	center_btn.tooltip_text = "Center camera on map"
	center_btn.focus_mode = Control.FOCUS_NONE
	center_btn.add_theme_font_size_override("font_size", 11)
	center_btn.pressed.connect(_on_center_camera_pressed)
	header_container.add_child(center_btn)

	collapse_btn = Button.new()
	collapse_btn.text = "▲"
	collapse_btn.tooltip_text = "Collapse / Expand Map Survey panel"
	collapse_btn.focus_mode = Control.FOCUS_NONE
	collapse_btn.custom_minimum_size = Vector2(24, 24)
	collapse_btn.add_theme_font_size_override("font_size", 11)
	collapse_btn.pressed.connect(_on_toggle_collapse)
	header_container.add_child(collapse_btn)

	# --- COLLAPSIBLE BODY ---
	body_container = VBoxContainer.new()
	body_container.add_theme_constant_override("separation", 8)
	root_vbox.add_child(body_container)

	# Subtitle / Hint
	var hint_label = Label.new()
	hint_label.text = "WASD to Pan  •  Mouse Wheel to Zoom\nSelect settings & reroll, or place Core to settle."
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82))
	body_container.add_child(hint_label)

	var sep1 = HSeparator.new()
	sep1.add_theme_color_override("separator_color", Color(0.25, 0.32, 0.42, 0.6))
	body_container.add_child(sep1)

	# --- MAP TYPE TOGGLES ---
	var map_type_label = Label.new()
	map_type_label.text = "Map Type:"
	map_type_label.add_theme_font_size_override("font_size", 12)
	map_type_label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	body_container.add_child(map_type_label)

	map_type_group = ButtonGroup.new()
	map_type_group.allow_unpress = false

	var map_type_row = HBoxContainer.new()
	map_type_row.add_theme_constant_override("separation", 6)
	body_container.add_child(map_type_row)

	var btn_river = _create_toggle_btn("River Divide", map_type_group)
	btn_river.pressed.connect(_on_map_type_pressed.bind(Level.MapGenType.RIVER_DIVIDE))
	map_type_row.add_child(btn_river)
	map_type_buttons[Level.MapGenType.RIVER_DIVIDE] = btn_river

	var btn_mainland = _create_toggle_btn("Mainland", map_type_group)
	btn_mainland.pressed.connect(_on_map_type_pressed.bind(Level.MapGenType.MAINLAND))
	map_type_row.add_child(btn_mainland)
	map_type_buttons[Level.MapGenType.MAINLAND] = btn_mainland

	var btn_lakes = _create_toggle_btn("Lakes", map_type_group)
	btn_lakes.pressed.connect(_on_map_type_pressed.bind(Level.MapGenType.LAKES))
	map_type_row.add_child(btn_lakes)
	map_type_buttons[Level.MapGenType.LAKES] = btn_lakes

	# --- BIOME TOGGLES ---
	var biome_label = Label.new()
	biome_label.text = "Biome:"
	biome_label.add_theme_font_size_override("font_size", 12)
	biome_label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	body_container.add_child(biome_label)

	biome_group = ButtonGroup.new()
	biome_group.allow_unpress = false

	var biome_row = HBoxContainer.new()
	biome_row.add_theme_constant_override("separation", 6)
	body_container.add_child(biome_row)

	var btn_forest = _create_toggle_btn("🌲 Forest", biome_group)
	btn_forest.pressed.connect(_on_biome_pressed.bind(Level.MapBiome.FOREST))
	biome_row.add_child(btn_forest)
	biome_buttons[Level.MapBiome.FOREST] = btn_forest

	var btn_desert = _create_toggle_btn("🏜️ Desert", biome_group)
	btn_desert.pressed.connect(_on_biome_pressed.bind(Level.MapBiome.DESERT))
	biome_row.add_child(btn_desert)
	biome_buttons[Level.MapBiome.DESERT] = btn_desert

	var btn_alpine = _create_toggle_btn("🏔️ Alpine", biome_group)
	btn_alpine.pressed.connect(_on_biome_pressed.bind(Level.MapBiome.ALPINE))
	biome_row.add_child(btn_alpine)
	biome_buttons[Level.MapBiome.ALPINE] = btn_alpine

	var sep2 = HSeparator.new()
	sep2.add_theme_color_override("separator_color", Color(0.25, 0.32, 0.42, 0.6))
	body_container.add_child(sep2)

	# --- ACTION BUTTONS ---
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	body_container.add_child(action_row)

	reroll_btn = Button.new()
	reroll_btn.text = "🎲  Generate New Map"
	reroll_btn.tooltip_text = "Reroll procedural terrain seed with selected settings"
	reroll_btn.focus_mode = Control.FOCUS_NONE
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_btn.custom_minimum_size.y = 36
	reroll_btn.add_theme_font_size_override("font_size", 13)
	_apply_action_button_style(reroll_btn, Color(0.16, 0.28, 0.42, 0.95), Color(0.35, 0.65, 0.95, 0.9))
	reroll_btn.pressed.connect(_on_generate_pressed)
	action_row.add_child(reroll_btn)

	place_core_btn = Button.new()
	place_core_btn.text = "🚩  Place Core"
	place_core_btn.tooltip_text = "Select Core to place and start the colony"
	place_core_btn.focus_mode = Control.FOCUS_NONE
	reroll_btn.custom_minimum_size.y = 36
	place_core_btn.add_theme_font_size_override("font_size", 13)
	_apply_action_button_style(place_core_btn, Color(0.32, 0.24, 0.12, 0.95), Color(0.95, 0.75, 0.3, 0.9))
	place_core_btn.pressed.connect(_on_place_core_pressed)
	action_row.add_child(place_core_btn)

	# --- STATUS FOOTER ---
	status_label = Label.new()
	status_label.text = "Ready to survey"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.7))
	body_container.add_child(status_label)


## Creates a styled toggle button for segmented option groups.
func _create_toggle_btn(label_text: String, group: ButtonGroup) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.toggle_mode = true
	btn.button_group = group
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_stylebox_override("normal", btn_normal_style)
	btn.add_theme_stylebox_override("hover", btn_hover_style)
	btn.add_theme_stylebox_override("pressed", btn_pressed_style)
	btn.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	btn.add_theme_color_override("font_pressed_color", Color(0.4, 1.0, 0.65))
	btn.add_theme_color_override("font_hover_color", Color(0.95, 0.98, 1.0))
	return btn


## Applies custom background and border styles to primary action buttons.
func _apply_action_button_style(btn: Button, bg: Color, border: Color) -> void:
	var norm = StyleBoxFlat.new()
	norm.bg_color = bg
	norm.border_color = border
	norm.set_border_width_all(1)
	norm.set_corner_radius_all(6)
	norm.content_margin_left = 10
	norm.content_margin_right = 10
	norm.content_margin_top = 6
	norm.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", norm)

	var hov = StyleBoxFlat.new()
	hov.bg_color = bg.lightened(0.15)
	hov.border_color = border.lightened(0.2)
	hov.set_border_width_all(1)
	hov.set_corner_radius_all(6)
	hov.content_margin_left = 10
	hov.content_margin_right = 10
	hov.content_margin_top = 6
	hov.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", hov)


## Connects Level and BuildingManager signals and initializes toggle button states.
func setup(level: Level) -> void:
	level_ref = level
	
	if level_ref and level_ref.building_manager:
		level_ref.building_manager.core_placed_event.connect(_on_core_placed)
		
	_sync_toggles_with_level()
	_update_status_label()


## Synchronizes the toggle button pressed states with the Level's active map settings.
func _sync_toggles_with_level() -> void:
	if not is_instance_valid(level_ref): return
	
	if map_type_buttons.has(level_ref.current_map_type):
		map_type_buttons[level_ref.current_map_type].button_pressed = true
		
	if biome_buttons.has(level_ref.current_biome):
		biome_buttons[level_ref.current_biome].button_pressed = true


## Updates the footer status description reflecting active survey parameters.
func _update_status_label() -> void:
	if not is_instance_valid(level_ref): return
	var type_name = Level.MapGenType.keys()[level_ref.current_map_type].capitalize().replace("_", " ")
	var biome_name = Level.MapBiome.keys()[level_ref.current_biome].capitalize()
	status_label.text = "%s  •  %s  (Place Core to begin)" % [type_name, biome_name]


## Toggles panel collapse to provide an unobstructed map survey view.
func _on_toggle_collapse() -> void:
	is_collapsed = not is_collapsed
	body_container.visible = not is_collapsed
	collapse_btn.text = "▼" if is_collapsed else "▲"


## Centers the camera onto the map's center coordinates (2400, 2400).
func _on_center_camera_pressed() -> void:
	var cam = get_viewport().get_camera_2d()
	if cam:
		cam.position = Vector2(Level.MAP_WIDTH * 16, Level.MAP_HEIGHT * 16)
		if cam.has_method("clamp_camera_to_bounds"):
			cam.clamp_camera_to_bounds()


## Handles Map Type toggle activation.
func _on_map_type_pressed(map_type: Level.MapGenType) -> void:
	if not is_instance_valid(level_ref): return
	if level_ref.current_map_type == map_type:
		return
	level_ref.reroll_map(map_type, level_ref.current_biome)
	_update_status_label()


## Handles Biome toggle activation.
func _on_biome_pressed(biome: Level.MapBiome) -> void:
	if not is_instance_valid(level_ref): return
	if level_ref.current_biome == biome:
		return
	level_ref.reroll_map(level_ref.current_map_type, biome)
	_update_status_label()


## Rerolls procedural generation with the currently selected settings.
func _on_generate_pressed() -> void:
	if not is_instance_valid(level_ref): return
	var active_type = _get_selected_map_type()
	var active_biome = _get_selected_biome()
	level_ref.reroll_map(active_type, active_biome)
	_update_status_label()


## Returns the active map type from the toggle button group.
func _get_selected_map_type() -> Level.MapGenType:
	for type in map_type_buttons:
		if map_type_buttons[type].button_pressed:
			return type
	return level_ref.current_map_type if is_instance_valid(level_ref) else Level.MapGenType.RIVER_DIVIDE


## Returns the active biome from the toggle button group.
func _get_selected_biome() -> Level.MapBiome:
	for biome in biome_buttons:
		if biome_buttons[biome].button_pressed:
			return biome
	return level_ref.current_biome if is_instance_valid(level_ref) else Level.MapBiome.FOREST


## Triggers Core blueprint placement for immediate settlement.
func _on_place_core_pressed() -> void:
	if not is_instance_valid(level_ref): return
	if level_ref.core_scene:
		level_ref._on_hotbar_item_selected(level_ref.core_scene, true)


## Responds to Core placement by gracefully fading out and removing this survey overlay.
func _on_core_placed() -> void:
	dismiss()


## Smoothly fades out and frees the survey overlay.
func dismiss() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in find_children("*", "Control"):
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)
