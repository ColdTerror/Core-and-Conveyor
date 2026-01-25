# HarvesterBuilding.gd
extends Building
class_name HarvesterBuilding

@export_group("Settings")
@export var target_resource: TileDataResource  # Drag Tree.tres or Stone.tres here!
@export var scan_radius: int = 4
@export var harvest_damage: int = 2
@export var work_interval: float = 1.0

# Visuals
@onready var beam_line: Line2D = $Line2D

var level_ref: Node2D
var work_timer: float = 0.0
var current_target: Vector2i = Vector2i.MAX

# --- SETUP (Called by BuildingManager) ---
func setup(level_instance: Node2D):
	level_ref = level_instance

# --- MAIN LOOP ---
func building_tick(delta: float) -> void:
	# Safety checks
	if not level_ref or not target_resource: 
		return

	work_timer -= delta
	
	# 1. Update Visuals
	if current_target != Vector2i.MAX:
		_draw_beam(current_target)
	else:
		if beam_line: beam_line.clear_points()

	# 2. Work Logic
	if work_timer <= 0:
		work_timer = work_interval
		_perform_harvest()

func _perform_harvest():
	# If we lost our target or it became invalid, find a new one
	if not _is_valid_target(current_target):
		current_target = _find_nearest_target()
	
	# If we have a valid target, hit it
	if current_target != Vector2i.MAX:
		var info = level_ref.active_grid_objects[current_target]
		ResourceManager.request_harvest(current_target, info, harvest_damage)

# --- FINDER LOGIC ---
func _find_nearest_target() -> Vector2i:
	var center = level_ref.object_layer.local_to_map(global_position)
	var best_pos = Vector2i.MAX
	var min_dist = 99999.0
	
	# Scan the square area around the building
	for x in range(-scan_radius, scan_radius + 1):
		for y in range(-scan_radius, scan_radius + 1):
			var check_pos = center + Vector2i(x, y)
			
			if _is_valid_target(check_pos):
				var dist = center.distance_squared_to(check_pos)
				if dist < min_dist:
					min_dist = dist
					best_pos = check_pos
	
	return best_pos

func _is_valid_target(pos: Vector2i) -> bool:
	if pos == Vector2i.MAX: return false
	
	# 1. Does the level have an object there?
	if not level_ref.active_grid_objects.has(pos):
		return false
	
	var info = level_ref.active_grid_objects[pos]
	
	# 2. Is it dead/empty?
	if info["health"] <= 0: return false
	
	# 3. IS IT THE RIGHT RESOURCE? (The Magic Check)
	# This checks if the file in the grid matches the file in our Inspector
	if info["data"] != target_resource:
		return false
		
	return true

func _draw_beam(grid_pos: Vector2i):
	if not beam_line: return
	
	# Convert grid coordinate to local coordinate
	var target_world = level_ref.object_layer.map_to_local(grid_pos)
	var target_local = to_local(target_world)
	
	beam_line.clear_points()
	beam_line.add_point(Vector2.ZERO) # Start at building center
	beam_line.add_point(target_local) # End at tree
