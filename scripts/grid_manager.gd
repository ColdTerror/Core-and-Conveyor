extends Node2D

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var highlight: Sprite2D = $SelectionHighlight
@onready var tooltip := $"CanvasLayer/Tooltip"
@onready var tooltip_label := $"CanvasLayer/Tooltip/Label"

@export var tile_size_px = Vector2(32, 32)

const ATLAS_COLUMNS := 3
const ATLAS_ROWS := 2
const TILE_COUNT := ATLAS_COLUMNS * ATLAS_ROWS

var current_tile_index := 0
var current_tile := Vector2i.ZERO

const TILE_INFO = {
	0: { "name": "Dirt" },
	1: { "name": "Water" },
	2: { "name": "Sand" },
	3: { "name": "Forest" },
	4: { "name": "Stone" },
	5: { "name": "Building" }
}

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)

	# --- Tooltip ---
	var cell := terrain_layer.get_cell_source_id(grid_pos)
	tooltip.visible = false

	if cell != -1:
		var atlas_coords := terrain_layer.get_cell_atlas_coords(grid_pos)
		var tile_index := atlas_coords.y * ATLAS_COLUMNS + atlas_coords.x

		if TILE_INFO.has(tile_index):
			tooltip_label.text = TILE_INFO[tile_index]["name"]
			tooltip.visible = true

	if tooltip.visible:
		tooltip.global_position = get_viewport().get_mouse_position() + Vector2(16, 16)

		tooltip.global_position.x = min(
			tooltip.global_position.x,
			get_viewport_rect().size.x - tooltip.size.x
		)
		tooltip.global_position.y = min(
			tooltip.global_position.y,
			get_viewport_rect().size.y - tooltip.size.y
		)

	# --- Highlight ---
	highlight.global_position = terrain_layer.map_to_local(grid_pos)

	current_tile = Vector2i(
		current_tile_index % ATLAS_COLUMNS,
		current_tile_index / ATLAS_COLUMNS
	)

	highlight.region_rect.position = Vector2(current_tile) * tile_size_px
	highlight.region_rect.size = tile_size_px

	# --- Paint ---
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		terrain_layer.set_cell(grid_pos, 0, current_tile)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_tile_index = (current_tile_index + 1) % TILE_COUNT
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_tile_index = (current_tile_index - 1 + TILE_COUNT) % TILE_COUNT

	if event.is_action_pressed("select_1"):
		current_tile_index = 0
	elif event.is_action_pressed("select_2"):
		current_tile_index = 1
	elif event.is_action_pressed("select_3"):
		current_tile_index = 2
