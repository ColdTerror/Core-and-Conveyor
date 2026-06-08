# ==============================================================================
# Script: UI/overlay_renderer.gd
# Purpose: Node2D class rendering custom gameplay overlay grids (buildable, safe, and attack heatmaps), ghost previews with ranges during dragging or placing, building footprint boxes for hovered/inspected nodes, and path cost indicators.
# Dependencies: Relies on Level (as parent), BuildingManager (level.building_manager), InputManager to read hovered structures, and ThemeDB for fallback fonts.
# Signals: None.
# ==============================================================================
class_name OverlayRenderer
extends Node2D

@onready var level = get_parent()

var cached_path_draws: Array = []
var _font: Font

var _prev_show_build_grid: bool = false
var _prev_show_safe_grid: bool = false
var _prev_show_attack_grid: bool = false
var _prev_show_path_grid: bool = false
var _prev_placing_building: bool = false
var _prev_hovered_building: Building = null
var _prev_hovered_res_tile: Vector2i = Vector2i(-99999, -99999)
var _prev_terraform_jobs_empty: bool = true
var _prev_overlay_threshold: int = 1
var _prev_show_overlay_numbers: bool = true
var _prev_mode: int = 0 

var _overlay_tick_timer: float = 0.0
const OVERLAY_TICK_RATE: float = 1.0



## Initializes fonts and caching states for custom grid rendering.
func _ready():
	_font = ThemeDB.fallback_font



## Detects state changes to trigger visual redraw requests on grid mode changes.
func _process(delta):
	var bm = level.building_manager
	if not bm: return
	
	var current_mode = InputManager.current_mode
	var current_hover = InputManager.hovered_building

	var needs_redraw = false

	# Path grid: rebuild cache
	if bm.show_path_grid and not _prev_show_path_grid:
		_rebuild_path_cost_cache()

	# Diff-check for toggle redraws
	if (bm.show_build_grid    != _prev_show_build_grid    or \
		bm.show_safe_grid     != _prev_show_safe_grid     or \
		bm.show_attack_grid   != _prev_show_attack_grid   or \
		bm.show_path_grid     != _prev_show_path_grid     or \
		bm.placing_building   != _prev_placing_building   or \
		bm.terraform_jobs.is_empty() != _prev_terraform_jobs_empty or \
		bm.overlay_threshold != _prev_overlay_threshold or \
		bm.show_overlay_numbers != _prev_show_overlay_numbers or \
		current_mode         != _prev_mode):
		needs_redraw = true
		
	# Check if hovered building changed
	if current_hover != _prev_hovered_building:
		needs_redraw = true
		_prev_hovered_building = current_hover
		
	# Check if hovered resource tile changed
	var current_res_hover = InputManager.hovered_resource_tile
	if current_res_hover != _prev_hovered_res_tile:
		needs_redraw = true
		_prev_hovered_res_tile = current_res_hover
		
	# Ghost placement update
	if bm.placing_building or current_mode != 0: 
		needs_redraw = true

	# Throttled overlay ticks
	var has_slow_overlay = bm.show_build_grid or bm.show_safe_grid or \
						   bm.show_attack_grid or not bm.terraform_jobs.is_empty()
	if has_slow_overlay:
		_overlay_tick_timer += delta
		if _overlay_tick_timer >= OVERLAY_TICK_RATE:
			_overlay_tick_timer = 0.0
			needs_redraw = true

	# Save state
	_prev_show_build_grid        = bm.show_build_grid
	_prev_show_safe_grid         = bm.show_safe_grid
	_prev_show_attack_grid       = bm.show_attack_grid
	_prev_show_path_grid         = bm.show_path_grid
	_prev_placing_building       = bm.placing_building
	_prev_terraform_jobs_empty   = bm.terraform_jobs.is_empty()
	_prev_overlay_threshold      = bm.overlay_threshold
	_prev_show_overlay_numbers   = bm.show_overlay_numbers
	_prev_mode                   = current_mode

	if needs_redraw:
		queue_redraw()



## Main Godot draw hook that routes active layer drawing routines.
func _draw():
	_draw_tool_highlight()
	_draw_zone_overlays()
	_draw_ghost_previews()
	_draw_hover_footprint()
	_draw_resource_hover_footprint()
	_draw_path_costs()



## Draws highlights under the mouse cursor depending on current interaction modes.
func _draw_tool_highlight():
	match InputManager.current_mode:
		InputManager.InteractionMode.DECONSTRUCT:
			_draw_grid_highlight(Color(1.0, 0.2, 0.2, 0.3), Color(1.0, 0.2, 0.2, 0.8))
		InputManager.InteractionMode.UPGRADE:
			_draw_grid_highlight(Color(0.2, 0.8, 1.0, 0.3), Color(0.2, 0.8, 1.0, 0.8))
		InputManager.InteractionMode.TERRAFORM:
			var mouse_pos = get_global_mouse_position()
			var grid_pos = level.terrain_layer.local_to_map(mouse_pos)
			var can_tf = false
			if level.building_manager and level.building_manager.has_method("can_terraform"):
				can_tf = level.building_manager.can_terraform(grid_pos)
			
			if can_tf:
				_draw_grid_highlight(Color(1.0, 0.6, 0.0, 0.3), Color(1.0, 0.6, 0.0, 0.8))
			else:
				_draw_grid_highlight(Color(1.0, 0.2, 0.2, 0.3), Color(1.0, 0.2, 0.2, 0.8))


## Renders a filled and bordered outline for a single tile at map locations.
func _draw_grid_highlight(fill_color: Color, outline_color: Color):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = level.terrain_layer.local_to_map(mouse_pos)
	var local_pos = level.terrain_layer.map_to_local(grid_pos)
	
	var half_offset = Vector2(level.tile_size_px.x / 2.0, level.tile_size_px.y / 2.0)
	var top_left = local_pos - half_offset
	var rect = Rect2(top_left, level.tile_size_px)
	
	draw_rect(rect, fill_color, true)
	draw_rect(rect, outline_color, false, 2.0)



## Draws overall buildable limits, safe areas, and attack coverage zones.
func _draw_zone_overlays():
	var bm = level.building_manager
	if not bm: return
	
	var tile_size = 32.0
	var half_offset = Vector2(tile_size / 2.0, tile_size / 2.0)
	var b_width = 2.0
	
	var show_nums = bm.show_overlay_numbers and not bm.placing_building

	if bm.show_build_grid:
		_draw_tile_set(bm.buildable_tiles, Color(0.2, 1.0, 0.2, 0.15), Color(0.2, 1.0, 0.2, 0.8), tile_size, half_offset, b_width)

	if bm.show_safe_grid:
		_draw_heatmap_tiles(bm.safe_tiles, Color(0.2, 0.5, 1.0), tile_size, half_offset, b_width, show_nums)

	if bm.show_attack_grid:
		_draw_heatmap_tiles(bm.attack_tiles, Color(1.0, 0.2, 0.2), tile_size, half_offset, b_width, show_nums)


## Renders a cohesive tile set with outline borders enclosing the shapes.
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


## Renders interactive colored transparency grids representing heatmaps.
func _draw_heatmap_tiles(tiles: Dictionary, base_color: Color, tile_size: float, half_offset: Vector2, b_width: float, show_numbers: bool = true):
	var bm = level.building_manager
	var threshold = bm.overlay_threshold if bm else 1
	var border = Color(base_color.r, base_color.g, base_color.b, 0.8)
	var font = _font
	
	# Filter heatmap tiles by threshold
	var filtered_tiles = {}
	for tile in tiles.keys():
		if tiles[tile] >= threshold:
			filtered_tiles[tile] = tiles[tile]

	# Draw fills and overlap numbers
	for tile in filtered_tiles.keys():
		var overlaps = filtered_tiles[tile]
		
		var alpha = min(0.15 + ((overlaps - threshold) * 0.15), 0.7)
		var fill = Color(base_color.r, base_color.g, base_color.b, alpha)
		var local_pos = level.object_layer.map_to_local(tile) - half_offset
		draw_rect(Rect2(local_pos, Vector2(tile_size, tile_size)), fill)
		
		if show_numbers:
			var text = str(overlaps)
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			var text_pos = local_pos + half_offset + Vector2(-text_size.x / 2.0, text_size.y / 3.0)
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))

	# Draw shrink-wrapped heatmap borders
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



## Renders drag preview rectangles, building footprints, and range circles.
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
	
	# Draw building footprints
	for g in ghosts_to_draw:
		if not is_instance_valid(g): continue
		
		var b_size = g.size if "size" in g else Vector2i(1, 1)
		var footprint_px = Vector2(b_size.x * tile_size, b_size.y * tile_size)
		
		var top_left = -footprint_px / 2.0 
		var is_valid = g.get_meta("is_valid", true)
			
		var border_color = Color(0.2, 1.0, 0.2, 0.9) if is_valid else Color(1.0, 0.2, 0.2, 0.9)
		
		draw_set_transform(to_local(g.global_position), g.rotation, g.scale)
		draw_rect(Rect2(top_left, footprint_px), border_color, false, 2.0)
		
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1,1))



## Outlines the blueprint boxes of currently hovered or selected buildings.
func _draw_hover_footprint():
	# Hide footprints during placement
	if level.building_manager and level.building_manager.placing_building:
		return
		
	var buildings_to_highlight = []
	
	# Grab currently hovered building
	if is_instance_valid(InputManager.hovered_building):
		buildings_to_highlight.append(InputManager.hovered_building)
		
	# Highlight selected menu targets
	if level.building_manager:
		for b in level.building_manager.buildings:
			if is_instance_valid(b) and b.get("is_selected") and not buildings_to_highlight.has(b):
				buildings_to_highlight.append(b)
	
	# Draw active footprints
	for b in buildings_to_highlight:
		if is_instance_valid(b) and b is Building and not b.is_ghost:
			var tile_size = 32.0
			var footprint_px = Vector2(b.size.x * tile_size, b.size.y * tile_size)
			var top_left = to_local(b.global_position) - (footprint_px / 2.0)
			
			var rect = Rect2(top_left, footprint_px)
			
			# Enhance border for selections
			var border_alpha = 0.9 if b.get("is_selected") else 0.5
			var border_color = Color(1.0, 1.0, 1.0, border_alpha) 
			
			draw_rect(rect, Color(1.0, 1.0, 1.0, 0.1), true)
			draw_rect(rect, border_color, false, 2.0)
			
			if b.has_method("is_launcher"):
				if is_instance_valid(b.get("target_receiver")):
					var from_pos = to_local(b.global_position)
					var to_pos = to_local(b.get("target_receiver").global_position)
					draw_line(from_pos, to_pos, Color(0.2, 0.8, 1.0, 0.8), 2.0)
					draw_circle(to_pos, 4.0, Color(0.2, 0.8, 1.0, 0.8))
				if b.get("is_linking_mode"):
					var from_pos = to_local(b.global_position)
					var to_pos = to_local(get_global_mouse_position())
					draw_line(from_pos, to_pos, Color(1.0, 0.8, 0.2, 0.8), 2.0)
					draw_circle(to_pos, 4.0, Color(1.0, 0.8, 0.2, 0.8))



## Draws text weights and blocked status grids.
func _draw_path_costs():
	var bm = level.building_manager
	if not bm or not bm.show_path_grid: return
	
	var font = _font
	
	for item in cached_path_draws:
		draw_string(font, item["pos"], item["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, item["color"])



## Refreshes weights and sólido points on path grid structures.
func _rebuild_path_cost_cache():
	cached_path_draws.clear()
	
	var bm = level.building_manager
	if not bm or not bm.pathfinder or not bm.pathfinder.enemy_astar: return

	var astar = bm.pathfinder.enemy_astar
	var region = astar.region
	var font = _font
	var font_size = 14
	
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var coords = Vector2i(x, y)
			var center_px = bm.terrain_layer.map_to_local(coords)
			
			if astar.is_point_solid(coords):
				# Cache blocked tile marker
				var text = "X"
				var t_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				var draw_pos = center_px - Vector2(t_size.x/2.0, -t_size.y/3.0)
				
				cached_path_draws.append({
					"pos": draw_pos, "text": text, "color": Color(1.0, 0.2, 0.2, 0.8)
				})
			else:
				var cost = astar.get_point_weight_scale(coords)
				if cost > 1.0:
					var text = str(cost)
					var t_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
					var draw_pos = center_px - Vector2(t_size.x/2.0, -t_size.y/3.0)
					
					cached_path_draws.append({
						"pos": draw_pos, "text": text, "color": Color(1.0, 0.0, 0.0, 1.0)
					})



## Outlines the currently hovered resource tile.
func _draw_resource_hover_footprint():
	var tile = InputManager.hovered_resource_tile
	if tile != Vector2i(-99999, -99999):
		var tile_size = 32.0
		var half_offset = Vector2(tile_size / 2.0, tile_size / 2.0)
		var pos = level.object_layer.map_to_local(tile) - half_offset
		var rect = Rect2(pos, Vector2(tile_size, tile_size))
		
		# Draw a light semi-transparent white highlight fill and solid white border
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.1), true)
		draw_rect(rect, Color(1.0, 1.0, 1.0, 0.8), false, 2.0)
