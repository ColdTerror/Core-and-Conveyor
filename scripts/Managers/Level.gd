# Level.gd 
extends Node2D

# ==========================================
# NODES & REFERENCES
# ==========================================
@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var object_layer: TileMapLayer = $ObjectLayer

@onready var hover_menu := $CanvasLayer/Popup_Layer/HoverMenu
@onready var hotbar = $CanvasLayer/Hud_Layer/HotBar_UI
@onready var detail_menu = $CanvasLayer/Popup_Layer/DetailMenu 
@onready var management_menu = $CanvasLayer/Popup_Layer/ManagementMenu
@onready var stat_menu = $CanvasLayer/Popup_Layer/StatisticsMenu

@onready var building_manager: BuildingManager = $BuildingManager
@onready var pathfinder = $Pathfinder

# ==========================================
# ENUMS & CONSTANTS
# ==========================================
enum InteractionMode { NONE, PLACE_BUILDING, DECONSTRUCT, UPGRADE, TERRAFORM }
enum MapGenType { RIVER_DIVIDE, MAINLAND, LAKES }

const ATLAS_COLUMNS := 3
const TILE_COUNT := 10
const MAP_WIDTH := 200
const MAP_HEIGHT := 200

# Terrain indices based on your library
const TERRAIN_GRASS := 0
const TERRAIN_WATER := 1
const TERRAIN_SAND := 2
const RES_TREE := 3
const RES_STONE := 4

# ==========================================
# EXPORTS & CONFIGURATION
# ==========================================
@export var current_map_type: MapGenType = MapGenType.RIVER_DIVIDE
@export var tile_size_px: Vector2 = Vector2(32, 32)
@export var tile_library: Array[TileDataResource] = []

@export_group("Scenes")
@export var item_scene: PackedScene 
@export var stockpile_scene: PackedScene 
@export var lumberjack_scene: PackedScene
@export var sawmill_scene: PackedScene
@export var bow_tower_scene: PackedScene
@export var wall_scene: PackedScene
@export var gate_scene: PackedScene
@export var conveyor_scene: PackedScene 
@export var router_scene: PackedScene 
@export var filter_scene: PackedScene
@export var core_scene: PackedScene 
@export var mine_scene: PackedScene
@export var stonemason_scene: PackedScene
@export var fletcher_scene: PackedScene
@export var projectile_scene: PackedScene

# ==========================================
# RUNTIME STATE
# ==========================================
var current_mode = InteractionMode.NONE
var active_grid_objects := {}

# Tool Trackers
var last_hovered_upgrade_tile := Vector2i(-1, -1)
var is_terrain_remove_brush: bool = false
var last_terrain_tile := Vector2i(-1, -1)

# ==========================================
# SETUP & MAIN LOOP
# ==========================================

func _ready():
	
		
	hover_menu.hide()
	
	# Connect the resource signals
	ResourceManager.resource_state_changed.connect(_on_resource_state_changed)
	ResourceManager.resource_destroyed.connect(_on_resource_destroyed)
	
	#Setup pause menu signal
	var pause_menu = $CanvasLayer/PauseMenu 
	pause_menu.save_requested.connect(_on_pause_menu_save_requested)
	
	# Give the manager a reference to this Level node
	building_manager.initialize(self)

	# Connect Hotbar Signal
	if hotbar:
		hotbar.item_selected.connect(_on_hotbar_item_selected)
		_setup_hotbar_items()
		
	building_manager.building_selected.connect(detail_menu.open_menu)
	building_manager.core_placed_event.connect(_on_core_placed)
	
	if not SaveManager.pending_load_data.is_empty():
		SaveManager.unpack_save(self)
	else:
		generate_simple_map()
		
	var map_rect = Rect2i(0, 0, MAP_HEIGHT, MAP_WIDTH)
	pathfinder.setup(terrain_layer, object_layer, map_rect)
	building_manager.pathfinder = pathfinder
	
	

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)
	
	# --- UPGRADE HOVER UI ---
	if current_mode == InteractionMode.UPGRADE:
		# Only update the UI if the mouse moved to a NEW tile
		if grid_pos != last_hovered_upgrade_tile:
			last_hovered_upgrade_tile = grid_pos
			building_manager.show_upgrade_preview(grid_pos)
	else:
		# If we cancel Upgrade Mode, hide the UI immediately
		if last_hovered_upgrade_tile != Vector2i(-1, -1):
			last_hovered_upgrade_tile = Vector2i(-1, -1)
			building_manager.placement_ended.emit() 

# ==========================================
# STATE MACHINE: INPUT HANDLING
# ==========================================

func _unhandled_input(event):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)

	# ---------------------------------------------------------
	# 1. HOTKEYS & MODE SWITCHING
	# ---------------------------------------------------------
	if event.is_action_pressed("rotate_tile"):
		if current_mode == InteractionMode.PLACE_BUILDING:
			building_manager.rotate_ghost()
		return
	
	if event.is_action_pressed("deconstruct_hotkey"): 
		building_manager.cancel_placement()
		current_mode = InteractionMode.DECONSTRUCT
		print("Entered Deconstruct Mode")
		
	if event.is_action_pressed("upgrade_hotkey"): 
		building_manager.cancel_placement()
		if current_mode == InteractionMode.UPGRADE:
			current_mode = InteractionMode.NONE
			print("Exited Upgrade Mode")
		else:
			current_mode = InteractionMode.UPGRADE
			print("Entered Upgrade Mode")
		
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_T:
			building_manager.cancel_placement()
			if current_mode == InteractionMode.TERRAFORM:
				current_mode = InteractionMode.NONE
				print("Exited Terrain Mode")
			else:
				current_mode = InteractionMode.TERRAFORM
				print("Entered Terrain Mode")
				
		if event.keycode == KEY_P:
			management_menu.toggle_menu()
			get_viewport().set_input_as_handled()
		if event.keycode == KEY_L:
			stat_menu.toggle_menu()
			get_viewport().set_input_as_handled()
	# ---------------------------------------------------------
	# 2. BUILDING MODE (Delegated to Manager)
	# ---------------------------------------------------------
	if current_mode == InteractionMode.PLACE_BUILDING:
		
		#Catch the cancel placement before sending it to building manager
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
			building_manager.cancel_placement()
			current_mode = InteractionMode.NONE
			return
			
			
		if event is InputEventMouse: 
			var finished = building_manager.handle_input(event, grid_pos)
			if finished:
				current_mode = InteractionMode.NONE
			return 

	# ---------------------------------------------------------
	# 3. DECONSTRUCT MODE
	# ---------------------------------------------------------
	if current_mode == InteractionMode.DECONSTRUCT:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			building_manager.deconstruct_building_at(grid_pos)
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			building_manager.deconstruct_building_at(grid_pos)
			
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
			current_mode = InteractionMode.NONE
			print("Exited Deconstruct Mode")
		return 
		
	# ---------------------------------------------------------
	# 4. UPGRADE MODE
	# ---------------------------------------------------------
	if current_mode == InteractionMode.UPGRADE:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if building_manager.upgrade_building_at(grid_pos):
				last_hovered_upgrade_tile = Vector2i(-1, -1)
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if building_manager.upgrade_building_at(grid_pos):
				last_hovered_upgrade_tile = Vector2i(-1, -1)
			
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
			current_mode = InteractionMode.NONE
			if last_hovered_upgrade_tile != Vector2i(-1, -1):
				last_hovered_upgrade_tile = Vector2i(-1, -1)
				building_manager.placement_ended.emit() 
			print("Exited Upgrade Mode")
		return 

	# ---------------------------------------------------------
	# 5. TERRAFORM MODE
	# ---------------------------------------------------------
	if current_mode == InteractionMode.TERRAFORM:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				last_terrain_tile = grid_pos
				if building_manager.occupied_tiles.has(grid_pos) and building_manager.occupied_tiles[grid_pos] is TerraformSite:
					is_terrain_remove_brush = true
					building_manager.deconstruct_building_at(grid_pos)
				else:
					is_terrain_remove_brush = false
					building_manager._try_add_terrain_job(grid_pos)
			else:
				last_terrain_tile = Vector2i(-1, -1)
				
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if grid_pos != last_terrain_tile:
				last_terrain_tile = grid_pos
				if is_terrain_remove_brush:
					if building_manager.occupied_tiles.has(grid_pos) and building_manager.occupied_tiles[grid_pos] is TerraformSite:
						building_manager.deconstruct_building_at(grid_pos)
				else:
					building_manager._try_add_terrain_job(grid_pos)
			
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
			current_mode = InteractionMode.NONE
			last_terrain_tile = Vector2i(-1, -1)
			print("Exited Terrain Mode")
		return 
		
	# ---------------------------------------------------------
	# 6. DEFAULT SELECTION & CANCEL
	# ---------------------------------------------------------
	if event.is_action_pressed("ui_left"):
		if current_mode == InteractionMode.NONE:
			building_manager.select_building_at(grid_pos)
			if has_node("WaveManager"):
				$WaveManager.deselect_enemy()

	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("right_click"):
		building_manager.cancel_placement()
		current_mode = InteractionMode.NONE

# ==========================================
# HOTBAR & UI
# ==========================================

func _setup_hotbar_items():
	_add_building_to_bar("Core", core_scene)

func _on_core_placed():
	print_debug("from level on core placed")
	if hotbar and hotbar.has_method("remove_button"):
		hotbar.remove_button("Core")
	_add_unlocked_buildings()
	
func _add_unlocked_buildings():
	_add_building_to_bar("Belt", conveyor_scene)
	_add_building_to_bar("Router", router_scene)
	_add_building_to_bar("Filter", filter_scene)
	_add_building_to_bar("Hut", lumberjack_scene)
	_add_building_to_bar("Sawmill", sawmill_scene)
	_add_building_to_bar("Stockpile", stockpile_scene)
	_add_building_to_bar("Bow Tower", bow_tower_scene)
	_add_building_to_bar("Wall", wall_scene)
	_add_building_to_bar("Gate", gate_scene)
	
	_add_building_to_bar("Mine", mine_scene)
	_add_building_to_bar("Stonemason", stonemason_scene)
	_add_building_to_bar("Fletcher", fletcher_scene)

func _add_building_to_bar(name: String, packed_scene: PackedScene):
	if not packed_scene: return
	var temp = packed_scene.instantiate()
	var icon = temp.icon if "icon" in temp else null
	hotbar.add_button(name, icon, packed_scene, true)
	temp.queue_free()
	
func _on_hotbar_item_selected(data, is_building):
	building_manager.cancel_placement()
	if is_building:
		current_mode = InteractionMode.PLACE_BUILDING
		building_manager.start_placing(data)

# ==========================================
# RESOURCES & ENVIRONMENT
# ==========================================

func _on_resource_state_changed(tile: Vector2i, state: int, data: TileDataResource):
	match state:
		ResourceManager.ResourceState.FULL:
			object_layer.set_cell(tile, 0, data.atlas_coords_full)
			if active_grid_objects.has(tile):
				active_grid_objects[tile]["health"] = data.total_resources
		ResourceManager.ResourceState.HARVESTING:
			if data.atlas_coords_harvesting != Vector2i(-1, -1):
				object_layer.set_cell(tile, 0, data.atlas_coords_harvesting)
		ResourceManager.ResourceState.DEPLETED:
			if data.atlas_coords_depleted != Vector2i(-1, -1):
				object_layer.set_cell(tile, 0, data.atlas_coords_depleted)
			else:
				object_layer.set_cell(tile, -1)

func _on_resource_destroyed(tile: Vector2i):
	if active_grid_objects.has(tile):
		active_grid_objects.erase(tile)
	object_layer.erase_cell(tile) 
	
	if building_manager and building_manager.pathfinder:
		building_manager.pathfinder.set_obstacle(tile, false)
		building_manager.pathfinder.set_weighted_obstacle(tile, 1.0)

func handle_harvest_input(grid_pos: Vector2i):
	if not active_grid_objects.has(grid_pos): return
	var obj_info = active_grid_objects[grid_pos]
	ResourceManager.request_harvest(grid_pos, obj_info)

func get_object_tile_index(tile: Vector2i) -> int:
	var atlas := object_layer.get_cell_atlas_coords(tile)
	if atlas == Vector2i(-1, -1): return -1
	return atlas.y * ATLAS_COLUMNS + atlas.x

# ==========================================
# COMBAT & PROJECTILES
# ==========================================

func _on_tower_fired(source_tower, start_pos, target_node, item_data, final_damage, speed, angle_offset):
	if not projectile_scene:
		print("Error: Projectile Scene not assigned in Level Inspector")
		return
	
	var dir = Vector2.RIGHT 
	if is_instance_valid(target_node):
		dir = (target_node.global_position - start_pos).normalized()
	
	dir = dir.rotated(angle_offset)
	var proj = projectile_scene.instantiate()
	object_layer.add_child(proj)
	
	if proj.has_method("setup"):
		proj.setup(start_pos, dir, speed, final_damage, item_data.texture, source_tower)

# ==========================================
# MAP GENERATION
# ==========================================

func generate_simple_map():
	terrain_layer.clear()
	object_layer.clear()
	active_grid_objects.clear()
	
	var land_noise = FastNoiseLite.new()
	land_noise.seed = randi()
	land_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	land_noise.frequency = 0.035 
	
	var forest_noise = FastNoiseLite.new()
	forest_noise.seed = randi()
	forest_noise.frequency = 0.12 
	
	var stone_noise = FastNoiseLite.new()
	stone_noise.seed = randi() + 1 
	stone_noise.frequency = 0.06 
	
	var biome_noise = FastNoiseLite.new()
	biome_noise.seed = randi() + 2
	biome_noise.frequency = 0.015 
	
	var river_noise = FastNoiseLite.new()
	river_noise.seed = randi() + 3
	river_noise.frequency = 0.006 
	
	var water_level = 0.16
	var sand_level = 0.20
	
	match current_map_type:
		MapGenType.LAKES:
			land_noise.frequency = 0.08 
			water_level = 0.24 
			sand_level = 0.28
		MapGenType.MAINLAND:
			pass 
		MapGenType.RIVER_DIVIDE:
			pass 
			
	var terrain_map := {}

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var grid_pos = Vector2i(x, y)
			
			var nx = 2.0 * x / MAP_WIDTH - 1.0
			var ny = 2.0 * y / MAP_HEIGHT - 1.0
			var dist = sqrt(nx*nx + ny*ny)
			var falloff = clamp(1.1 - dist * 1.3, 0.0, 1.0)
			
			var noise_val = (land_noise.get_noise_2d(x, y) + 1.0) / 2.0
			var elevation = noise_val * falloff

			var type = TERRAIN_WATER
			if elevation < water_level: type = TERRAIN_WATER
			elif elevation < sand_level: type = TERRAIN_SAND
			else: type = TERRAIN_GRASS 
				
			if current_map_type == MapGenType.RIVER_DIVIDE:
				if type == TERRAIN_GRASS or type == TERRAIN_SAND:
					var r_val = abs(river_noise.get_noise_2d(x, y))
					if r_val < 0.05: type = TERRAIN_WATER
					elif r_val < 0.06: type = TERRAIN_SAND
			
			terrain_map[grid_pos] = type

	for pos in terrain_map:
		var type = terrain_map[pos]
		var atlas_coords = Vector2i(type % ATLAS_COLUMNS, type / ATLAS_COLUMNS)
		terrain_layer.set_cell(pos, 0, atlas_coords)

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var pos = Vector2i(x, y)
			if terrain_map[pos] == TERRAIN_GRASS:
				var biome_val = biome_noise.get_noise_2d(x, y)
				if biome_val > 0.15:
					var s_val = (stone_noise.get_noise_2d(x, y) + 1.0) / 2.0
					if s_val > 0.55: place_resource_at(pos, RES_STONE)
				elif biome_val < -0.15:
					var d_val = (forest_noise.get_noise_2d(x, y) + 1.0) / 2.0
					if d_val > 0.60: place_resource_at(pos, RES_TREE)

	print("Map generated: ", MapGenType.keys()[current_map_type])

func place_resource_at(grid_pos: Vector2i, resource_index: int):
	if resource_index >= tile_library.size(): return
	var data = tile_library[resource_index]
	object_layer.set_cell(grid_pos, 0, data.atlas_coords_full)
	active_grid_objects[grid_pos] = {
		"health": data.total_resources,
		"data": data
	}

func place_tile(grid_pos: Vector2i, data: TileDataResource):
	var correct_index = tile_library.find(data)
	if correct_index == -1: return
	
	var atlas_coords = Vector2i(correct_index % ATLAS_COLUMNS, correct_index / ATLAS_COLUMNS)
	if not data.is_object:
		terrain_layer.set_cell(grid_pos, 0, atlas_coords)
	else:
		if can_place_object(grid_pos):
			var final_coords = data.atlas_coords_full if data.atlas_coords_full != Vector2i(-1, -1) else atlas_coords
			object_layer.set_cell(grid_pos, 0, final_coords)
			active_grid_objects[grid_pos] = {
				"health": data.total_resources,
				"data": data
			}

func can_place_object(grid_pos: Vector2i) -> bool:
	var terrain_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	if terrain_atlas == Vector2i(-1, -1): return false 
	
	var terrain_index = terrain_atlas.y * ATLAS_COLUMNS + terrain_atlas.x
	if terrain_index == TERRAIN_WATER: return false
	if object_layer.get_cell_source_id(grid_pos) != -1: return false
	if building_manager.occupied_tiles.has(grid_pos): return false

	return true

# ==========================================
# MAP SAVE / LOAD
# ==========================================

# Add this helper function at the bottom:
func _on_pause_menu_save_requested(slot: int):
	# The Level passes itself!
	SaveManager.save_game(self, slot)
	
func get_map_save_data() -> Dictionary:
	var terrain_data = {}
	# 1. Save the floor (Grass, Sand, Water, etc.)
	for pos in terrain_layer.get_used_cells():
		var atlas = terrain_layer.get_cell_atlas_coords(pos)
		terrain_data[var_to_str(pos)] = var_to_str(atlas)

	var object_data = {}
	# 2. Save the resources (Trees, Stone) and their current HP
	for pos in active_grid_objects:
		var obj = active_grid_objects[pos]
		var correct_index = tile_library.find(obj["data"])
		object_data[var_to_str(pos)] = {
			"health": obj["health"],
			"lib_index": correct_index
		}

	return {
		"map_type": current_map_type,
		"terrain": terrain_data,
		"objects": object_data
	}

func load_map_save_data(data: Dictionary):
	# 1. Wipe the current blank slate
	terrain_layer.clear()
	object_layer.clear()
	active_grid_objects.clear()

	current_map_type = data.get("map_type", 0)

	# 2. Rebuild the Floor
	var terrain_data = data.get("terrain", {})
	for pos_str in terrain_data:
		var pos = str_to_var(pos_str)
		var atlas = str_to_var(terrain_data[pos_str])
		terrain_layer.set_cell(pos, 0, atlas)

	# 3. Rebuild the Trees and Rocks
	var object_data = data.get("objects", {})
	for pos_str in object_data:
		var pos = str_to_var(pos_str)
		var obj_info = object_data[pos_str]
		var lib_idx = obj_info["lib_index"]

		if lib_idx >= 0 and lib_idx < tile_library.size():
			var tile_data = tile_library[lib_idx]
			
			# Check if it was partially harvested so we use the right sprite!
			var final_coords = tile_data.atlas_coords_full
			if obj_info["health"] < tile_data.total_resources and tile_data.atlas_coords_harvesting != Vector2i(-1, -1):
				final_coords = tile_data.atlas_coords_harvesting
				
			object_layer.set_cell(pos, 0, final_coords)
			active_grid_objects[pos] = {
				"health": obj_info["health"],
				"data": tile_data
			}
			
	print("Map loaded successfully!")
