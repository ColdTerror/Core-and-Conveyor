extends Node2D

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var object_layer: TileMapLayer = $ObjectLayer
@onready var highlight: Sprite2D = $SelectionHighlight
@onready var tooltip := $"CanvasLayer/Tooltip"
@onready var tooltip_label := $"CanvasLayer/Tooltip/Label"

@export var tile_size_px = Vector2(32, 32)
# Drag and drop your 6 .tres files here in the Inspector in order!
@export var tile_library: Array[TileDataResource] = []

const ATLAS_COLUMNS := 3
const TILE_COUNT := 6

var current_tile_index := 0
var active_grid_objects := {} # { Vector2i: {"health": int, "data": Resource} }

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)
	var current_data = tile_library[current_tile_index]

	# --- Tooltip Logic ---
	update_tooltip(grid_pos)

	# --- Placement Logic ---
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		place_tile(grid_pos, current_data)

	# --- Mining Logic ---
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		mine_tile(grid_pos)

	# --- Highlight Visuals ---
	update_highlight(grid_pos)

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
	@warning_ignore("integer_division")
	var atlas_coords = Vector2i(current_tile_index % ATLAS_COLUMNS, current_tile_index / ATLAS_COLUMNS)
	
	if not data.is_object:
		terrain_layer.set_cell(grid_pos, 0, atlas_coords)
	else:
		if can_place_object(grid_pos):
			object_layer.set_cell(grid_pos, 0, atlas_coords)
			# Automatically registers any "Object" tile into the simulation
			active_grid_objects[grid_pos] = {
				"health": data.total_resources,
				"data": data
			}

func can_place_object(grid_pos: Vector2i) -> bool:
	var terrain_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	var terrain_index = terrain_atlas.y * ATLAS_COLUMNS + terrain_atlas.x
	# Check if terrain is Water (Index 1) or if space is occupied
	return terrain_index != 1 and object_layer.get_cell_source_id(grid_pos) == -1

func mine_tile(grid_pos: Vector2i):
	if active_grid_objects.has(grid_pos):
		var tile_info = active_grid_objects[grid_pos]
		var data = tile_info["data"]
		
		tile_info["health"] -= data.amount_per_mine
		print("Mining ", data.display_name, "... Health: ", tile_info["health"])
		
		if tile_info["health"] <= 0:
			InventoryManager.add_resources(data.display_name, data.total_resources)
			object_layer.set_cell(grid_pos, -1)
			active_grid_objects.erase(grid_pos)

func update_highlight(grid_pos: Vector2i):
	highlight.global_position = terrain_layer.map_to_local(grid_pos)
	@warning_ignore("integer_division")
	var atlas_pos = Vector2i(current_tile_index % ATLAS_COLUMNS, current_tile_index / ATLAS_COLUMNS)
	highlight.region_rect = Rect2(Vector2(atlas_pos) * tile_size_px, tile_size_px)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_tile_index = (current_tile_index + 1) % TILE_COUNT
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_tile_index = (current_tile_index - 1 + TILE_COUNT) % TILE_COUNT
