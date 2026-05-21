# ==============================================================================
# Script: Building Classes/terraform_site.gd
# Purpose: Specialized labor site that clears debris/objects or fills in water tiles, querying local terrain atlas coordinates to auto-match neighboring ground types dynamically upon completion.
# Dependencies: Inherits Building. Relies on parent level layers (terrain_layer, object_layer), Pathfinder, and QuotaManager.
# Signals: Emits health_changed and destroyed (inherited from Building).
# ==============================================================================
extends Building # <--- THE FIX: It is now officially a building!
class_name TerraformSite


enum JobType { REMOVE_OBJECT, CONVERT_WATER }
var job_type: JobType

var level_ref: Node2D

var is_ready_to_build: bool = true
var required_items: Dictionary = {} 
var delivered_items: Dictionary = {}

func setup(level: Node2D, grid_pos: Vector2i, type: JobType):
	level_ref = level
	job_type = type
	occupied_tiles = [grid_pos]
	
	grid_origin = grid_pos
	
	building_name = "Clear Terrain" if type == JobType.REMOVE_OBJECT else "Fill Water"
	
	# We assign these here because the base Building class already created them for us!
	health = 0
	max_health = 100
	
	global_position = level_ref.object_layer.map_to_local(grid_pos)
	
	z_index = 10
	
	if "build_range" in self: build_range = 0
	if "corruption_range" in self: corruption_range = 0

# --- DUCK TYPING FOR THE BOT ---
func needs_materials() -> bool:
	return false # Terraforming is free right now! Just requires labor.

func add_build_progress(amount: int):
	health += amount
	queue_redraw()
	
	if has_signal("health_changed"):
		health_changed.emit(health, max_health)
		
	queue_redraw()
	
	if health >= max_health:
		_finish_terraforming()

# --- UPGRADED: Context-Aware Terrain Sampling (Using Atlas Coords) ---
func _get_matching_neighbor_terrain(target_tile: Vector2i) -> Vector2i:
	var dirt_atlas = Vector2i(0, 0)
	var sand_atlas = Vector2i(2, 0)
	
	var dirt_count = 0
	var sand_count = 0
	
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	for offset in neighbors:
		var neighbor_pos = target_tile + offset
		
		# Ensure we are looking at the correct TileMap source (0) before checking the atlas
		if level_ref.terrain_layer.get_cell_source_id(neighbor_pos) == 0:
			var neighbor_atlas = level_ref.terrain_layer.get_cell_atlas_coords(neighbor_pos)
			
			if neighbor_atlas == dirt_atlas:
				dirt_count += 1
			elif neighbor_atlas == sand_atlas:
				sand_count += 1
				
	# If there's strictly more sand around it than dirt, return the sand atlas! 
	if sand_count > dirt_count:
		return sand_atlas
		
	# Otherwise, default to the dirt atlas.
	return dirt_atlas

func _finish_terraforming():
	var target_tile = occupied_tiles[0]
	
	if job_type == JobType.CONVERT_WATER:
		# --- UPGRADED: Ask the scanner what atlas coords to place! ---
		var best_atlas = _get_matching_neighbor_terrain(target_tile)
		
		# set_cell( coords, source_id, atlas_coords )
		level_ref.terrain_layer.set_cell(target_tile, 0, best_atlas)
		
		if level_ref.building_manager.pathfinder:
			level_ref.building_manager.pathfinder.set_obstacle(target_tile, false)
			
	elif job_type == JobType.REMOVE_OBJECT:
		level_ref.object_layer.set_cell(target_tile, -1)
		if level_ref.active_grid_objects.has(target_tile):
			level_ref.active_grid_objects.erase(target_tile)
		if level_ref.building_manager.pathfinder:
			level_ref.building_manager.pathfinder.set_obstacle(target_tile, false)

	destroyed.emit(self)
	queue_free()
# VISUALS
func _draw():
	var tile_size = 32.0
	var top_left = Vector2(-tile_size / 2.0, -tile_size / 2.0)
	var full_rect = Rect2(top_left, Vector2(tile_size, tile_size))
	
	# Base colors (Orange theme for terraforming)
	var outline_color = Color(1.0, 0.6, 0.0, 0.8)
	var bg_color = Color(1.0, 0.6, 0.0, 0.15)
	
	# 1. Base background (faint orange)
	draw_rect(full_rect, bg_color, true)
	
	# 2. Draw the faint "X" underneath the progress
	draw_line(top_left, top_left + Vector2(tile_size, tile_size), Color(1.0, 0.6, 0.0, 0.3), 2.0)
	draw_line(top_left + Vector2(tile_size, 0), top_left + Vector2(0, tile_size), Color(1.0, 0.6, 0.0, 0.3), 2.0)
	
	# 3. Calculate Build Percentage
	var build_pct = clamp(float(health) / float(max_health), 0.0, 1.0)
	
	# 4. Draw Progress Fill (Brighter solid orange rising from the bottom)
	if build_pct > 0:
		var fill_h = tile_size * build_pct
		var fill_rect = Rect2(Vector2(top_left.x, top_left.y + tile_size - fill_h), Vector2(tile_size, fill_h))
		draw_rect(fill_rect, Color(1.0, 0.8, 0.0, 0.6), true)
		
	# 5. Draw border
	draw_rect(full_rect, outline_color, false, 2.0)
# SAVE / LOAD SYSTEM (Terraform Site)
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["job_type"] = job_type # e.g., 0 for Remove Object, 1 for Convert Water
	return data

func load_save_data(data: Dictionary):
	super.load_save_data(data)
	job_type = data.get("job_type", 0)
