extends Node2D
class_name WorkerBot

signal clicked(bot: WorkerBot)
signal inventory_changed # <--- NEW: Tells the UI to update!

# --- THE DISGUISE (Duck Typing) ---
# Your UI looks for these variables, so the bot must have them!
var building_name: String = "Worker Bot"
var health: int = 100
var max_health: int = 100

# --- THE PRIORITY SYSTEM ---
enum TaskPriority { GATHER_ALL, GATHER_WOOD, GATHER_STONE, STOPPED }
var current_priority: TaskPriority = TaskPriority.GATHER_ALL

enum State { IDLE, MOVING_TO_RESOURCE, HARVESTING, MOVING_TO_CORE, DEPOSITING }
var current_state: State = State.IDLE

@export var speed: float = 75.0
@export var carry_capacity: int = 5
@export var harvest_time: float = 0.5 # How fast they swing their axe

var carried_item_name: String = ""
var carried_amount: int = 0

var level_ref: Node2D
var target_tile: Vector2i = Vector2i(-1, -1)
var current_path: Array[Vector2] = []

@onready var action_timer = $ActionTimer

var unreachable_tiles: Array[Vector2i] = []

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
			
		State.MOVING_TO_CORE:
			_move_along_path(delta, State.DEPOSITING)

# ==========================================
# 1. BRAIN: DECISION MAKING
# ==========================================

func _find_nearest_resource():
	# --- NEW: Check if we are allowed to work! ---
	if current_priority == TaskPriority.STOPPED:
		return # Do absolutely nothing. Just stand there!
	# ---------------------------------------------
	
	if not level_ref or level_ref.active_grid_objects.is_empty():
		return 
		
	var my_grid_pos = level_ref.object_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF
	
	for tile in level_ref.active_grid_objects.keys():
		# --- NEW: Skip trees we already know we can't reach! ---
		if unreachable_tiles.has(tile):
			continue
		
		
			
		var info = level_ref.active_grid_objects[tile]
		
		# --- THE FIX: Ignore dead trees and rocks! ---
		if info["health"] <= 0:
			continue
		# ---------------------------------------------
		
		var item_name = info["data"].item_drop.display_name
			
		# --- THE PRIORITY FILTER ---
		if current_priority == TaskPriority.GATHER_WOOD and item_name != "Wood":
			continue # Ignore stones
		if current_priority == TaskPriority.GATHER_STONE and item_name != "Stone":
			continue # Ignore trees
		# ---------------------------
		
		# --- THE FIX: Stop mixing items! ---
		# If my hands are full, ONLY look for the exact same item!
		if carried_amount > 0 and item_name != carried_item_name:
			continue
		# -----------------------------------
			
		var dist = my_grid_pos.distance_squared_to(tile)
		if dist < min_dist:
			min_dist = dist
			best_tile = tile
				
	if best_tile != Vector2i(-1, -1):
		target_tile = best_tile
		current_state = State.MOVING_TO_RESOURCE
		_request_path(target_tile, false) # Pass 'false' because it's a resource
	else:
		pass # No reachable resources left!
		
		
func _find_core():
	var core = _get_core_building()
	if core:
		# Pathfind to the tile right next to the core
		_request_path(core.grid_origin) 
		current_state = State.MOVING_TO_CORE
	else:
		current_state = State.IDLE # Core is dead or missing!

# ==========================================
# 2. LEGS: MOVEMENT
# ==========================================

func _request_path(target_grid: Vector2i, is_core: bool = false):
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return
	
	# 1. Find an empty tile to stand on NEXT to the tree/core
	var standing_tile = _get_standable_adjacent_tile(target_grid)
	
	if standing_tile == Vector2i(-1, -1):
		print("Bot: Target ", target_grid, " is completely blocked in!")
		if not is_core:
			unreachable_tiles.append(target_grid) # Blacklist the tree
		current_state = State.IDLE
		return
		
	# 2. Pathfind to the EMPTY standing tile
	var target_local = level_ref.object_layer.map_to_local(standing_tile)
	var target_world = level_ref.object_layer.to_global(target_local)
	
	var packed_path = pathfinder.get_path_route(global_position, target_world)
	
	# 3. Check if the path is possible
	if packed_path.is_empty():
		print("Bot: Cannot find a route to adjacent tile ", standing_tile)
		if not is_core:
			unreachable_tiles.append(target_grid) # Blacklist the tree
		current_state = State.IDLE
		return
		
	# 4. Save the path and walk!
	current_path.clear()
	current_path.append_array(packed_path)
	
	# NOTE: We removed pop_back()! The bot will walk all the way onto the standing_tile.


func _move_along_path(delta: float, next_state: State):
	if current_path.is_empty():
		# We reached the destination!
		current_state = next_state
		_start_action()
		return
		
	var target_pos = current_path[0]
	var dist = global_position.distance_to(target_pos)
	var move_step = speed * delta
	
	if dist <= move_step:
		global_position = target_pos
		current_path.pop_front() # Reached this waypoint, go to the next!
	else:
		global_position = global_position.move_toward(target_pos, move_step)

# ==========================================
# 3. HANDS: ACTIONS
# ==========================================

func _start_action():
	if current_state == State.HARVESTING:
		action_timer.start(harvest_time)
	elif current_state == State.DEPOSITING:
		action_timer.start(0.5) # Quick half-second dropoff animation

func _on_action_timer_timeout():
	if current_state == State.HARVESTING:
		if level_ref.active_grid_objects.has(target_tile):
			var info = level_ref.active_grid_objects[target_tile]
			
			# --- THE ELEGANT FIX ---
			# Ask the manager for 1 item, and save whatever it gives us
			var harvested_amount = ResourceManager.request_harvest(target_tile, info, 1)
			
			# If we got anything, add it to our pockets!
			if harvested_amount > 0:
				carried_item_name = info["data"].item_drop.display_name
				carried_amount += harvested_amount
				inventory_changed.emit()
				#print_debug("Bot mined %s" % [carried_item_name])
			# -----------------------ds
			
			# --- THE LOGIC FIX ---
			if carried_amount >= carry_capacity:
				_find_core() # Pockets are full, go home!
			elif info["health"] <= 0:
				# Tree is dead! Do we have anything to drop off?
				if carried_amount > 0:
					_find_core() 
				else:
					current_state = State.IDLE # Pockets are empty! Find a new tree right now!
			else:
				action_timer.start(harvest_time) # Keep chopping!
			# ---------------------
		else:
			if carried_amount > 0:
				_find_core()
			else:
				current_state = State.IDLE

	elif current_state == State.DEPOSITING:
		if carried_amount > 0:
			var core = _get_core_building()
			
			if core and core.has_method("add_item"):
				# Try to dump the inventory
				var amount_taken = core.add_item(carried_item_name, carried_amount)
				
				# Subtract whatever the Core actually took
				carried_amount -= amount_taken
				inventory_changed.emit()
				
				if carried_amount <= 0:
					# Pocket empty! Go back to work.
					carried_item_name = ""
					current_state = State.IDLE 
				else:
					# Pocket still has items? The Core must be full!
					# Stay in DEPOSITING state and check again in 2 seconds.
					action_timer.start(2.0)
			else:
				current_state = State.IDLE # Core is missing, abort.
		else:
			# If a bot somehow ends up at the Core empty-handed, send it back to work!
			current_state = State.IDLE

# Helper to find the Core Building
func _get_core_building() -> Building:
	for b in level_ref.building_manager.buildings:
		if b is CoreBuilding: # Assuming you named the class CoreBuilding!
			return b
	return null
	
	
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
		
		# Is this neighbor inside the map AND completely empty?
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
	# Did the player Left-Click the bot?
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("Bot Clicked")
		
		# CRITICAL: This destroys the click event so it doesn't fall 
		# through and hit the grass tile underneath the bot!
		get_viewport().set_input_as_handled() 
		
		clicked.emit(self)

# --- NEW: DIRECT COMMAND FUNCTION ---
func set_priority(new_priority: int):
	# Don't do anything if they click the button we are already doing
	if current_priority == new_priority: return 
	
	current_priority = new_priority as TaskPriority
	
	# --- Contraband Check (Voiding wrong items) ---
	if carried_amount > 0:
		if current_priority == TaskPriority.GATHER_WOOD and carried_item_name != "Wood":
			print("Bot voided %d %s to switch to Wood!" % [carried_amount, carried_item_name])
			carried_amount = 0
			carried_item_name = ""
		elif current_priority == TaskPriority.GATHER_STONE and carried_item_name != "Stone":
			print("Bot voided %d %s to switch to Stone!" % [carried_amount, carried_item_name])
			carried_amount = 0
			carried_item_name = ""
			
	
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

# The UI panel will call this to populate its text box!
func get_inventory_info() -> Dictionary:
	var p_name = "All"
	if current_priority == TaskPriority.GATHER_WOOD: p_name = "Wood Only"
	elif current_priority == TaskPriority.GATHER_STONE: p_name = "Stone Only"
	# --- NEW: Tell the UI what to print! ---
	elif current_priority == TaskPriority.STOPPED: p_name = "Halted" 
	
	var carrying_text = "Empty"
	if carried_amount > 0:
		carrying_text = "%s (%d)" % [carried_item_name, carried_amount]
	
	return { "Target": p_name, "Carrying": carrying_text }
	
# ==========================================
# DEBUG VISUALS
# ==========================================

func _draw():
	# 1. Draw the Path Line
	if current_path.size() > 0:
		var points = PackedVector2Array()
		points.append(Vector2.ZERO) # Start at the bot's feet
		
		for p in current_path:
			points.append(to_local(p)) 
			
		if points.size() > 1:
			draw_polyline(points, Color(0.2, 0.8, 1.0, 0.8), 2.0)
			draw_circle(to_local(current_path[-1]), 4.0, Color(1.0, 0.2, 0.2))

	# --- NEW: Draw the Target Box ---
	# Only draw the red box if the bot is actively hunting or chopping a resource
	if target_tile != Vector2i(-1, -1) and (current_state == State.MOVING_TO_RESOURCE or current_state == State.HARVESTING):
		if level_ref and level_ref.object_layer:
			
			# A. Convert Grid to Global Pixels
			var target_local_map = level_ref.object_layer.map_to_local(target_tile)
			var target_global = level_ref.object_layer.to_global(target_local_map)
			
			# B. Convert Global Pixels to Bot's Local Pixels
			var target_local_to_bot = to_local(target_global)
			
			# C. Draw a 32x32 hollow square (offset by 16 so it centers on the tile)
			var rect = Rect2(target_local_to_bot - Vector2(16, 16), Vector2(32, 32))
			
			# draw_rect(Rect, Color, filled(bool), line_width)
			draw_rect(rect, Color(1.0, 0.2, 0.2, 0.8), false, 2.0)
