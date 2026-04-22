extends Node2D
class_name InputController

# ==========================================
# REFERENCES (Filled by the Level on load)
# ==========================================
var level_ref: Node2D
var building_manager: Node2D
var wave_manager: Node2D
var management_menu: Control
var stat_menu: Control

# ==========================================
# STATE & TRACKERS
# ==========================================
enum InteractionMode { NONE, PLACE_BUILDING, DECONSTRUCT, UPGRADE, TERRAFORM }
var current_mode: InteractionMode = InteractionMode.NONE

var hovered_bot: WorkerBot = null
var hovered_building: Building = null

var last_hovered_upgrade_tile: Vector2i = Vector2i(-1, -1)
var last_terrain_tile: Vector2i = Vector2i(-1, -1)
var is_terrain_remove_brush: bool = false


func _ready():
	add_to_group("InputManager")

# ==========================================
# KEYBOARD INPUT (Menus & Mode Toggles)
# ==========================================
func _unhandled_key_input(event: InputEvent):
	if not event.is_pressed() or event.is_echo(): return

	match event.keycode:
		KEY_T:
			_cancel_current_action()
			current_mode = InteractionMode.NONE if current_mode == InteractionMode.TERRAFORM else InteractionMode.TERRAFORM
			get_viewport().set_input_as_handled()
		KEY_P:
			if management_menu: management_menu.toggle_menu()
			get_viewport().set_input_as_handled()
		KEY_L:
			if stat_menu: stat_menu.toggle_menu()
			get_viewport().set_input_as_handled()
		KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_EQUAL, KEY_MINUS:
			if building_manager:
				building_manager.handle_overlay_hotkeys(event.keycode)
			get_viewport().set_input_as_handled()

# ==========================================
# MOUSE INPUT (The State Machine)
# ==========================================
func _unhandled_input(event: InputEvent):
	if not level_ref or not building_manager: return
	
	var mouse_pos = get_global_mouse_position()
	var grid_pos = level_ref.terrain_layer.local_to_map(mouse_pos)

	# --- 1. GLOBAL CANCEL & HOTKEYS ---
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
		_cancel_current_action()
		return

	if event.is_action_pressed("rotate_tile") and current_mode == InteractionMode.PLACE_BUILDING:
		building_manager.rotate_ghost()
		return

	if event.is_action_pressed("deconstruct_hotkey"):
		_cancel_current_action()
		current_mode = InteractionMode.DECONSTRUCT
		return

	if event.is_action_pressed("upgrade_hotkey"):
		_cancel_current_action()
		current_mode = InteractionMode.NONE if current_mode == InteractionMode.UPGRADE else InteractionMode.UPGRADE
		return

	# --- 2. STATE MACHINE ROUTING ---
	match current_mode:
		InteractionMode.PLACE_BUILDING:
			if event is InputEventMouse:
				if building_manager.handle_input(event, grid_pos):
					current_mode = InteractionMode.NONE

		InteractionMode.DECONSTRUCT:
			if _is_left_clicking(event) or _is_left_dragging(event):
				building_manager.deconstruct_building_at(grid_pos)

		InteractionMode.UPGRADE:
			if _is_left_clicking(event) or _is_left_dragging(event):
				if building_manager.upgrade_building_at(grid_pos):
					last_hovered_upgrade_tile = Vector2i(-1, -1)

		InteractionMode.TERRAFORM:
			_handle_terraform_input(event, grid_pos)

		InteractionMode.NONE:
			if event.is_action_pressed("ui_left"):
				_handle_default_selection(grid_pos)

# ==========================================
# ACTION HELPERS
# ==========================================
func _cancel_current_action():
	building_manager.cancel_placement()
	current_mode = InteractionMode.NONE
	last_hovered_upgrade_tile = Vector2i(-1, -1)
	last_terrain_tile = Vector2i(-1, -1)

func _is_left_clicking(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed

func _is_left_dragging(event: InputEvent) -> bool:
	return event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

# ==========================================
# SPECIFIC MODE LOGIC
# ==========================================
func _handle_default_selection(grid_pos: Vector2i):
	# 1. Did we click a bot?
	if is_instance_valid(hovered_bot):
		# Pass it directly to your existing function!
		if building_manager and building_manager.has_method("_on_bot_clicked"):
			building_manager._on_bot_clicked(hovered_bot)
			
		get_viewport().set_input_as_handled()
		return

	# 2. Did we click a building's Area2D?
	if is_instance_valid(hovered_building):
		# We already have the exact building node, so we can just emit the signal directly!
		if building_manager:
			building_manager.building_selected.emit(hovered_building)
			
		get_viewport().set_input_as_handled()
		return

	# 3. We clicked empty terrain or grid!
	if building_manager:
		building_manager.building_selected.emit(null)
		
	if wave_manager:
		wave_manager.deselect_enemy()
func _handle_terraform_input(event: InputEvent, grid_pos: Vector2i):
	if _is_left_clicking(event):
		last_terrain_tile = grid_pos
		var tile_occupied = building_manager.occupied_tiles.has(grid_pos)
		
		if tile_occupied and building_manager.occupied_tiles[grid_pos] is TerraformSite:
			is_terrain_remove_brush = true
			building_manager.deconstruct_building_at(grid_pos)
		else:
			is_terrain_remove_brush = false
			building_manager._try_add_terrain_job(grid_pos)
			
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		last_terrain_tile = Vector2i(-1, -1)
		
	elif _is_left_dragging(event):
		if grid_pos != last_terrain_tile:
			last_terrain_tile = grid_pos
			if is_terrain_remove_brush:
				if building_manager.occupied_tiles.has(grid_pos) and building_manager.occupied_tiles[grid_pos] is TerraformSite:
					building_manager.deconstruct_building_at(grid_pos)
			else:
				building_manager._try_add_terrain_job(grid_pos)
