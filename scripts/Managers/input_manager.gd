# ==============================================================================
# Script: Managers/input_manager.gd
# Purpose: Unified input controller that handles keyboard hotkeys, menu gatekeeping, continuous WASD camera movements, drag-and-drop building blueprint placements, mouse hover tracking, and state-machine selection routing.
# Dependencies: Requires standard Godot Node2D parent and level tracking nodes, and coordinates with GameState and Camera.
# Signals:
#   - object_selected: Emitted when the selected target bot, building, or enemy changes.
# ==============================================================================
extends Node2D
class_name InputController

# REFERENCES (Filled by the Level on load)
var level_ref: Node2D
var building_manager: Node2D
var wave_manager: Node2D
var management_menu: Control
var stat_menu: Control
var hover_popup: Control

# STATE & TRACKERS
enum InteractionMode { NONE, PLACE_BUILDING, DECONSTRUCT, UPGRADE, TERRAFORM, SET_HOME }
var current_mode: InteractionMode = InteractionMode.NONE

var hovered_bot: WorkerBot = null
var hovered_building: Building = null
var hovered_enemy: Node2D = null
var bot_awaiting_home: Node2D = null

var last_hovered_upgrade_tile: Vector2i = Vector2i(-1, -1)
var last_terrain_tile: Vector2i = Vector2i(-1, -1)
var is_terrain_remove_brush: bool = false

# Signals
signal object_selected(target: Node2D)



## Adds this node to global input manager group during ready initialization.
func _ready():
	add_to_group("InputManager")



## Processes discrete key strokes for menus, overlays, and developer skip tools.
func _unhandled_key_input(event: InputEvent):
	if not event.is_pressed() or event.is_echo(): return

	# GLOBAL UI HOTKEYS (Allowed even if a menu is open!)
	match event.keycode:
		KEY_P:
			if management_menu: management_menu.toggle_menu()
			get_viewport().set_input_as_handled()
			return
		KEY_L:
			if stat_menu: stat_menu.toggle_menu()
			get_viewport().set_input_as_handled()
			return

	# THE GATEKEEPER: Menu Routing
	if GameState.is_menu_open:
		# Universal Close Menu button
		if event.is_action_pressed("ui_cancel"):
			GameState.close_menu()
			get_viewport().set_input_as_handled()
			return
			
		if GameState.current_menu == GameState.MenuType.RESEARCH:
			if event.keycode == KEY_R: 
				print("Special Research Hotkey Pressed!")
				get_viewport().set_input_as_handled()
				return
				
		get_viewport().set_input_as_handled()
		return

	# WORLD ACTIONS (Only run if NO menus are open)
	match event.keycode:
		KEY_T:
			_cancel_current_action()
			current_mode = InteractionMode.NONE if current_mode == InteractionMode.TERRAFORM else InteractionMode.TERRAFORM
			get_viewport().set_input_as_handled()
			
		KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_EQUAL, KEY_MINUS, KEY_N:
			if building_manager:
				building_manager.handle_overlay_hotkeys(event.keycode)
			get_viewport().set_input_as_handled()
	
	# DEBUG TOOLS
	match event.keycode:
		KEY_F8:
			if level_ref and level_ref.has_node("TimeManager"):
				print("DEBUG: Force Skipping to Sunset...")
				level_ref.get_node("TimeManager").debug_skip_to_night()
			get_viewport().set_input_as_handled()
			
		KEY_F9:
			if level_ref and level_ref.has_node("TimeManager"):
				print("DEBUG: Force Skipping to Sunrise...")
				level_ref.get_node("TimeManager").debug_skip_to_next_morning()
			get_viewport().set_input_as_handled()



## Handles continuous key inputs such as keyboard-based camera panning.
func _process(delta):
	# Gatekeeper: Don't allow camera panning if a menu is open!
	if GameState.is_menu_open: return
	
	var move_dir := Vector2.ZERO
	
	if Input.is_key_pressed(KEY_D):
		move_dir.x += 1
	if Input.is_key_pressed(KEY_A):
		move_dir.x -= 1
	if Input.is_key_pressed(KEY_S):
		move_dir.y += 1
	if  Input.is_key_pressed(KEY_W):
		move_dir.y -= 1
		
	if move_dir != Vector2.ZERO:
		var cam = get_tree().get_first_node_in_group("Camera")
		if cam and cam.has_method("apply_pan"):
			cam.apply_pan(move_dir, delta)



## Maps mouse clicks and drags to their matching interaction modes.
func _unhandled_input(event: InputEvent):
	if not level_ref or not building_manager: return
	
	# THE GATEKEEPER: Block World Clicks
	if GameState.is_menu_open and current_mode != InteractionMode.SET_HOME:
		if event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return

	# CAMERA ZOOM
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var cam = get_tree().get_first_node_in_group("Camera")
			if cam: cam.apply_zoom(event.position, 1 + cam.zoom_speed)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var cam = get_tree().get_first_node_in_group("Camera")
			if cam: cam.apply_zoom(event.position, 1 - cam.zoom_speed)
			get_viewport().set_input_as_handled()
			return

	# NORMAL WORLD CLICKS 
	var mouse_pos = get_global_mouse_position()
	var grid_pos = level_ref.terrain_layer.local_to_map(mouse_pos)

	# GLOBAL CANCEL & HOTKEYS
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

	# --- 5. STATE MACHINE ROUTING ---
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
			
		InteractionMode.SET_HOME:
			if _is_left_clicking(event):
				if is_instance_valid(bot_awaiting_home):
					if bot_awaiting_home.has_method("is_valid_home_tile"):
						if not bot_awaiting_home.is_valid_home_tile(grid_pos):
							get_viewport().set_input_as_handled()
							return
							
					bot_awaiting_home.set_home(grid_pos)
					if bot_awaiting_home.has_method("toggle_set_home_mode"):
						bot_awaiting_home.toggle_set_home_mode(false)
						
				bot_awaiting_home = null
				current_mode = InteractionMode.NONE
				get_viewport().set_input_as_handled()
		
		InteractionMode.NONE:
			if event.is_action_pressed("ui_left"):
				_handle_default_selection(grid_pos)



## Cancels active interaction states, clearing highlight variables and deactivating placement ghosts.
func _cancel_current_action():
	object_selected.emit(null)
		
	if current_mode == InteractionMode.SET_HOME and is_instance_valid(bot_awaiting_home):
		if bot_awaiting_home.has_method("toggle_set_home_mode"):
			bot_awaiting_home.toggle_set_home_mode(false)
		bot_awaiting_home = null
	
	building_manager.cancel_placement()
	current_mode = InteractionMode.NONE
	last_hovered_upgrade_tile = Vector2i(-1, -1)
	last_terrain_tile = Vector2i(-1, -1)


## Helper utility checks if left mouse click is down.
func _is_left_clicking(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed


## Helper utility checks if left mouse click is held while cursor is in motion.
func _is_left_dragging(event: InputEvent) -> bool:
	return event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)



## Selects hovered bots, structures, or enemies when in default selection mode.
func _handle_default_selection(grid_pos: Vector2i):
	# Did we click a bot?
	if is_instance_valid(hovered_bot):
		object_selected.emit(hovered_bot)
		get_viewport().set_input_as_handled()
		return
		
	# Did we click an Enemy?
	if is_instance_valid(hovered_enemy):
		object_selected.emit(hovered_enemy)
		get_viewport().set_input_as_handled()
		return
	
	# Did we click a building's Area2D?
	if is_instance_valid(hovered_building):
		object_selected.emit(hovered_building)
		get_viewport().set_input_as_handled()
		return

	# We clicked empty terrain or grid!
	object_selected.emit(null)



## Routes clicks and mouse drag brushes to assign or remove terrain terraforming jobs.
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



## Caches references and activates detail tooltips when cursors hover over valid objects.
func _on_object_hovered(object: Node2D):
	if object.has_method("set_priority"): # Duck-typing for WorkerBot
		hovered_bot = object
	elif object is Building:
		hovered_building = object
	elif object is Enemy:
		hovered_enemy = object

	if hover_popup and hover_popup.has_method("show_building_info"):
		hover_popup.show_building_info(object)


## Clears tracking variables and dismisses active tooltips when cursors unhover.
func _on_object_unhovered(object: Node2D):
	if hovered_bot == object: hovered_bot = null
	if hovered_enemy == object: hovered_enemy = null
	
	if hovered_building == object: 
		hovered_building = null
		var renderer = get_tree().get_first_node_in_group("OverlayRenderer")
		if renderer: renderer.queue_redraw()

	if hover_popup and "current_building" in hover_popup:
		if hover_popup.current_building == object:
			hover_popup.hide()
