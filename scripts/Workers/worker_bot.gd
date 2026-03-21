extends Node2D
class_name WorkerBot

signal clicked(bot: WorkerBot)
signal inventory_changed

# --- THE DISGUISE (Duck Typing) ---
var building_name: String = "Worker Bot"
var health: int = 100
var max_health: int = 100

# --- THE PRIORITY SYSTEM ---
enum TaskPriority { GATHER_WOOD, GATHER_STONE, REPAIR, BUILD, STOPPED }
var current_priority: TaskPriority = TaskPriority.GATHER_WOOD

enum State { 
	IDLE, 
	MOVING_TO_RESOURCE, HARVESTING, 
	MOVING_TO_INVENTORY, DEPOSITING, 
	ON_STANDBY, 
	MOVING_TO_REPAIR, REPAIRING, 
	MOVING_TO_BUILD, BUILDING,
	MOVING_TO_FETCH, FETCHING 
}
var current_state: State = State.IDLE

@export var speed: float = 75.0
@export var carry_capacity: int = 5
@export var harvest_time: float = 1

var carried_item_name: String = ""
var carried_amount: int = 0
var carried_item_res: Resource = null

var level_ref: Node2D
var target_tile: Vector2i = Vector2i(-1, -1)
var current_path: Array[Vector2] = []

@onready var action_timer = $ActionTimer

var unreachable_tiles: Array[Vector2i] = []
var full_storages_ignored: Array[Node2D] = []
var unreachable_storages: Array[Node2D] = [] # NEW: Pathfinding blacklist for storages

func setup(level: Node2D):
	level_ref = level
	action_timer.timeout.connect(_on_action_timer_timeout)
	
	if has_node("Area2D"):
		$Area2D.input_event.connect(_on_input_event)

func _process(delta):
	queue_redraw()
	
	match current_state:
		State.IDLE:
			if current_priority == TaskPriority.REPAIR:
				_find_damaged_building()
			elif current_priority == TaskPriority.BUILD:
				_find_construction_site()
			else:
				_find_nearest_resource()
			
		State.MOVING_TO_RESOURCE:
			_move_along_path(delta, State.HARVESTING)
			
		State.MOVING_TO_INVENTORY:
			_move_along_path(delta, State.DEPOSITING)
		State.MOVING_TO_REPAIR:
			_move_along_path(delta, State.REPAIRING)
		State.MOVING_TO_BUILD:
			_move_along_path(delta, State.BUILDING)
		State.MOVING_TO_FETCH:
			_move_along_path(delta, State.FETCHING)

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
		
	# --- NEW: Drop our old claim before searching for a new one! ---
	_clear_reservation() 
		
	var my_grid_pos = level_ref.object_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF
	
	for tile in level_ref.active_grid_objects.keys():
		if unreachable_tiles.has(tile):
			continue
		
		var info = level_ref.active_grid_objects[tile]
		
		if info["health"] <= 0:
			continue
			
		# --- NEW: THE "DIBS" CHECK ---
		# If someone else has claimed this tile, and that someone is still alive, skip it!
		if info.has("reserved_by") and is_instance_valid(info["reserved_by"]) and info["reserved_by"] != self:
			continue 
		# -----------------------------
		
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
		
		# --- NEW: CLAIM THE TILE ---
		level_ref.active_grid_objects[best_tile]["reserved_by"] = self
		# ---------------------------
		
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
	_clear_reservation()
	
	if not level_ref or not level_ref.building_manager: return
	
	var my_pos = level_ref.terrain_layer.local_to_map(global_position)

	# Build a sorted list of candidates, then try each until one paths successfully.
	var candidates: Array = []

	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		if b is ConstructionSite: 
			continue
		if not b.has_method("add_item"): continue
		if b in full_storages_ignored: continue
		if b in unreachable_storages: continue  # NEW: skip known blocked storages

		if "is_dedicated_mode" in b and "selected_output_name" in b:
			if b.is_dedicated_mode and b.selected_output_name != "" and b.selected_output_name != carried_item_name:
				continue

		if b.occupied_tiles.size() > 0:
			var b_tile = b.occupied_tiles[0]
			var dist = my_pos.distance_squared_to(b_tile)
			candidates.append({ "building": b, "tile": b_tile, "dist": dist })

	# Sort closest first
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])

	# Try each candidate until one has a valid path
	for candidate in candidates:
		var b_tile = candidate["tile"]
		var b_node = candidate["building"]

		_request_path(b_tile, true)

		if not current_path.is_empty():
			# Valid path found!
			target_tile = b_tile
			current_state = State.MOVING_TO_INVENTORY
			return
		else:
			# Path failed — blacklist this storage until we reset
			print("Bot: Storage at %s is unreachable, blacklisting." % b_tile)
			unreachable_storages.append(b_node)

	# Every storage is either full, filtered, or unreachable
	current_state = State.ON_STANDBY
	action_timer.start(5.0)

# ==========================================
# REPAIR SEARCH
# ==========================================
func _find_damaged_building():
	_clear_reservation()
	if current_priority == TaskPriority.STOPPED: return
	if not level_ref or not level_ref.building_manager: return

	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF

	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		# 1. Duck-type: Does this object even have health?
		if "health" in b and "max_health" in b:
			# 2. Is it damaged?
			if b.health < b.max_health:
				if b.occupied_tiles.size() > 0:
					var b_tile = b.occupied_tiles[0]
					var dist = my_pos.distance_squared_to(b_tile)
					if dist < min_dist:
						min_dist = dist
						best_tile = b_tile

	if best_tile != Vector2i(-1, -1):
		target_tile = best_tile
		_request_path(best_tile, true) # Treat as building for pathing
		
		# Prevent telepathy bug!
		if not current_path.is_empty():
			current_state = State.MOVING_TO_REPAIR
		else:
			current_state = State.IDLE 
	else:
		# Base is completely healthy! Wait 2 seconds and check again.
		current_state = State.ON_STANDBY
		action_timer.start(5.0)

func _find_construction_site():
	_clear_reservation()
	if not level_ref or not level_ref.building_manager: return

	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF
	
	# We need to remember what building we pick, so we know what to fetch
	var target_blueprint: ConstructionSite = null

	# 1. FIND A BLUEPRINT
	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
			
		if b is ConstructionSite:
			# CASE A: Hands are empty, and it needs materials!
			if carried_amount == 0 and not b.is_ready_to_build:
				var b_tile = b.occupied_tiles[0]
				var dist = my_pos.distance_squared_to(b_tile)
				if dist < min_dist:
					min_dist = dist
					best_tile = b_tile
					target_blueprint = b
					
			# CASE B: Hands are full, and it needs the exact item we are holding!
			elif carried_amount > 0 and not b.is_ready_to_build:
				if b.required_items.has(carried_item_name):
					var needed = b.required_items[carried_item_name]
					var have = b.delivered_items.get(carried_item_name, 0)
					if have < needed: # It actually needs the item in our hands!
						var b_tile = b.occupied_tiles[0]
						var dist = my_pos.distance_squared_to(b_tile)
						if dist < min_dist:
							min_dist = dist
							best_tile = b_tile
							target_blueprint = b
							
			# CASE C: Hands are empty, materials are delivered, ready to hammer!
			elif carried_amount == 0 and b.is_ready_to_build:
				var b_tile = b.occupied_tiles[0]
				var dist = my_pos.distance_squared_to(b_tile)
				if dist < min_dist:
					min_dist = dist
					best_tile = b_tile
					target_blueprint = b

	if best_tile != Vector2i(-1, -1) and target_blueprint != null:
		
		# If our hands are full, or the blueprint is ready to be hammered, walk to the blueprint!
		if carried_amount > 0 or target_blueprint.is_ready_to_build:
			target_tile = best_tile
			_request_path(best_tile, true)
			if not current_path.is_empty():
				# Are we dropping off items, or swinging the hammer?
				current_state = State.MOVING_TO_INVENTORY if carried_amount > 0 else State.MOVING_TO_BUILD
			else:
				current_state = State.IDLE 
				
		# If our hands are empty, and it needs items, we must FETCH!
		else:
			# Look at what the blueprint is missing
			var item_to_fetch = ""
			for req_name in target_blueprint.required_items.keys():
				var needed = target_blueprint.required_items[req_name]
				var have = target_blueprint.delivered_items.get(req_name, 0)
				if have < needed:
					item_to_fetch = req_name
					break # Found something it needs!
					
			if item_to_fetch != "":
				_find_stockpile_with_item(item_to_fetch)
			else:
				current_state = State.IDLE

	else:
		# --- THE FIX: DUMP LEFTOVER INVENTORY ---
		if carried_amount > 0:
			# We are holding useless materials! Go put them back in the box.
			_find_nearest_storage()
		else:
			# Hands are completely empty and no sites need building. Rest.
			current_state = State.ON_STANDBY
			action_timer.start(2.0)

func _find_stockpile_with_item(item_name: String):
	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF

	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		
		var has_item = false
		
		# --- CASE 1: Normal Stockpiles (Uses ItemResource keys) ---
		if "inventory" in b and typeof(b.inventory) == TYPE_DICTIONARY:
			for key in b.inventory.keys():
				if key is ItemResource and key.display_name == item_name:
					# Ensure the value is actually an int/float before checking > 0
					var amount = b.inventory[key]
					if typeof(amount) in [TYPE_INT, TYPE_FLOAT] and amount > 0:
						has_item = true
						break
		
		# --- CASE 2: Core Building (Uses String keys) ---
		# If your core tracks inventory differently, you can check it here!
		elif b is CoreBuilding and b.has_method("get_economy_assets"):
			var assets = b.get_economy_assets()
			if assets.has(item_name) and assets[item_name] > 0:
				has_item = true

		if has_item:
			var b_tile = b.occupied_tiles[0]
			var dist = my_pos.distance_squared_to(b_tile)
			if dist < min_dist:
				min_dist = dist
				best_tile = b_tile
					
	if best_tile != Vector2i(-1, -1):
		# We found a stockpile! Walk to it and FETCH.
		carried_item_name = item_name # Memorize what we are supposed to grab
		target_tile = best_tile
		_request_path(best_tile, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_FETCH
		else:
			current_state = State.IDLE
	else:
		# No stockpile has the item! We are stuck waiting.
		print("Builder Bot: No stockpiles have ", item_name, "!")
		current_state = State.ON_STANDBY
		action_timer.start(2.0)

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
	elif current_state == State.REPAIRING:
		action_timer.start(1.0)
	elif current_state == State.BUILDING:
		action_timer.start(1.0)
	elif current_state == State.FETCHING: 
		action_timer.start(1.0)
		
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

	elif current_state == State.FETCHING:
		var storage = null
		if level_ref.building_manager.occupied_tiles.has(target_tile):
			storage = level_ref.building_manager.occupied_tiles[target_tile]
			
		# Check if the building has our new pulling function
		if storage and storage.has_method("take_item"):
			# Attempt to pull the item we memorized!
			var result = storage.take_item(carried_item_name, carry_capacity)
			
			if result.get("amount", 0) > 0:
				carried_amount = result["amount"]
				carried_item_res = result["resource"] # We need the Resource to deposit it later!
				inventory_changed.emit()
				
				# Go back to IDLE. Next frame, the Brain will see our hands 
				# are full and instantly route us to the blueprint!
				current_state = State.IDLE 
			else:
				# Another bot took the last item before we got here!
				carried_item_name = ""
				current_state = State.IDLE
		else:
			carried_item_name = ""
			current_state = State.IDLE

	elif current_state == State.DEPOSITING:
		if carried_amount > 0:
			var storage = null
			if level_ref.building_manager.occupied_tiles.has(target_tile):
				storage = level_ref.building_manager.occupied_tiles[target_tile]
				
			if storage and storage.has_method("add_item"):
				var amount_taken = storage.add_item(carried_item_res, carried_amount)
				carried_amount -= amount_taken
				inventory_changed.emit()
				
				if carried_amount <= 0:
					carried_item_name = ""
					carried_item_res = null
					full_storages_ignored.clear()
					unreachable_storages.clear() # NEW: Walls may have changed, reset on success
					current_state = State.IDLE
				else:
					full_storages_ignored.append(storage)
					_find_nearest_storage()
			else:
				current_state = State.IDLE
		else:
			current_state = State.IDLE


	elif current_state == State.REPAIRING:
		var building = null
		if level_ref.building_manager.occupied_tiles.has(target_tile):
			building = level_ref.building_manager.occupied_tiles[target_tile]
			
		# Make sure it still exists and has health variables
		if building and "health" in building and "max_health" in building:
			if building.health < building.max_health:
				
				# Heal it by 5 HP per swing (Adjust this number to balance your game!)
				building.health += 5 
				
				# Cap it so we don't accidentally give a wall 105/100 HP
				if building.health > building.max_health:
					building.health = building.max_health
					
				# (Optional) If your building script has a function to update its health bar, call it here!
				if building.has_method("update_health_ui"):
					building.update_health_ui()
					
				# Are we done repairing?
				if building.health >= building.max_health:
					current_state = State.IDLE # Find the next broken building!
				else:
					action_timer.start(1.0) # Keep hammering!
			else:
				current_state = State.IDLE # It's fully healed
		else:
			current_state = State.IDLE # Building was destroyed before we could fix it
	
	# (Inside your action timer, right next to the REPAIRING block)
	elif current_state == State.BUILDING:
		var building = null
		if level_ref.building_manager.occupied_tiles.has(target_tile):
			building = level_ref.building_manager.occupied_tiles[target_tile]
			
		# Make sure it's a blueprint and it still exists
		if building and building is ConstructionSite:
			# Hit it with the hammer for 10 progress!
			building.add_build_progress(10)
			
			# If the building swapped itself out, the old reference is queued for deletion
			if not is_instance_valid(building) or building.is_queued_for_deletion():
				current_state = State.IDLE # It finished building!
			else:
				action_timer.start(1.0) # Keep hammering!
		else:
			current_state = State.IDLE
			
	elif current_state == State.ON_STANDBY:
		# Timer expired — wipe all blacklists and try again fresh
		full_storages_ignored.clear()
		unreachable_storages.clear() # NEW: Maybe a wall was removed!
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
	_clear_reservation()
	
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
	elif current_priority == TaskPriority.REPAIR: p_name = "Repair Duty"
	elif current_priority == TaskPriority.BUILD: p_name = "Build Duty"
	elif current_priority == TaskPriority.STOPPED: p_name = "Halted"
	
	var carrying_text = "Empty"
	if carried_amount > 0:
		carrying_text = "%s (%d)" % [carried_item_name, carried_amount]
	
	return { "Target": p_name, "Carrying": carrying_text }


# ==========================================
# RESERVATION SYSTEM
# ==========================================
func _clear_reservation():
	# If we currently have a target, and it's a natural resource (not a building)...
	if target_tile != Vector2i(-1, -1) and level_ref and level_ref.active_grid_objects.has(target_tile):
		var info = level_ref.active_grid_objects[target_tile]
		
		# If we are the ones who claimed it, remove our claim!
		if info.has("reserved_by") and info["reserved_by"] == self:
			info["reserved_by"] = null

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
	
	# --- NEW: Action Progress Bar ---
	# 1. Define the states where the bot is standing still and actively working
	var active_states = [State.HARVESTING, State.DEPOSITING, State.REPAIRING, State.ON_STANDBY, State.BUILDING, State.FETCHING]
	
	# 2. Only draw the bar if we are in a working state AND the timer is ticking
	if current_state in active_states and not action_timer.is_stopped() and action_timer.wait_time > 0:
		
		# Calculate how far along the timer is (0.0 to 1.0)
		var progress = 1.0 - (action_timer.time_left / action_timer.wait_time)
		
		# Setup dimensions
		var bar_width = 24.0
		var bar_height = 4.0
		var bar_pos = Vector2(-bar_width / 2.0, -24.0) 
		
		var bg_rect = Rect2(bar_pos, Vector2(bar_width, bar_height))
		var fg_rect = Rect2(bar_pos, Vector2(bar_width * progress, bar_height))
		
		# Color-code the bar
		var fill_color = Color(0.2, 0.8, 0.2) # Default Green (Harvesting/Depositing)
		if current_state == State.REPAIRING:
			fill_color = Color(0.2, 0.6, 1.0) # Blue for Repairs
		elif current_state == State.BUILDING:
			fill_color = Color(0.524, 0.004, 0.953, 1.0)  #Purple for building
		elif current_state == State.FETCHING:
			fill_color = Color(0.0, 0.8, 0.8) #Cyan for fetching
		elif current_state == State.ON_STANDBY:
			fill_color = Color(1.0, 1.0, 1.0, 1.0) # White for the wait penalty
			
		# Draw the rectangles
		draw_rect(bg_rect, Color(0.1, 0.1, 0.1, 0.8), true)
		draw_rect(fg_rect, fill_color, true)
		draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 1.0), false, 1.0)
