extends Node2D
class_name OverlayRenderer

@onready var level = get_parent()

func _process(_delta):
	queue_redraw()

func _draw():
	_draw_tool_highlight()
	_draw_terrain_jobs()
	_draw_zone_overlays()
	_draw_ghost_previews()

# ==========================================
# TOOL HIGHLIGHT (cursor indicator)
# ==========================================

func _draw_tool_highlight():
	match level.current_mode:
		level.InteractionMode.DECONSTRUCT:
			_draw_grid_highlight(Color(1.0, 0.2, 0.2, 0.3), Color(1.0, 0.2, 0.2, 0.8))
		level.InteractionMode.UPGRADE:
			_draw_grid_highlight(Color(0.2, 0.8, 1.0, 0.3), Color(0.2, 0.8, 1.0, 0.8))
		level.InteractionMode.TERRAFORM:
			_draw_grid_highlight(Color(1.0, 0.6, 0.0, 0.3), Color(1.0, 0.6, 0.0, 0.8))

func _draw_grid_highlight(fill_color: Color, outline_color: Color):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = level.terrain_layer.local_to_map(mouse_pos)
	var local_pos = level.terrain_layer.map_to_local(grid_pos)
	
	var half_offset = Vector2(level.tile_size_px.x / 2.0, level.tile_size_px.y / 2.0)
	var top_left = local_pos - half_offset
	var rect = Rect2(top_left, level.tile_size_px)
	
	draw_rect(rect, fill_color, true)
	draw_rect(rect, outline_color, false, 2.0)

# ==========================================
# TERRAIN JOB MARKERS (red/blue X markers)
# ==========================================

func _draw_terrain_jobs():
	var bm = level.building_manager
	if not bm or bm.terraform_jobs.is_empty(): return
	
	var tile_size = 32.0
	var half = Vector2(tile_size / 2.0, tile_size / 2.0)
	
	for tile in bm.terraform_jobs.keys():
		var job_type = bm.terraform_jobs[tile]
		var center = level.object_layer.map_to_local(tile)
		var top_left = center - half
		
		# Red = remove object, Blue = convert water
		var color = Color(1.0, 0.2, 0.2, 0.8) if job_type == TerraformSite.JobType.REMOVE_OBJECT else Color(0.2, 0.6, 1.0, 0.8)
		var fill = Color(color.r, color.g, color.b, 0.15)
		
		var rect = Rect2(top_left, Vector2(tile_size, tile_size))
		draw_rect(rect, fill, true)
		draw_rect(rect, color, false, 2.0)
		draw_line(top_left, top_left + Vector2(tile_size, tile_size), color, 2.0)
		draw_line(top_left + Vector2(tile_size, 0), top_left + Vector2(0, tile_size), color, 2.0)

# ==========================================
# ZONE OVERLAYS (F1/F2/F3 hotkeys)
# ==========================================

func _draw_zone_overlays():
	var bm = level.building_manager
	if not bm: return
	
	var tile_size = 32.0
	var half_offset = Vector2(tile_size / 2.0, tile_size / 2.0)
	var b_width = 2.0

	if bm.show_build_grid:
		_draw_tile_set(bm.buildable_tiles, Color(0.2, 1.0, 0.2, 0.15), Color(0.2, 1.0, 0.2, 0.8), tile_size, half_offset, b_width)

	if bm.show_safe_grid:
		_draw_heatmap_tiles(bm.safe_tiles, Color(0.2, 0.5, 1.0), tile_size, half_offset, b_width)

	if bm.show_attack_grid:
		_draw_heatmap_tiles(bm.attack_tiles, Color(1.0, 0.2, 0.2), tile_size, half_offset, b_width)

func _draw_tile_set(tiles: Dictionary, fill: Color, border: Color, tile_size: float, half_offset: Vector2, b_width: float):
	for tile in tiles.keys():
		var local_pos = level.object_layer.map_to_local(tile) - half_offset
		draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), fill)
	
	for tile in tiles.keys():
		var pos = level.object_layer.map_to_local(tile) - half_offset
		var tl = pos
		var tr = pos + Vector2(tile_size, 0)
		var bl = pos + Vector2(0, tile_size)
		var br = pos + Vector2(tile_size, tile_size)
		if not tiles.has(tile + Vector2i.UP):    draw_line(tl, tr, border, b_width)
		if not tiles.has(tile + Vector2i.DOWN):  draw_line(bl, br, border, b_width)
		if not tiles.has(tile + Vector2i.LEFT):  draw_line(tl, bl, border, b_width)
		if not tiles.has(tile + Vector2i.RIGHT): draw_line(tr, br, border, b_width)

func _draw_heatmap_tiles(tiles: Dictionary, base_color: Color, tile_size: float, half_offset: Vector2, b_width: float):
	var bm = level.building_manager
	var threshold = bm.overlay_threshold if bm else 1
	var border = Color(base_color.r, base_color.g, base_color.b, 0.8)
	var font = ThemeDB.fallback_font
	
	# 1. FILTER THE TILES
	# Create a temporary dictionary of only the tiles that meet our current layer depth
	var filtered_tiles = {}
	for tile in tiles.keys():
		if tiles[tile] >= threshold:
			filtered_tiles[tile] = tiles[tile]

	# 2. DRAW FILLS AND NUMBERS
	for tile in filtered_tiles.keys():
		var overlaps = filtered_tiles[tile]
		
		# The alpha resets based on the threshold, so the base layer always looks clean!
		var alpha = min(0.15 + ((overlaps - threshold) * 0.15), 0.7)
		var fill = Color(base_color.r, base_color.g, base_color.b, alpha)
		var local_pos = level.object_layer.map_to_local(tile) - half_offset
		draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), fill)
		
		# Draw the exact number in the center of the tile!
		var text = str(overlaps)
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		var text_pos = local_pos + half_offset + Vector2(-text_size.x / 2.0, text_size.y / 3.0)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))

	# 3. DRAW SHRINK-WRAPPED BORDERS
	# Because we check against 'filtered_tiles.has()', the outer border will 
	# dynamically redraw itself around whatever layer depth you are currently viewing!
	for tile in filtered_tiles.keys():
		var pos = level.object_layer.map_to_local(tile) - half_offset
		var tl = pos
		var tr = pos + Vector2(tile_size, 0)
		var bl = pos + Vector2(0, tile_size)
		var br = pos + Vector2(tile_size, tile_size)
		
		if not filtered_tiles.has(tile + Vector2i.UP):    draw_line(tl, tr, border, b_width)
		if not filtered_tiles.has(tile + Vector2i.DOWN):  draw_line(bl, br, border, b_width)
		if not filtered_tiles.has(tile + Vector2i.LEFT):  draw_line(tl, bl, border, b_width)
		if not filtered_tiles.has(tile + Vector2i.RIGHT): draw_line(tr, br, border, b_width)

# ==========================================
# GHOST PREVIEWS (building placement ranges)
# ==========================================

func _draw_ghost_previews():
	var bm = level.building_manager
	if not bm or not bm.placing_building: return
	
	var tile_size = 32.0
	var half_offset = Vector2(tile_size / 2.0, tile_size / 2.0)
	var b_width = 2.0
	
	var ghosts_to_draw = []
	if bm.is_dragging and bm.drag_ghosts.size() > 0:
		ghosts_to_draw = bm.drag_ghosts
	elif bm.ghost_building:
		ghosts_to_draw = [bm.ghost_building]

	var unique_safe_tiles = {}
	var unique_build_tiles = {}

	for g in ghosts_to_draw:
		if not is_instance_valid(g): continue
		var origin = level.object_layer.local_to_map(g.global_position)
		
		if "corruption_range" in g and g.corruption_range > 0:
			for t in bm._get_tiles_in_radius(origin, g, g.corruption_range):
				unique_safe_tiles[t] = true
				
		if "build_range" in g and g.build_range > 0:
			for t in bm._get_tiles_in_radius(origin, g, g.build_range):
				unique_build_tiles[t] = true

	# Draw fills
	for t in unique_safe_tiles.keys():
		var pos = level.object_layer.map_to_local(t) - half_offset
		draw_rect(Rect2(pos, Vector2(tile_size, tile_size)), Color(0.5, 0.8, 1.0, 0.15))
		
	for t in unique_build_tiles.keys():
		var pos = level.object_layer.map_to_local(t) - half_offset
		draw_rect(Rect2(pos, Vector2(tile_size, tile_size)), Color(0.5, 1.0, 0.5, 0.15))

	# Draw borders
	_draw_tile_set(unique_build_tiles, Color(0,0,0,0), Color(0.2, 1.0, 0.2, 0.8), tile_size, half_offset, b_width)
	_draw_tile_set(unique_safe_tiles,  Color(0,0,0,0), Color(0.2, 0.5, 1.0, 0.8), tile_size, half_offset, b_width)
	
	# Draw Exact Building Footprints
	for g in ghosts_to_draw:
		if not is_instance_valid(g): continue
		
		var b_size = g.size if "size" in g else Vector2i(1, 1)
		var footprint_px = Vector2(b_size.x * tile_size, b_size.y * tile_size)
		
		# The physical center of the building is exactly half the size up and left
		var top_left = -footprint_px / 2.0 
		
		var is_valid = g.get_meta("is_valid", true)
			
		var border_color = Color(0.2, 1.0, 0.2, 0.9) if is_valid else Color(1.0, 0.2, 0.2, 0.9)
		var grid_color = Color(border_color.r, border_color.g, border_color.b, 0.3) # Faint version
		
		# Align the Godot canvas to the ghost's exact position and rotation
		draw_set_transform(to_local(g.global_position), g.rotation, g.scale)
		
		# 1. Draw the thick outer border
		draw_rect(Rect2(top_left, footprint_px), border_color, false, 2.0)
		
			
	# Reset the canvas transform so it doesn't mess up the rest of the game!
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1,1))
