# Level.gd 
extends Node2D

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var object_layer: TileMapLayer = $ObjectLayer


@onready var hover_popup := $CanvasLayer/Popup_Layer/BuildingHoverPopup
@onready var hotbar = $CanvasLayer/Hud_Layer/HotBar_UI

# Mode State
enum InteractionMode { NONE, PLACE_BUILDING, DECONSTRUCT, UPGRADE}
var current_mode = InteractionMode.NONE

var last_hovered_upgrade_tile := Vector2i(-1, -1)

enum MapGenType { RIVER_DIVIDE, MAINLAND, LAKES }
@export var current_map_type: MapGenType = MapGenType.RIVER_DIVIDE


@export var tile_size_px: Vector2 = Vector2(32, 32)

@export var tile_library: Array[TileDataResource] = []

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


var active_grid_objects := {}


@export_group("Scenes")
@export var item_scene: PackedScene 
@export var stockpile_scene: PackedScene 
@export var lumberjack_scene: PackedScene
@export var sawmill_scene: PackedScene
@export var bow_tower_scene: PackedScene
@export var wall_scene: PackedScene
@export var conveyor_scene: PackedScene 
@export var router_scene: PackedScene 
@export var core_scene: PackedScene 
@export var quarry_scene: PackedScene
@export var stonemason_scene: PackedScene
@export var fletcher_scene: PackedScene


# ------------------

@export var projectile_scene: PackedScene


@onready var building_manager: BuildingManager = $BuildingManager

@onready var building_menu = $CanvasLayer/Popup_Layer/BuildingMenu 

@onready var pathfinder = $Pathfinder

func _ready():
	generate_simple_map()
	hover_popup.hide()
	
	# Connect the new Generic Signal
	ResourceManager.resource_state_changed.connect(_on_resource_state_changed)
	
	# Give the manager a reference to this Level node
	building_manager.initialize(self)

	# NEW: Connect Hotbar Signal
	if hotbar:
		hotbar.item_selected.connect(_on_hotbar_item_selected)
		_setup_hotbar_items()
		
	var map_rect = Rect2i(0, 0, MAP_HEIGHT, MAP_WIDTH)
	pathfinder.setup(terrain_layer, object_layer, map_rect)
	building_manager.pathfinder = pathfinder
	
	building_manager.building_selected.connect(building_menu.open_menu)
	

# =========================
# Hotbar stuff
# =========================

# 1. DEFINE WHAT GOES ON THE BAR
func _setup_hotbar_items():

	
	# B. Add Building Buttons
	# We instantiate briefly to get the icon/cost, or you can use a separate Resource system.
	# For now, we trust the packed scenes are assigned.
	_add_building_to_bar("Belt", conveyor_scene)
	_add_building_to_bar("Router", router_scene)
	_add_building_to_bar("Hut", lumberjack_scene)
	_add_building_to_bar("Sawmill", sawmill_scene)
	_add_building_to_bar("Stockpile", stockpile_scene)
	_add_building_to_bar("Bow Tower", bow_tower_scene)
	_add_building_to_bar("Wall", wall_scene)
	_add_building_to_bar("Core", core_scene)
	_add_building_to_bar("Quarry", quarry_scene)
	_add_building_to_bar("Stonemason", stonemason_scene)
	_add_building_to_bar("Fletcher", fletcher_scene)
	
	

func _add_building_to_bar(name: String, packed_scene: PackedScene):
	if not packed_scene: return
	
	# Hack: Instance it momentarily to read the 'icon' property we added
	var temp = packed_scene.instantiate()
	var icon = null
	if "icon" in temp: icon = temp.icon
	
	hotbar.add_button(name, icon, packed_scene, true)
	temp.queue_free()
	
# 2. HANDLE CLICKS
func _on_hotbar_item_selected(data, is_building):
	# Reset states
	building_manager.cancel_placement()
	
	
	if is_building:
		current_mode = InteractionMode.PLACE_BUILDING
		building_manager.start_placing(data)
	# DELETE THE ELSE BLOCK - no more tile mode for conveyors

# =========================
# Resource state change
# =========================

func _on_resource_state_changed(tile: Vector2i, state: int, data: TileDataResource):
	# Now we don't need hardcoded constants like TREE_FULL_ATLAS!
	# We use the data passed back to us.
	
	match state:
		ResourceManager.ResourceState.FULL:
			object_layer.set_cell(tile, 0, data.atlas_coords_full)
			# Refill health in your tracking dict
			if active_grid_objects.has(tile):
				active_grid_objects[tile]["health"] = data.total_resources

		ResourceManager.ResourceState.HARVESTING:
			# If the data has a specific look for harvesting (leafless), use it
			if data.atlas_coords_harvesting != Vector2i(-1, -1):
				object_layer.set_cell(tile, 0, data.atlas_coords_harvesting)

		ResourceManager.ResourceState.DEPLETED:
			# If the data has a stump look, use it; otherwise remove tile
			if data.atlas_coords_depleted != Vector2i(-1, -1):
				object_layer.set_cell(tile, 0, data.atlas_coords_depleted)
			else:
				object_layer.set_cell(tile, -1) # Remove completely if no stump sprite



func handle_harvest_input(grid_pos: Vector2i):
	# 1. Check if something exists here
	if not active_grid_objects.has(grid_pos):
		return
		
	var obj_info = active_grid_objects[grid_pos]
	var data = obj_info["data"]
	
	# 2. Send Request to Manager
	# We pass 'obj_info' so the manager can edit the health directly.
	# We can also pass a specific amount (e.g. 10) if we have a super-pickaxe later.
	ResourceManager.request_harvest(grid_pos, obj_info)
# ===========================

func get_object_tile_index(tile: Vector2i) -> int:
	var atlas := object_layer.get_cell_atlas_coords(tile)
	if atlas == Vector2i(-1, -1):
		return -1
	return atlas.y * ATLAS_COLUMNS + atlas.x

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)
	
	# --- NEW: UPGRADE HOVER UI ---
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
	# -----------------------------
	
	queue_redraw()

# ============================================================================
# VISUAL OVERLAYS
# ============================================================================
func _draw():
	# DECONSTRUCT (Red)
	if current_mode == InteractionMode.DECONSTRUCT:
		_draw_grid_highlight(Color(1.0, 0.2, 0.2, 0.3), Color(1.0, 0.2, 0.2, 0.8))
		
	# UPGRADE (Blue/Cyan)
	elif current_mode == InteractionMode.UPGRADE:
		_draw_grid_highlight(Color(0.2, 0.8, 1.0, 0.3), Color(0.2, 0.8, 1.0, 0.8))

# Helper function to keep _draw clean!
func _draw_grid_highlight(fill_color: Color, outline_color: Color):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)
	var local_pos = terrain_layer.map_to_local(grid_pos)
	
	var half_offset = Vector2(tile_size_px.x / 2.0, tile_size_px.y / 2.0)
	var top_left = local_pos - half_offset
	var rect = Rect2(top_left, tile_size_px)
	
	draw_rect(rect, fill_color, true)
	draw_rect(rect, outline_color, false, 2.0)


# ============================================================================
# MAP GENERATION - RISE TO RUINS STYLE
# ============================================================================

func generate_simple_map():
	terrain_layer.clear()
	object_layer.clear()
	active_grid_objects.clear()
	
	# 1. Setup Base Noises
	var land_noise = FastNoiseLite.new()
	land_noise.seed = randi()
	land_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	land_noise.frequency = 0.035 # Default mainland frequency
	
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
	
	# --- NEW: MAP TYPE MODIFIERS ---
	var water_level = 0.16
	var sand_level = 0.20
	
	match current_map_type:
		MapGenType.LAKES:
			# Lumpier terrain creates lots of natural bowls and valleys
			land_noise.frequency = 0.08 
			# Raise the sea level so those valleys flood and become lakes
			water_level = 0.24 
			sand_level = 0.28
		MapGenType.MAINLAND:
			pass # Uses default values, but we will skip the river carving!
		MapGenType.RIVER_DIVIDE:
			pass # Uses default values
	# -------------------------------
	
	var terrain_map := {}

	# 2. Step One: Create the Island, Plateaus, and Rivers
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
			# Use the dynamic variables instead of hardcoded numbers!
			if elevation < water_level:
				type = TERRAIN_WATER
			elif elevation < sand_level:
				type = TERRAIN_SAND
			else:
				type = TERRAIN_GRASS 
				
			# --- CARVE THE RIVER (Only if the map type allows it!) ---
			if current_map_type == MapGenType.RIVER_DIVIDE:
				if type == TERRAIN_GRASS or type == TERRAIN_SAND:
					var r_val = abs(river_noise.get_noise_2d(x, y))
					
					if r_val < 0.05: 
						type = TERRAIN_WATER
					elif r_val < 0.06: 
						type = TERRAIN_SAND
			# ---------------------------------------------------------
			
			terrain_map[grid_pos] = type

	# 3. Apply Terrain to Tilemap
	for pos in terrain_map:
		var type = terrain_map[pos]
		var atlas_coords = Vector2i(type % ATLAS_COLUMNS, type / ATLAS_COLUMNS)
		terrain_layer.set_cell(pos, 0, atlas_coords)

	# 4. Step Two: Clumped Resources (Objects on Grass)
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var pos = Vector2i(x, y)
			
			if terrain_map[pos] == TERRAIN_GRASS:
				var biome_val = biome_noise.get_noise_2d(x, y)
				
				if biome_val > 0.15:
					var s_val = (stone_noise.get_noise_2d(x, y) + 1.0) / 2.0
					if s_val > 0.55: 
						place_resource_at(pos, RES_STONE)
						
				elif biome_val < -0.15:
					var d_val = (forest_noise.get_noise_2d(x, y) + 1.0) / 2.0
					if d_val > 0.60: 
						place_resource_at(pos, RES_TREE)

	print("Map generated: ", MapGenType.keys()[current_map_type])


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func place_resource_at(grid_pos: Vector2i, resource_index: int):
	if resource_index >= tile_library.size(): return
	
	var data = tile_library[resource_index]
	
	# NEW: Use the explicit coordinate from the resource data
	object_layer.set_cell(grid_pos, 0, data.atlas_coords_full)
	
	# Register in the system
	active_grid_objects[grid_pos] = {
		"health": data.total_resources,
		"data": data
	}



# ====================================================
# MODIFIED: place_tile (Now Handles Conveyor Buildings)
# ====================================================
func place_tile(grid_pos: Vector2i, data: TileDataResource):
	var correct_index = tile_library.find(data)
	if correct_index == -1: return
	
	var atlas_coords = Vector2i(correct_index % ATLAS_COLUMNS, correct_index / ATLAS_COLUMNS)
	
	# DELETE THIS ENTIRE SECTION:
	# --- CONVEYOR LOGIC (Spawn Building) ---
	# if data.is_conveyor:
	#     ... all the belt spawning code ...
	# ---------------------------------------

	# Normal tile placement (terrain/resources)
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
	# 1. Check Terrain (Water check)
	var terrain_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	# Safety check for invalid terrain
	if terrain_atlas == Vector2i(-1, -1): return false 
	
	var terrain_index = terrain_atlas.y * ATLAS_COLUMNS + terrain_atlas.x
	if terrain_index == TERRAIN_WATER:
		return false

	# 2. Check Object Layer (Trees, Rocks, existing Belts)
	if object_layer.get_cell_source_id(grid_pos) != -1:
		return false

	# 3. Check Buildings (Towers, Sawmills)
	if building_manager.occupied_tiles.has(grid_pos):
		return false

	return true


func _unhandled_input(event):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)

	# 1. Rotation - UPDATE TO:
	if event.is_action_pressed("rotate_tile"):
		if current_mode == InteractionMode.PLACE_BUILDING:
			building_manager.rotate_ghost()
		return
	
	#Change into deconstruct mode
	if event.is_action_pressed("deconstruct_hotkey"): # (Map this in Project Settings -> Input Map)
		building_manager.cancel_placement()
		current_mode = InteractionMode.DECONSTRUCT
		print("Entered Deconstruct Mode")
		
	# --- Change into UPGRADE mode ---
	# (Remember to map "upgrade_hotkey" to 'U' in Project Settings -> Input Map!)
	if event.is_action_pressed("upgrade_hotkey"): 
		building_manager.cancel_placement()
		current_mode = InteractionMode.UPGRADE
		print("Entered Upgrade Mode")

	# 2. BUILDING MODE (Delegated to Manager)
	# We check this FIRST. If we are placing a building, we send Presses, Releases, 
	# and Motion events to the manager so it can handle dragging walls.
	if current_mode == InteractionMode.PLACE_BUILDING:
		if event is InputEventMouse: # Covers Motion and Buttons
			# The manager returns TRUE if it placed a single building and finished.
			# It returns FALSE if it's dragging or waiting for more input.
			var finished = building_manager.handle_input(event, grid_pos)
			
			if finished:
				current_mode = InteractionMode.NONE
			return # Don't let building clicks trigger other logic below

	# --- NEW: DECONSTRUCT MODE ---
	if current_mode == InteractionMode.DECONSTRUCT:
		# Let the player click and drag to delete multiple things quickly
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			building_manager.deconstruct_building_at(grid_pos)
			
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			building_manager.deconstruct_building_at(grid_pos)
			
		# Right click or Escape to cancel deconstruct mode
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_right"):
			current_mode = InteractionMode.NONE
			print("Exited Deconstruct Mode")
			
		return # Stop processing other clicks
		
	# --- UPGRADE MODE LOGIC ---
	if current_mode == InteractionMode.UPGRADE:
		# Click and drag to upgrade multiple things quickly
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if building_manager.upgrade_building_at(grid_pos):
				last_hovered_upgrade_tile = Vector2i(-1, -1)
			
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if building_manager.upgrade_building_at(grid_pos):
				last_hovered_upgrade_tile = Vector2i(-1, -1)
			
		# Right click or Escape to cancel upgrade mode
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_right"):
			current_mode = InteractionMode.NONE
			if last_hovered_upgrade_tile != Vector2i(-1, -1):
				last_hovered_upgrade_tile = Vector2i(-1, -1)
				building_manager.placement_ended.emit() 
			print("Exited Upgrade Mode")
			
		return # Stop processing other clicks

	# 3. TILE MODE & SELECTION (Standard Clicks)
	# Only listen for explicit "Presses" for these modes
	if event.is_action_pressed("ui_left"):
		
		# MODE: Selection / Interaction (Clicking existing stuff)
		if current_mode == InteractionMode.NONE:
			# Level doesn't care if a building is there, it just tells the manager to check!
			building_manager.select_building_at(grid_pos)
			
			if has_node("WaveManager"):
				$WaveManager.deselect_enemy()

	# 4. CANCELLATION (Escape OR Right Click)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_right"):
		# Common Cancel
		building_manager.cancel_placement()
		current_mode = InteractionMode.NONE
		


		


# This function listens for the Tower's signal
func _on_tower_fired(source_tower, start_pos, target_node, item_data, final_damage, speed, angle_offset):
	if not projectile_scene:
		print("Error: Projectile Scene not assigned in Level Inspector")
		return
	
	# 1. Calculate Direction
	var dir = Vector2.RIGHT # Default
	if is_instance_valid(target_node):
		dir = (target_node.global_position - start_pos).normalized()
	
	# 2. Apply Spread (Rotate the vector)
	# If angle_offset is 0 (Bow), this does nothing. 
	# If Shotgun, this fans the arrows out.
	dir = dir.rotated(angle_offset)
	
	# 3. Spawn the Projectile
	var proj = projectile_scene.instantiate()
	
	# Add to Object Layer so it sorts with buildings/units
	object_layer.add_child(proj)
	
	# Configure it
	# Note: We assume your Projectile.gd has a 'setup' function
	if proj.has_method("setup"):
		proj.setup(start_pos, dir, speed, final_damage, item_data.texture, source_tower)
		
