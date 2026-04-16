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

# --- DUCK TYPING FOR THE BOT ---
func needs_materials() -> bool:
	return false # Terraforming is free right now! Just requires labor.

func add_build_progress(amount: int):
	health += amount
	queue_redraw()
	
	if has_signal("health_changed"):
		health_changed.emit(health, max_health)
		
	if health >= max_health:
		_finish_terraforming()

func _finish_terraforming():
	var target_tile = occupied_tiles[0]
	
	if job_type == JobType.CONVERT_WATER:
		# Replace water with dirt (Update the 0 to your actual Dirt Tile ID!)
		level_ref.terrain_layer.set_cell(target_tile, 0, Vector2i(0, 0))
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

func _draw():
	var tile_size = 32.0
	var top_left = Vector2(-tile_size / 2.0, -tile_size / 2.0)
	var rect = Rect2(top_left, Vector2(tile_size, tile_size))
	
	# Color code by type (Orange)
	var color = Color(1.0, 0.6, 0.0, 0.8)
	var fill = Color(1.0, 0.6, 0.0, 0.3)
	
	draw_rect(rect, fill, true)
	draw_rect(rect, color, false, 2.0)
	draw_line(top_left, top_left + Vector2(tile_size, tile_size), color, 2.0)
	draw_line(top_left + Vector2(tile_size, 0), top_left + Vector2(0, tile_size), color, 2.0)

# ==========================================
# SAVE / LOAD SYSTEM (Terraform Site)
# ==========================================
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["job_type"] = job_type # e.g., 0 for Remove Object, 1 for Convert Water
	return data

func load_save_data(data: Dictionary):
	super.load_save_data(data)
	job_type = data.get("job_type", 0)
