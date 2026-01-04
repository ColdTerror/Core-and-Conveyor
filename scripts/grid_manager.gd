extends Node2D

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var highlight: Sprite2D = $SelectionHighlight


# This stores the Atlas Coordinates (x, y) of the tile we want to place
var current_tile = Vector2i(0, 0) 

@export var tile_size_px = Vector2(16, 16)

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)
	
	# Snap highlight (assuming sprite is centered)
	highlight.global_position = terrain_layer.map_to_local(grid_pos)
	
	# Update the Sprite's Region Rect
	# We move the 'position' of the region based on which tile is selected
	highlight.region_rect.position = Vector2(current_tile) * tile_size_px
	highlight.region_rect.size = tile_size_px
	
	# Paint with the currently selected tile
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# We use '0' for the source_id (the palette we made)
		terrain_layer.set_cell(grid_pos, 0, current_tile)

func _input(event):
	# Update current_tile based on key presses
	# Adjust these Vector2i coords to match where your colors are in your atlas
	if event.is_action_pressed("select_1"):
		current_tile = Vector2i(0, 0) # e.g., Dirt
	elif event.is_action_pressed("select_2"):
		current_tile = Vector2i(1, 0) # e.g., Grass
	elif event.is_action_pressed("select_3"):
		current_tile = Vector2i(2, 0) # e.g., Tree
	elif event.is_action_pressed("select_4"):
		current_tile = Vector2i(3, 0) # e.g., Water
