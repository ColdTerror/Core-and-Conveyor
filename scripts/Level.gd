# Level.gd - Rise to Ruins Style Generation
extends Node2D

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var object_layer: TileMapLayer = $ObjectLayer
@onready var highlight: Sprite2D = $SelectionHighlight
@onready var tooltip := $"CanvasLayer/Tooltip"
@onready var tooltip_label := $"CanvasLayer/Tooltip/Label"

@export var tile_size_px = Vector2(32, 32)
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

func _ready():
	generate_simple_map()

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)
	
	update_tooltip(grid_pos)
	
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if current_tile_index < tile_library.size():
			place_tile(grid_pos, tile_library[current_tile_index])
	
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		mine_tile(grid_pos)
	
	update_highlight(grid_pos)

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
	var atlas_coords = Vector2i(resource_index % ATLAS_COLUMNS, resource_index / ATLAS_COLUMNS)
	
	object_layer.set_cell(grid_pos, 0, atlas_coords)
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
	var obj_atlas = object_layer.get_cell_atlas_coords(grid_pos)
	var terr_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	
	var index = -1
	if obj_atlas != Vector2i(-1, -1):
		index = obj_atlas.y * ATLAS_COLUMNS + obj_atlas.x
	elif terr_atlas != Vector2i(-1, -1):
		index = terr_atlas.y * ATLAS_COLUMNS + terr_atlas.x
		
	if index != -1 and index < tile_library.size():
		tooltip_label.text = tile_library[index].display_name
		tooltip.visible = true
		tooltip.global_position = get_viewport().get_mouse_position() + Vector2(16, 16)

func place_tile(grid_pos: Vector2i, data: TileDataResource):
	var atlas_coords = Vector2i(current_tile_index % ATLAS_COLUMNS, current_tile_index / ATLAS_COLUMNS)
	
	if not data.is_object:
		terrain_layer.set_cell(grid_pos, 0, atlas_coords)
	else:
		if can_place_object(grid_pos):
			object_layer.set_cell(grid_pos, 0, atlas_coords)
			
			# Save the tile data to our dictionary
			var tile_info = {
				"health": data.total_resources,
				"data": data
			}
			
			# If it's a conveyor, we can add extra logic here if needed
			if data.is_conveyor:
				tile_info["direction"] = data.conveyor_direction
				
			active_grid_objects[grid_pos] = tile_info

func can_place_object(grid_pos: Vector2i) -> bool:
	var terrain_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	var terrain_index = terrain_atlas.y * ATLAS_COLUMNS + terrain_atlas.x
	return terrain_index != TERRAIN_WATER and object_layer.get_cell_source_id(grid_pos) == -1

func mine_tile(grid_pos: Vector2i):
	if active_grid_objects.has(grid_pos):
		var tile_info = active_grid_objects[grid_pos]
		var data = tile_info["data"]
		tile_info["health"] -= data.amount_per_mine
		if tile_info["health"] <= 0:
			if "InventoryManager" in self: # Safe check
				InventoryManager.add_resources(data.display_name, data.total_resources)
			object_layer.set_cell(grid_pos, -1)
			active_grid_objects.erase(grid_pos)

func update_highlight(grid_pos: Vector2i):
	highlight.global_position = terrain_layer.map_to_local(grid_pos)
	var atlas_pos = Vector2i(current_tile_index % ATLAS_COLUMNS, current_tile_index / ATLAS_COLUMNS)
	highlight.region_rect = Rect2(Vector2(atlas_pos) * tile_size_px, tile_size_px)

func _input(event):
	# Existing cycle logic...
	if Input.is_key_pressed(KEY_PERIOD):
		current_tile_index = (current_tile_index + 1) % tile_library.size()
	elif Input.is_key_pressed(KEY_COMMA):
		current_tile_index = (current_tile_index - 1 + tile_library.size()) % tile_library.size()

	# NEW: Quick Rotate for Conveyors
	if event.is_action_pressed("rotate_tile"): # Define 'rotate_tile' as 'R' in Input Map
		var current_data = tile_library[current_tile_index]
		if current_data.is_conveyor:
			var start_index = 6 # Change this to the index of your first conveyor
			current_tile_index = start_index + ((current_tile_index - start_index + 1) % 4)
