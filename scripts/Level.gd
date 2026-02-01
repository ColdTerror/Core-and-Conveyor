# Level.gd - Rise to Ruins Style Generation
extends Node2D

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var object_layer: TileMapLayer = $ObjectLayer
@onready var highlight: Sprite2D = $SelectionHighlight
@onready var tooltip := $"CanvasLayer/Popup_Layer/Tooltip"
@onready var tooltip_label := $"CanvasLayer/Popup_Layer/Tooltip/Label"

@onready var hover_popup := $CanvasLayer/Popup_Layer/BuildingHoverPopup
@onready var hotbar = $CanvasLayer/Hud_Layer/HotBar_UI

# Mode State
enum InteractionMode { NONE, PLACE_TILE, PLACE_BUILDING }
var current_mode = InteractionMode.NONE


@export var tile_size_px: Vector2 = Vector2(32, 32)

@export var tile_library: Array[TileDataResource] = []

const ATLAS_COLUMNS := 3
const TILE_COUNT := 10
const MAP_WIDTH := 50
const MAP_HEIGHT := 50

# Terrain indices based on your library
const TERRAIN_GRASS := 0
const TERRAIN_WATER := 1
const TERRAIN_SAND := 2
const RES_TREE := 3
const RES_STONE := 4

var current_tile_index := 0
var active_grid_objects := {}


# Dragging Variables
var is_dragging_line: bool = false
var drag_start_pos: Vector2i
# Configure this to match your library! 
# Assuming your library has 4 conveyor items in order: Right, Down, Left, Up
@export var conveyor_start_index: int = 6





@export var item_scene: PackedScene # Drag your Ore/Item .tscn here in the Inspector

@export var stockpile_scene: PackedScene 
@export var lumberjack_scene: PackedScene
@export var sawmill_scene: PackedScene

@onready var building_manager: BuildingManager = $BuildingManager

@onready var building_menu = $CanvasLayer/Popup_Layer/BuildingMenu 


var item_grid := {} # Key: Vector2i (grid pos), Value: Node (the item)

func spawn_item_at_mouse():
	if item_scene == null:
		print("Error: No item_scene assigned in the Inspector!")
		return
		
	# 1. Get positions
	var mouse_pos = get_global_mouse_position()
	var grid_pos = object_layer.local_to_map(mouse_pos)
	var spawn_pos = object_layer.map_to_local(grid_pos)
	
	if item_grid.has(grid_pos):
		print("Cannot spawn: Tile occupied!")
		return
	
	# 2. Create the item instance
	var new_item = item_scene.instantiate()
	
	if new_item.has_method("setup"):
		new_item.setup(self)
		
	# 3. Add it to the scene
	add_child(new_item)
	
	# 4. Set its position to the center of the tile
	new_item.global_position = spawn_pos
	

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

# =========================
# Hotbar stuff
# =========================

# 1. DEFINE WHAT GOES ON THE BAR
func _setup_hotbar_items():
	# A. Add Conveyor Button
	# We use the Right Conveyor (Index 6) as the default "icon" and data
	# Ensure your tile_library has the conveyor at conveyor_start_index!
	if tile_library.size() > conveyor_start_index:
		var conv_data = tile_library[conveyor_start_index]
		
		# 1. Get the main texture from the TileMapLayer
		var source = object_layer.tile_set.get_source(0)
		var base_texture = source.texture
		
		# 2. Create a crop (AtlasTexture)
		var atlas_tex = AtlasTexture.new()
		atlas_tex.atlas = base_texture
		
		# Calculate the rectangle to crop
		# Prefer full coords, fallback to calculated
		var coords = conv_data.atlas_coords_full
		if coords == Vector2i(-1, -1):
			var idx = conveyor_start_index
			coords = Vector2i(idx % ATLAS_COLUMNS, idx / ATLAS_COLUMNS)
			
		atlas_tex.region = Rect2(Vector2(coords) * tile_size_px, tile_size_px)
		
		# 3. Add button
		hotbar.add_button("Belt", atlas_tex, conveyor_start_index, false)
	
	# B. Add Building Buttons
	# We instantiate briefly to get the icon/cost, or you can use a separate Resource system.
	# For now, we trust the packed scenes are assigned.
	
	_add_building_to_bar("Hut", lumberjack_scene)
	_add_building_to_bar("Sawmill", sawmill_scene)
	_add_building_to_bar("Stockpile", stockpile_scene)

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
	current_tile_index = 0
	is_dragging_line = false
	
	if is_building:
		# Data is a PackedScene
		current_mode = InteractionMode.PLACE_BUILDING
		building_manager.start_placing(data)
	else:
		# Data is an Integer (Tile Index)
		current_mode = InteractionMode.PLACE_TILE
		current_tile_index = data # This sets us to the "Right" conveyor
		# Note: The player can still use 'R' to rotate because 'place_tile' checks current_tile_index
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
	
	update_tooltip(grid_pos)
	
	if is_dragging_line: highlight.visible = false
	else: 
		highlight.visible = true
		update_highlight(grid_pos)

	# Only allow Drag Logic if we are in TILE mode
	if current_mode == InteractionMode.PLACE_TILE:
		if Input.is_action_just_pressed("start_end_drag"):
			var current_data = tile_library[current_tile_index]
			if current_data.is_conveyor:
				is_dragging_line = true
				drag_start_pos = grid_pos
				highlight.visible = false
		
		if is_dragging_line: queue_redraw()

		if Input.is_action_just_released("start_end_drag"):
			if is_dragging_line:
				_commit_drag_line(grid_pos)
				is_dragging_line = false
				highlight.visible = true
				queue_redraw()

# ============================================================================
# Conveyer Drag Drop 
# ============================================================================
func _draw():
	if is_dragging_line:
		var current_grid = terrain_layer.local_to_map(get_global_mouse_position())
		var points = _get_straight_line(drag_start_pos, current_grid)
		
		# 1. Determine WHICH data to draw
		var data_to_draw: TileDataResource
		
		if drag_start_pos == current_grid:
			# If we haven't moved, show the currently selected tile (respects 'R' key)
			data_to_draw = tile_library[current_tile_index]
		else:
			# If dragging, calculate the correct direction
			var dir_index = _get_drag_direction_index(drag_start_pos, current_grid)
			var idx = conveyor_start_index + dir_index
			if idx < tile_library.size():
				data_to_draw = tile_library[idx]
			else:
				return # Safety

		# 2. Get the Texture from the TileSet (Assuming Source 0 is your main atlas)
		var source = object_layer.tile_set.get_source(0)
		var texture = source.texture
		
		# 3. Calculate the Source Rect (Where on the sheet is this sprite?)
		# Prefer the explicit full coord, fallback to calculated if needed
		var coords = data_to_draw.atlas_coords_full
		if coords == Vector2i(-1, -1):
			var found_idx = tile_library.find(data_to_draw)
			coords = Vector2i(found_idx % ATLAS_COLUMNS, found_idx / ATLAS_COLUMNS)
			
		var src_rect = Rect2(Vector2(coords) * tile_size_px, tile_size_px)

		# 4. Draw the Ghosts
		for pt in points:
			var world_pos = terrain_layer.map_to_local(pt)
			var draw_pos = world_pos - (tile_size_px / 2.0)
			
			# Optional: Keep a faint blue background to indicate "Valid Placement"
			draw_rect(Rect2(draw_pos, tile_size_px), Color(0.2, 0.6, 1.0, 0.2), true)
			
			# Draw the actual Conveyor Sprite (semi-transparent)
			draw_texture_rect_region(texture, Rect2(draw_pos, tile_size_px), src_rect, Color(1, 1, 1, 0.6))
			
# --- DRAG HELPERS ---

func _commit_drag_line(end_pos: Vector2i):
	# FIX: Check if this was just a single click (No drag occurred)
	if drag_start_pos == end_pos:
		# If we didn't move, use the tile we currently have selected 
		# (This respects the rotation you set with 'R')
		place_tile(end_pos, tile_library[current_tile_index])
		return
	
	var points = _get_straight_line(drag_start_pos, end_pos)
	var dir_index = _get_drag_direction_index(drag_start_pos, end_pos)
	
	# Determine which tile resource to use based on direction
	# Assuming Library Order: [6=Right, 7=Down, 8=Left, 9=Up]
	# Adjust 'conveyor_start_index' in variables to match your setup!
	var correct_resource_index = conveyor_start_index + dir_index
	
	if correct_resource_index >= tile_library.size():
		print("Error: Conveyor index out of bounds")
		return

	var data = tile_library[correct_resource_index]

	# Place the tiles
	for pt in points:
		place_tile(pt, data)

# Returns 0=Right, 1=Up, 2=Left, 3=Down
func _get_drag_direction_index(start: Vector2i, end: Vector2i) -> int:
	var diff = end - start
	
	# If start == end, default to Right (0)
	if diff == Vector2i.ZERO: return 0
	
	if abs(diff.x) >= abs(diff.y):
		# Horizontal
		return 0 if diff.x > 0 else 2 # 0=Right, 2=Left
	else:
		# Vertical
		# Y is negative going UP in Godot (0,0 is top-left)
		return 3 if diff.y > 0 else 1 # 3=Down, 1=Up

func _get_straight_line(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var diff = end - start
	var final_end = end
	
	# Axis Lock
	if abs(diff.x) >= abs(diff.y):
		final_end.y = start.y
	else:
		final_end.x = start.x
		
	# Walk
	var current = start
	var step = Vector2i.ZERO
	if final_end.x != start.x: step.x = sign(final_end.x - start.x)
	if final_end.y != start.y: step.y = sign(final_end.y - start.y)
	
	# Safety loop
	var safe = 0
	while safe < 100:
		points.append(current)
		if current == final_end: break
		current += step
		safe += 1
		
	return points
# ============================================================================
# MAP GENERATION - RISE TO RUINS STYLE
# ============================================================================

func generate_simple_map():
	terrain_layer.clear()
	object_layer.clear()
	active_grid_objects.clear()
	
	# 1. Setup Noises
	var land_noise = FastNoiseLite.new()
	land_noise.seed = randi()
	land_noise.frequency = 0.035 # Lower = Larger landmasses
	land_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	var forest_noise = FastNoiseLite.new()
	forest_noise.seed = randi()
	forest_noise.frequency = 0.12 # Tight clusters for thick forests
	
	var terrain_map := {}

	# 2. Step One: Create the Island and Plateaus
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var grid_pos = Vector2i(x, y)
			
			# Circular Falloff (Ensures map is an island)
			var nx = 2.0 * x / MAP_WIDTH - 1.0
			var ny = 2.0 * y / MAP_HEIGHT - 1.0
			var dist = sqrt(nx*nx + ny*ny)
			var falloff = clamp(1.1 - dist * 1.3, 0.0, 1.0)
			
			# Get noise and combine with falloff
			var noise_val = (land_noise.get_noise_2d(x, y) + 1.0) / 2.0
			var elevation = noise_val * falloff

			# Define "Steps" (Plateaus)
			var type = TERRAIN_WATER
			if elevation < 0.18:
				type = TERRAIN_WATER
			elif elevation < 0.25:
				type = TERRAIN_SAND
			elif elevation < 0.7:
				type = TERRAIN_GRASS # Large building area
			else:
				type = RES_STONE # High mountain ground
			
			terrain_map[grid_pos] = type

	# 3. Apply Terrain to Tilemap
	for pos in terrain_map:
		var type = terrain_map[pos]
		# Note: We use RES_STONE for the mountain ground as well
		var atlas_coords = Vector2i(type % ATLAS_COLUMNS, type / ATLAS_COLUMNS)
		terrain_layer.set_cell(pos, 0, atlas_coords)

	# 4. Step Two: Clumped Resources
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var pos = Vector2i(x, y)
			var t_type = terrain_map[pos]
			
			# Get density noise for objects
			var d_val = (forest_noise.get_noise_2d(x, y) + 1.0) / 2.0
			
			# Thick Forests on Grass
			if t_type == TERRAIN_GRASS:
				if d_val > 0.68: # Higher number = thicker, smaller groves
					place_resource_at(pos, RES_TREE)
			
			# Concentrated Rock Veins on Mountains
			if t_type == RES_STONE:
				if d_val > 0.55:
					place_resource_at(pos, RES_STONE)

	clear_starting_zone()
	print("Rise to Ruins map generated!")

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

func clear_starting_zone():
	var center = Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2)
	var radius = 5
	
	for x in range(center.x - radius, center.x + radius):
		for y in range(center.y - radius, center.y + radius):
			var pos = Vector2i(x, y)
			if center.distance_to(pos) < radius:
				# Ensure ground is grass
				terrain_layer.set_cell(pos, 0, Vector2i(0,0)) 
				# Remove trees/rocks
				object_layer.set_cell(pos, -1)
				active_grid_objects.erase(pos)

# --- Keep your existing UI/Interaction logic below ---

func update_tooltip(grid_pos: Vector2i):
	tooltip.visible = false
	
	# 1. Check for Objects (Trees, Rocks, Buildings) using your dictionary
	if active_grid_objects.has(grid_pos):
		var info = active_grid_objects[grid_pos]
		var data = info["data"]
		
		tooltip_label.text = "%s\nHP: %d/%d" % [data.display_name, info["health"], data.total_resources]
		tooltip.visible = true
		tooltip.global_position = get_viewport().get_mouse_position() + Vector2(16, 16)
		return

	# 2. Fallback: Check for Terrain (Grass/Water/Sand)
	# Since terrain isn't in active_grid_objects, we keep the old math logic here
	var terr_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	if terr_atlas != Vector2i(-1, -1):
		var index = terr_atlas.y * ATLAS_COLUMNS + terr_atlas.x
		if index < tile_library.size():
			tooltip_label.text = tile_library[index].display_name
			tooltip.visible = true
			tooltip.global_position = get_viewport().get_mouse_position() + Vector2(16, 16)

func place_tile(grid_pos: Vector2i, data: TileDataResource):
	# FIX: Find the actual index of the data we want to place
	var correct_index = tile_library.find(data)
	if correct_index == -1: return # Safety check

	# Use correct_index instead of current_tile_index
	var atlas_coords = Vector2i(correct_index % ATLAS_COLUMNS, correct_index / ATLAS_COLUMNS)
	
	if not data.is_object:
		terrain_layer.set_cell(grid_pos, 0, atlas_coords)
	else:
		if can_place_object(grid_pos):
			# NEW: If the data defines its own full sprite (like trees), use that.
			# Otherwise fallback to the calculated atlas_coords (like walls/conveyors)
			var final_coords = atlas_coords
			if data.atlas_coords_full != Vector2i(-1, -1):
				final_coords = data.atlas_coords_full

			object_layer.set_cell(grid_pos, 0, final_coords)
			
			var tile_info = {
				"health": data.total_resources,
				"data": data
			}
			
			if data.is_conveyor:
				tile_info["direction"] = data.conveyor_direction
				
			active_grid_objects[grid_pos] = tile_info

func can_place_object(grid_pos: Vector2i) -> bool:
	var terrain_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	var terrain_index = terrain_atlas.y * ATLAS_COLUMNS + terrain_atlas.x
	return terrain_index != TERRAIN_WATER and object_layer.get_cell_source_id(grid_pos) == -1



func update_highlight(grid_pos: Vector2i):
	highlight.global_position = terrain_layer.map_to_local(grid_pos)
	var atlas_pos = Vector2i(current_tile_index % ATLAS_COLUMNS, current_tile_index / ATLAS_COLUMNS)
	highlight.region_rect = Rect2(Vector2(atlas_pos) * tile_size_px, tile_size_px)


func _input(event):
	# 1. Rotation (Always allowed)
	if event.is_action_pressed("rotate_tile"):
		var current_data = tile_library[current_tile_index]
		if current_data.is_conveyor:
			var start = conveyor_start_index
			current_tile_index = start + ((current_tile_index - start + 1) % 4)

	# 2. Mouse Clicks (Mode Dependent)
	if event.is_action_pressed("ui_left"):
		print_debug('left click' + str(current_mode))
		
		# MODE 1: Placing a Building
		if current_mode == InteractionMode.PLACE_BUILDING:
			building_manager.confirm_placement()
			
			current_mode = InteractionMode.NONE
			
		# MODE 2: Placing Tiles (Belts)
		elif current_mode == InteractionMode.PLACE_TILE:
			if not is_dragging_line:
				place_tile(terrain_layer.local_to_map(get_global_mouse_position()), tile_library[current_tile_index])

		# MODE 3: Selection / Interaction (Clicking existing stuff)
		elif current_mode == InteractionMode.NONE:
			_handle_selection_click()

	# 3. Right Click (Cancel)
	elif event.is_action_pressed("ui_right"):
		building_manager.cancel_placement()
		current_mode = InteractionMode.NONE
		is_dragging_line = false
		queue_redraw()
		
		# Optional: Default right-click behavior (Harvest)
		handle_harvest_input(terrain_layer.local_to_map(get_global_mouse_position()))

func _handle_selection_click():
	var grid_pos = terrain_layer.local_to_map(get_global_mouse_position())
	
	# Check if there is a building at this tile
	if building_manager.occupied_tiles.has(grid_pos):
		var building = building_manager.occupied_tiles[grid_pos]
		
		# Open the menu for this building
		building_menu.open_menu(building)
		
		# Optional: Close the hover popup so it doesn't overlap
		hover_popup.hide()

func print_active_objects():
	print("--- CURRENT ACTIVE GRID OBJECTS ---")
	if active_grid_objects.is_empty():
		print("Grid is empty.")
		return
		
	for grid_pos in active_grid_objects:
		var info = active_grid_objects[grid_pos]
		var data = info["data"]
		
		# Build a readable string for this specific tile
		var output = "Pos: %s | Name: %s | HP: %d" % [grid_pos, data.display_name, info["health"]]
		
		# If it's a conveyor, add the direction info
		if data.is_conveyor:
			output += " | Dir: %s" % str(data.conveyor_direction)
			
		print(output)
	print("------------------------------------")
	print("--- CURRENT ACTIVE ITEM OBJECTS ---")
	# Key: Vector2i (grid pos), Value: Node (the item)
	if item_grid.is_empty():
		print("Grid is empty.")
	else:
		for grid_pos in item_grid:
			var info = item_grid[grid_pos]
			
			print(grid_pos)
	print("------------------------------------")
	
