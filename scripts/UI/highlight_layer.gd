extends Node2D

@onready var level = get_parent()

func _process(_delta):
	# Constantly update the highlight as long as we are in an active tool mode!
	if level.current_mode != level.InteractionMode.NONE:
		queue_redraw()
	else:
		# Clear the drawing if we cancel our tool
		queue_redraw()

func _draw():
	# Ask the Level what mode we are currently in
	if level.current_mode == level.InteractionMode.DECONSTRUCT:
		_draw_grid_highlight(Color(1.0, 0.2, 0.2, 0.3), Color(1.0, 0.2, 0.2, 0.8))
		
	elif level.current_mode == level.InteractionMode.UPGRADE:
		_draw_grid_highlight(Color(0.2, 0.8, 1.0, 0.3), Color(0.2, 0.8, 1.0, 0.8))
		
	elif level.current_mode == level.InteractionMode.TERRAFORM:
		_draw_grid_highlight(Color(1.0, 0.6, 0.0, 0.3), Color(1.0, 0.6, 0.0, 0.8))

func _draw_grid_highlight(fill_color: Color, outline_color: Color):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = level.terrain_layer.local_to_map(mouse_pos)
	var local_pos = level.terrain_layer.map_to_local(grid_pos)
	
	var half_offset = Vector2(level.tile_size_px.x / 2.0, level.tile_size_px.y / 2.0)
	var top_left = local_pos - half_offset
	var rect = Rect2(top_left, level.tile_size_px)
	
	# We use the standard draw commands because this script OWNS the node!
	draw_rect(rect, fill_color, true)
	draw_rect(rect, outline_color, false, 2.0)
