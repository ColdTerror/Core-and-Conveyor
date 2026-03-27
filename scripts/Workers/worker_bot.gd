extends Node2D
class_name WorkerBot

signal clicked(bot: WorkerBot)
signal inventory_changed

signal hovered(bot: WorkerBot) 
signal unhovered(bot: WorkerBot)

# --- THE DISGUISE (Duck Typing) ---
var building_name: String = "Worker Bot"
var health: int = 100
var max_health: int = 100

# --- THE PRIORITY SYSTEM ---
enum TaskPriority { GATHER_WOOD, GATHER_STONE, MAINTAIN, STOPPED }
var current_priority: TaskPriority = TaskPriority.STOPPED

enum State { 
	IDLE, 
	MOVING_TO_RESOURCE, HARVESTING, 
	MOVING_TO_INVENTORY, DEPOSITING, 
	ON_STANDBY, 
	MOVING_TO_REPAIR, REPAIRING, 
	MOVING_TO_BUILD, BUILDING,
	MOVING_TO_FETCH, FETCHING,
	MOVING_HOME, RECHARGING
}
var current_state: State = State.IDLE

var home_tile: Vector2i = Vector2i(-1, -1)
var is_selected: bool = false

# --- ENERGY SYSTEM ---
@export var max_energy: float = 100.0
var current_energy: float = 100.0
@export var energy_drain_rate: float = 2.0 # Loses 2 energy per second while working
@export var energy_recharge_rate: float = 25.0 # Gains 25 energy per second at home
var is_limping: bool = false

@export var base_speed: float = 75.0

var current_speed: float
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
		$Area2D.mouse_entered.connect(_on_mouse_entered)
		$Area2D.mouse_exited.connect(_on_mouse_exited)
		
	if level_ref and level_ref.object_layer:
		# Figure out what tile we are standing on right now
		home_tile = level_ref.object_layer.local_to_map(global_position)

func _ready():
	current_speed = base_speed
	# 1. Join the group so the Manager can find us when an upgrade finishes
	add_to_group("WorkerBots")
	
	# 2. Apply buffs IMMEDIATELY on spawn, so new bots get the current upgrades!
	apply_research_buffs()

func apply_research_buffs():
	# Calculate our new speed based on the global multiplier
	current_speed = base_speed * ResearchManager.bot_speed_mult
	
	# If you have an inventory capacity variable, update it here too!
	# max_carry_amount = ResearchManager.bot_carry_capacity

func _process(delta):
	queue_redraw()
	
	_handle_energy(delta)
	
	match current_state:
		State.IDLE:
			if _escape_trapped_tile():
				return # Skip this frame so the new safe position registers!
			
			if current_priority == TaskPriority.STOPPED:
				_go_home_or_standby(1.0)
				return
			if current_priority == TaskPriority.MAINTAIN:
				_find_priority_job()
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
		State.MOVING_HOME:
			if is_limping:
				_move_along_path(delta, State.RECHARGING)
			else:
				_move_along_path(delta, State.IDLE)
		State.RECHARGING:
			pass

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
			
		# --- THE UPGRADED TURF CHECK ---
		# If 1 or more Harvesters claim this tile, leave it for the machines!
		if info.get("harvester_claim_count", 0) > 0:
			continue
		# -------------------------------
		
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
		_request_path([best_tile], false) # Wrap single resource in array!
		
		if not current_path.is_empty():
			level_ref.active_grid_objects[target_tile]["reserved_by"] = self
			current_state = State.MOVING_TO_RESOURCE
		else:
			current_state = State.IDLE
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
		var b_node = candidate["building"]

		_request_path(b_node.occupied_tiles, true) # Pass the full array!

		if not current_path.is_empty():
			current_state = State.MOVING_TO_INVENTORY
			return
		else:
			print("Bot: Storage unreachable, blacklisting.")
			unreachable_storages.append(b_node)

	# Every storage is either full, filtered, or unreachable
	_go_home_or_standby(5.0)

# ==========================================
# UNIFIED PRIORITY SEARCH
# ==========================================
func _find_priority_job():
	_clear_reservation()
	if not level_ref or not level_ref.building_manager: return

	# 1. Ask the Boss for the most important task!
	var best_job = level_ref.building_manager.get_highest_priority_job(global_position)

	# 2. IF NO JOBS EXIST
	if best_job == null:
		if carried_amount > 0:
			_find_nearest_storage() # Put away whatever we are holding
		else:
			_go_home_or_standby(2.0) # Rest
		return

	# 3. WE HAVE A JOB! Are we holding the WRONG item for it?
	if carried_amount > 0:
		var holding_wrong_item = true
		
		# Only blueprints accept deliveries. Repairs don't need items in hands.
		if best_job is ConstructionSite and not best_job.is_ready_to_build:
			if best_job.required_items.has(carried_item_name):
				var needed = best_job.required_items[carried_item_name]
				var have = best_job.delivered_items.get(carried_item_name, 0)
				if have < needed:
					holding_wrong_item = false # We are holding exactly what it needs!
					
		if holding_wrong_item:
			_find_nearest_storage() # Go put the wrong item away first!
			return

	# 4. EXECUTE THE JOB
	if best_job is ConstructionSite:
		if carried_amount > 0:
			# Hands are full of the right material -> Deliver it!
			_request_path(best_job.occupied_tiles, true)
			if not current_path.is_empty():
				current_state = State.MOVING_TO_INVENTORY 
			else:
				current_state = State.IDLE
				
		elif not best_job.is_ready_to_build:
			# Blueprint needs items, hands are empty -> Fetch!
			var item_to_fetch = ""
			for req_name in best_job.required_items.keys():
				var needed = best_job.required_items[req_name]
				var have = best_job.delivered_items.get(req_name, 0)
				if have < needed:
					item_to_fetch = req_name
					break
					
			if item_to_fetch != "":
				_find_stockpile_with_item(item_to_fetch)
			else:
				current_state = State.IDLE
				
		else:
			# Fully stocked -> Hammer it!
			_request_path(best_job.occupied_tiles, true)
			if not current_path.is_empty():
				current_state = State.MOVING_TO_BUILD
			else:
				current_state = State.IDLE
				
	else:
		# It's a standard damaged building -> Repair it!
		_request_path(best_job.occupied_tiles, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_REPAIR
		else:
			current_state = State.IDLE

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
		carried_item_name = item_name 
		
		var stockpile = level_ref.building_manager.occupied_tiles[best_tile]
		_request_path(stockpile.occupied_tiles, true) # Pass the array!
		
		if not current_path.is_empty():
			current_state = State.MOVING_TO_FETCH
		else:
			current_state = State.IDLE
	else:
		# No stockpile has the item! We are stuck waiting.
		print("Builder Bot: No stockpiles have ", item_name, "!")
		_go_home_or_standby(2.0)

func _handle_energy(delta: float):
	# 1. RECHARGING LOGIC
	if current_state == State.RECHARGING:
		current_energy += energy_recharge_rate * delta
		if current_energy >= max_energy:
			current_energy = max_energy
			is_limping = false
			
			# Restore normal speed (Re-apply any research buffs!)
			current_speed = base_speed 
			if ResearchManager.bot_speed_mult:
				current_speed *= ResearchManager.bot_speed_mult
				
			current_state = State.IDLE # Wake up and find a job!
		return

	# 2. DRAINING LOGIC (Only drain if actively moving or working)
	var active_states = [
		State.MOVING_TO_RESOURCE, State.HARVESTING, 
		State.MOVING_TO_INVENTORY, State.DEPOSITING, 
		State.MOVING_TO_REPAIR, State.REPAIRING, 
		State.MOVING_TO_BUILD, State.BUILDING, 
		State.MOVING_TO_FETCH, State.FETCHING
	]
	
	if current_state in active_states:
		current_energy -= energy_drain_rate * delta
		
		# 3. EXHAUSTION TRIGGER
		if current_energy <= 0 and not is_limping:
			current_energy = 0
			is_limping = true
			current_speed = base_speed * 0.4 # Slow down to 40% speed!
			
			print("Bot exhausted! Limping home.")
			
			# Drop current task and wipe the path
			_clear_reservation()
			action_timer.stop()
			target_tile = Vector2i(-1, -1)
			
			# Try to go home
			if home_tile != Vector2i(-1, -1):
				if _request_path_exact(home_tile):
					current_state = State.MOVING_HOME
				else:
					# Path is blocked! Fall asleep on the floor.
					current_state = State.RECHARGING 
			else:
				# No home assigned! Fall asleep on the floor.
				current_state = State.RECHARGING

# ==========================================
# 2. LEGS: MOVEMENT
# ==========================================

func _request_path(target_tiles: Array, is_building: bool = false):
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return
	
	var result = _get_standable_adjacent_tile(target_tiles)
	var standing_tile = result["stand"]
	var interaction_tile = result["target"]
	
	if standing_tile == Vector2i(-1, -1):
		print("Bot: Target footprint is completely blocked in!")
		if not is_building:
			unreachable_tiles.append(target_tiles[0])
		current_state = State.IDLE
		return
		
	var target_local = level_ref.object_layer.map_to_local(standing_tile)
	var target_world = level_ref.object_layer.to_global(target_local)
	
	var packed_path = pathfinder.get_path_route(global_position, target_world)
	
	if packed_path.is_empty():
		print("Bot: Cannot find a route to footprint!")
		if not is_building:
			unreachable_tiles.append(target_tiles[0])
		current_state = State.IDLE
		return
		
	current_path.clear()
	current_path.append_array(packed_path)
	
	# --- NEW: Tell the bot's action logic exactly which tile we walked up to! ---
	target_tile = interaction_tile


func _move_along_path(delta: float, next_state: State):
	if current_path.is_empty():
		current_state = next_state
		_start_action()
		return
		
	var target_pos = current_path[0]
	var dist = global_position.distance_to(target_pos)
	var move_step = current_speed * delta
	
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
					
				if building.has_signal("health_changed"):
					building.health_changed.emit(building.health, building.max_health)
					
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
		unreachable_storages.clear()
		unreachable_tiles.clear()
		current_state = State.IDLE


# ==========================================
# TILE MATH HELPERS
# ==========================================

func _get_standable_adjacent_tile(target_tiles: Array) -> Dictionary:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return {"stand": Vector2i(-1, -1), "target": Vector2i(-1, -1)}
	
	var neighbors = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var best_stand = Vector2i(-1, -1)
	var best_target = Vector2i(-1, -1)
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	var closest_dist = INF
	
	for t_tile in target_tiles:
		for offset in neighbors:
			var test_tile = t_tile + offset
			
			# Don't try to stand inside the building itself!
			if test_tile in target_tiles:
				continue
				
			if pathfinder.astar.is_in_boundsv(test_tile) and not pathfinder.astar.is_point_solid(test_tile):
				var dist = my_grid.distance_squared_to(test_tile)
				if dist < closest_dist:
					closest_dist = dist
					best_stand = test_tile
					best_target = t_tile
					
	return {"stand": best_stand, "target": best_target}


func _escape_trapped_tile() -> bool:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return false
	
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	
	# Are we stuck inside a solid building footprint?
	if pathfinder.astar.is_point_solid(my_grid):
		
		# Search outward in a square (Up to 2 tiles away just in case they are stuck in a big building!)
		for radius in range(1, 3):
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					var test_tile = my_grid + Vector2i(x, y)
					
					# Look for the closest empty piece of ground
					if pathfinder.astar.is_in_boundsv(test_tile) and not pathfinder.astar.is_point_solid(test_tile):
						
						# Found a safe spot! "Pop" the bot out instantly.
						var safe_local = level_ref.object_layer.map_to_local(test_tile)
						global_position = level_ref.object_layer.to_global(safe_local)
						print("Bot escaped from being trapped inside a building!")
						return true # Escaped!
						
	return false # Not trapped

# ==========================================
# UI INTERACTION & PRIORITY LOGIC
# ==========================================

func _on_mouse_entered():
	hovered.emit(self)

func _on_mouse_exited():
	unhovered.emit(self)


func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		clicked.emit(self)

func set_priority(new_priority: int):
	print(new_priority)
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
		# ← Expanded: interrupt ANY gathering/depositing state, not just IDLE/MOVING
		var interruptible_states = [
			State.IDLE, 
			State.MOVING_TO_RESOURCE, State.HARVESTING,
			State.MOVING_TO_INVENTORY, State.DEPOSITING
		]
		if current_state in interruptible_states:
			target_tile = Vector2i(-1, -1)
			current_path.clear()
			action_timer.stop()  # ← Critical: stop the harvest timer mid-swing
			current_state = State.IDLE
			
	inventory_changed.emit()

func get_inventory_info() -> Dictionary:
	var p_name = "Wood Only"
	if current_priority == TaskPriority.GATHER_STONE: p_name = "Stone Only"
	elif current_priority == TaskPriority.MAINTAIN: p_name = "Maintenance Duty"
	elif current_priority == TaskPriority.STOPPED: p_name = "Home"
	
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
# HOME SYSTEM
# ==========================================
func set_home(grid_pos: Vector2i):
	home_tile = grid_pos
	inventory_changed.emit()
	
	# If the bot is currently doing nothing, wake it up so it walks home instantly!
	if current_state in [State.IDLE, State.ON_STANDBY]:
		current_state = State.IDLE 

func _go_home_or_standby(wait_time: float):
	if home_tile != Vector2i(-1, -1):
		var my_grid = level_ref.object_layer.local_to_map(global_position)
		if my_grid != home_tile:
			if _request_path_exact(home_tile):
				current_state = State.MOVING_HOME
				return
				
	# If no home is set, we are already home, or the path is blocked:
	current_state = State.ON_STANDBY
	action_timer.start(wait_time)

func _request_path_exact(target_grid: Vector2i) -> bool:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return false
	
	# If the player built a wall over the bot's home, it can't go there!
	if pathfinder.astar.is_point_solid(target_grid):
		return false 
		
	var target_local = level_ref.object_layer.map_to_local(target_grid)
	var target_world = level_ref.object_layer.to_global(target_local)
	
	var packed_path = pathfinder.get_path_route(global_position, target_world)
	if packed_path.is_empty(): return false
	
	current_path.clear()
	current_path.append_array(packed_path)
	return true

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

	# Draw Home Tile (Light Blue Transparent Square)
	if is_selected and home_tile != Vector2i(-1, -1) and level_ref and level_ref.object_layer:
		var home_local_map = level_ref.object_layer.map_to_local(home_tile)
		var home_global = level_ref.object_layer.to_global(home_local_map)
		var home_local_to_bot = to_local(home_global)
		var rect = Rect2(home_local_to_bot - Vector2(16, 16), Vector2(32, 32))
		draw_rect(rect, Color(0.2, 0.8, 1.0, 0.2), true) 
		draw_rect(rect, Color(0.2, 0.8, 1.0, 0.8), false, 2.0)
	
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
		
	# --- ENERGY BAR ---
	if current_energy < max_energy:
		var e_width = 24.0
		var e_height = 4.0
		var e_pos = Vector2(-e_width / 2.0, 18.0) # Drawn below the bot's feet
		
		var e_bg = Rect2(e_pos, Vector2(e_width, e_height))
		var e_fg = Rect2(e_pos, Vector2(e_width * (current_energy / max_energy), e_height))
		
		var energy_color = Color(1.0, 0.8, 0.2) # Yellow (Normal Drain)
		if is_limping: 
			energy_color = Color(1.0, 0.2, 0.2) # Red (Exhausted/Limping)
		elif current_state == State.RECHARGING: 
			energy_color = Color(0.2, 1.0, 0.8) # Cyan (Charging Up)
		
		draw_rect(e_bg, Color(0.1, 0.1, 0.1, 0.8), true)
		draw_rect(e_fg, energy_color, true)
		draw_rect(e_bg, Color(0.0, 0.0, 0.0, 1.0), false, 1.0)
