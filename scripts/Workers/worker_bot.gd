extends Node2D
class_name WorkerBot

signal clicked(bot: WorkerBot)
signal inventory_changed

# --- THE DISGUISE (Duck Typing) ---
var building_name: String = "Worker Bot"
var health: int = 100
var max_health: int = 100

# --- THE PRIORITY SYSTEM ---
enum TaskPriority { GATHER_WOOD, GATHER_STONE, STOPPED }
var current_priority: TaskPriority = TaskPriority.GATHER_WOOD

enum State { IDLE, MOVING_TO_RESOURCE, HARVESTING, MOVING_TO_INVENTORY, DEPOSITING, WAITING_FOR_STORAGE }
var current_state: State = State.IDLE

@export var speed: float = 75.0
@export var carry_capacity: int = 5
@export var harvest_time: float = 0.5

var carried_item_name: String = ""
var carried_amount: int = 0
var carried_item_res: Resource = null

var level_ref: Node2D
var target_tile: Vector2i = Vector2i(-1, -1)
var current_path: Array[Vector2] = []

@onready var action_timer = $ActionTimer

var unreachable_tiles: Array[Vector2i] = []
var full_storages_ignored: Array[Node2D] = []

func setup(level: Node2D):
	level_ref = level
	action_timer.timeout.connect(_on_action_timer_timeout)
	
	if has_node("Area2D"):
		$Area2D.input_event.connect(_on_input_event)

func _process(delta):
	queue_redraw()
	
	match current_state:
		State.IDLE:
			_find_nearest_resource()
			
		State.MOVING_TO_RESOURCE:
			_move_along_path(delta, State.HARVESTING)
			
		State.MOVING_TO_INVENTORY:
			_move_along_path(delta, State.DEPOSITING)

# ==========================================
# 1. BRAIN: DECISION MAKING
# ==========================================

func _find_nearest_resource():
	if current_priority == TaskPriority.STOPPED:
		return
	
	if carried_amount >= carry_capacity:
		_find_nearest_storage()
		return

	if not level_ref or level_ref.active_grid_objects.is_empty():
		return
		
	var my_grid_pos = level_ref.object_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF
	
	for tile in level_ref.active_grid_objects.keys():
		if unreachable_tiles.has(tile):
			continue
		
		var info = level_ref.active_grid_objects[tile]
		
		if info["health"] <= 0:
			continue
		
		var item_name = info["data"].item_drop.display_name
		
		# --- PRIORITY FILTER ---
		if current_priority == TaskPriority.GATHER_WOOD and item_name != "Wood":
			continue
		if current_priority == TaskPriority.GATHER_STONE and item_name != "Stone":
			continue

		# If hands are full, only look for the exact same item
		if carried_amount > 0 and item_name != carried_item_name:
			continue
			
		var dist = my_grid_pos.distance_squared_to(tile)
		if dist < min_dist:
			min_dist = dist
			best_tile = tile
				
	if best_tile != Vector2i(-1, -1):
		target_tile = best_tile
		current_state = State.MOVING_TO_RESOURCE
		_request_path(target_tile, false)
	else:
		if carried_amount > 0:
			_find_nearest_storage()
		else:
			current_state = State.IDLE

		
# ==========================================
# UNIVERSAL STORAGE SEARCH
# ==========================================
func _find_nearest_storage():
	if not level_ref or not level_ref.building_manager: return
	
	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF
	
	for b in level_ref.building_manager.buildings:
		
		if not (b.has_method("add_item") or b.has_method("add_bot_item")): continue
		
		if b in full_storages_ignored: continue
		
		if "is_dedicated_mode" in b and "selected_output_name" in b:
			if b.is_dedicated_mode and b.selected_output_name != "" and b.selected_output_name != carried_item_name:
				continue
		
		if b.occupied_tiles.size() > 0:
			var b_tile = b.occupied_tiles[0]
			var dist = my_pos.distance_squared_to(b_tile)
			if dist < min_dist:
				min_dist = dist
				best_tile = b_tile
				
	if best_tile != Vector2i(-1, -1):
		target_tile = best_tile
		_request_path(best_tile, true)
		current_state = State.MOVING_TO_INVENTORY
	else:
		# All storages are full — wait patiently
		current_state = State.WAITING_FOR_STORAGE
		action_timer.start(10.0)


# ==========================================
# 2. LEGS: MOVEMENT
# ==========================================

func _request_path(target_grid: Vector2i, is_core: bool = false):
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return
	
	var standing_tile = _get_standable_adjacent_tile(target_grid)
	
	if standing_tile == Vector2i(-1, -1):
		print("Bot: Target ", target_grid, " is completely blocked in!")
		if not is_core:
			unreachable_tiles.append(target_grid)
		current_state = State.IDLE
		return
		
	var target_local = level_ref.object_layer.map_to_local(standing_tile)
	var target_world = level_ref.object_layer.to_global(target_local)
	
	var packed_path = pathfinder.get_path_route(global_position, target_world)
	
	if packed_path.is_empty():
		print("Bot: Cannot find a route to adjacent tile ", standing_tile)
		if not is_core:
			unreachable_tiles.append(target_grid)
		current_state = State.IDLE
		return
		
	current_path.clear()
	current_path.append_array(packed_path)


func _move_along_path(delta: float, next_state: State):
	if current_path.is_empty():
		current_state = next_state
		_start_action()
		return
		
	var target_pos = current_path[0]
	var dist = global_position.distance_to(target_pos)
	var move_step = speed * delta
	
	if dist <= move_step:
		global_position = target_pos
		current_path.pop_front()
	else:
		global_position = global_position.move_toward(target_pos, move_step)

# ==========================================
# 3. HANDS: ACTIONS
# ==========================================

func _start_action():
	if current_state == State.HARVESTING:
		action_timer.start(harvest_time)
	elif current_state == State.DEPOSITING:
		action_timer.start(0.5)

func _on_action_timer_timeout():
	if current_state == State.HARVESTING:
		if level_ref.active_grid_objects.has(target_tile):
			var info = level_ref.active_grid_objects[target_tile]
			
			var harvested_amount = ResourceManager.request_harvest(target_tile, info, 1)
			
			if harvested_amount > 0:
				carried_item_res = info["data"].item_drop
				carried_item_name = carried_item_res.display_name
				carried_amount += harvested_amount
				inventory_changed.emit()
			
			if carried_amount >= carry_capacity:
				_find_nearest_storage()
			elif info["health"] <= 0:
				if carried_amount > 0:
					_find_nearest_storage()
				else:
					current_state = State.IDLE
			else:
				action_timer.start(harvest_time)
		else:
			if carried_amount > 0:
				_find_nearest_storage()
			else:
				current_state = State.IDLE

	elif current_state == State.DEPOSITING:
		if carried_amount > 0:
			var storage = null
			if level_ref.building_manager.occupied_tiles.has(target_tile):
				storage = level_ref.building_manager.occupied_tiles[target_tile]
				
			if storage:
				var amount_taken = 0
				
				if storage.has_method("add_bot_item"):
					amount_taken = storage.add_bot_item(carried_item_res, carried_amount)
				elif storage.has_method("add_item"):
					amount_taken = storage.add_item(carried_item_name, carried_amount)
					
				carried_amount -= amount_taken
				inventory_changed.emit()
				
				if carried_amount <= 0:
					carried_item_name = ""
					carried_item_res = null
					full_storages_ignored.clear()
					current_state = State.IDLE
				else:
					full_storages_ignored.append(storage)
					_find_nearest_storage()
			else:
				current_state = State.IDLE
		else:
			current_state = State.IDLE

	elif current_state == State.WAITING_FOR_STORAGE:
		full_storages_ignored.clear()
		current_state = State.IDLE


# ==========================================
# TILE MATH HELPERS
# ==========================================
func _get_standable_adjacent_tile(target_tile: Vector2i) -> Vector2i:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return Vector2i(-1, -1)
	
	var neighbors = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var best_stand = Vector2i(-1, -1)
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	var closest_dist = INF
	
	for offset in neighbors:
		var test_tile = target_tile + offset
		
		if pathfinder.astar.is_in_boundsv(test_tile) and not pathfinder.astar.is_point_solid(test_tile):
			var dist = my_grid.distance_squared_to(test_tile)
			if dist < closest_dist:
				closest_dist = dist
				best_stand = test_tile
				
	return best_stand


# ==========================================
# UI INTERACTION & PRIORITY LOGIC
# ==========================================

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		clicked.emit(self)

func set_priority(new_priority: int):
	if current_priority == new_priority: return
	
	current_priority = new_priority as TaskPriority
	
	# Void contraband items when switching priorities
	if carried_amount > 0:
		if current_priority == TaskPriority.GATHER_WOOD and carried_item_name != "Wood":
			print("Bot voided %d %s to switch to Wood!" % [carried_amount, carried_item_name])
			carried_amount = 0
			carried_item_name = ""
			carried_item_res = null
		elif current_priority == TaskPriority.GATHER_STONE and carried_item_name != "Stone":
			print("Bot voided %d %s to switch to Stone!" % [carried_amount, carried_item_name])
			carried_amount = 0
			carried_item_name = ""
			carried_item_res = null
	
	if current_priority == TaskPriority.STOPPED:
		target_tile = Vector2i(-1, -1)
		current_path.clear()
		action_timer.stop()
		current_state = State.IDLE
	else:
		if current_state == State.IDLE or current_state == State.MOVING_TO_RESOURCE:
			target_tile = Vector2i(-1, -1)
			current_path.clear()
			current_state = State.IDLE
			
	inventory_changed.emit()

func get_inventory_info() -> Dictionary:
	var p_name = "Wood Only"
	if current_priority == TaskPriority.GATHER_STONE: p_name = "Stone Only"
	elif current_priority == TaskPriority.STOPPED: p_name = "Halted"
	
	var carrying_text = "Empty"
	if carried_amount > 0:
		carrying_text = "%s (%d)" % [carried_item_name, carried_amount]
	
	return { "Target": p_name, "Carrying": carrying_text }

	
# ==========================================
# DEBUG VISUALS
# ==========================================

func _draw():
	if current_path.size() > 0:
		var points = PackedVector2Array()
		points.append(Vector2.ZERO)
		
		for p in current_path:
			points.append(to_local(p))
			
		if points.size() > 1:
			draw_polyline(points, Color(0.2, 0.8, 1.0, 0.8), 2.0)
			draw_circle(to_local(current_path[-1]), 4.0, Color(1.0, 0.2, 0.2))

	if target_tile != Vector2i(-1, -1) and (current_state == State.MOVING_TO_RESOURCE or current_state == State.HARVESTING):
		if level_ref and level_ref.object_layer:
			var target_local_map = level_ref.object_layer.map_to_local(target_tile)
			var target_global = level_ref.object_layer.to_global(target_local_map)
			var target_local_to_bot = to_local(target_global)
			var rect = Rect2(target_local_to_bot - Vector2(16, 16), Vector2(32, 32))
			draw_rect(rect, Color(1.0, 0.2, 0.2, 0.8), false, 2.0)
