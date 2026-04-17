extends Node2D
class_name WorkerBot

# ==========================================
# SIGNALS
# ==========================================
signal clicked(bot: WorkerBot)
signal inventory_changed
signal hovered(bot: WorkerBot)
signal unhovered(bot: WorkerBot)

# ==========================================
# ENUMS
# ==========================================
enum TaskPriority { GATHER_WOOD, GATHER_STONE, MAINTAIN, STOPPED }
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

# ==========================================
# IDENTITY (Duck typing — lets buildings and bots share UI code)
# ==========================================
var building_name: String = "Worker Bot"
var health: int = 100
var max_health: int = 100

# ==========================================
# CONFIGURATION (Tweak these in the inspector)
# ==========================================
@export var base_speed: float = 75.0
@export var carry_capacity: int = 5
@export var harvest_time: float = 1.0

@export_group("Energy")
@export var max_energy: float = 100.0
@export var energy_drain_rate: float = 2.0   # Per second while working
@export var energy_recharge_rate: float = 25.0 # Per second while recharging at home

# ==========================================
# RUNTIME STATE
# ==========================================

# --- Task & Movement ---
var current_priority: TaskPriority = TaskPriority.STOPPED
var current_state: State = State.IDLE
var current_speed: float
var _think_cooldown: float = 0.0

# --- Standby Durations ---
const STANDBY_IDLE: float = 1.0       # Nothing to do, check soon
const STANDBY_WAITING: float = 2.0    # Waiting for jobs or materials
const STANDBY_STORAGE_FULL: float = 5.0 # All storage full, wait for space

# --- Inventory ---
var carried_item_name: String = ""
var carried_amount: int = 0
var carried_item_res: Resource = null

# --- Energy ---
var current_energy: float = 100.0
var is_limping: bool = false

# --- Navigation ---
var target_tile: Vector2i = Vector2i(-1, -1)
var current_path: Array[Vector2] = []

# --- Home ---
var is_setting_home: bool = false
var home_tile: Vector2i = Vector2i(-1, -1)

# --- Blacklists (cleared on standby to retry after waiting) ---
var unreachable_tiles: Array[Vector2i] = []    # Resource tiles we couldn't path to
var full_storages_ignored: Array[Node2D] = []  # Storages that rejected our deposit
var unreachable_storages: Array[Node2D] = []   # Storages we couldn't path to

# --- References ---
var level_ref: Node2D
var is_selected: bool = false

@onready var action_timer = $ActionTimer

# ==========================================
# SETUP & READY
# ==========================================

func setup(level: Node2D):
	level_ref = level
	action_timer.timeout.connect(_on_action_timer_timeout)
	
	if has_node("Area2D"):
		$Area2D.input_event.connect(_on_input_event)
		$Area2D.mouse_entered.connect(_on_mouse_entered)
		$Area2D.mouse_exited.connect(_on_mouse_exited)
		
	if level_ref and level_ref.object_layer:
		home_tile = level_ref.object_layer.local_to_map(global_position)

func _ready():
	current_energy = max_energy
	current_speed = base_speed
	add_to_group("WorkerBots")
	apply_research_buffs()

# Called by ResearchManager when an upgrade completes
func apply_research_buffs():
	current_speed = base_speed * ResearchManager.bot_speed_mult

# ==========================================
# MAIN LOOP
# ==========================================

func _process(delta):
	
	queue_redraw()
	_handle_energy(delta)
	
	match current_state:
		State.IDLE:
			if _escape_trapped_tile():
				return
			
			# Throttle brain to 5 times per second instead of every frame
			_think_cooldown -= delta
			if _think_cooldown > 0:
				return
			_think_cooldown = 0.2
			
			if current_priority == TaskPriority.STOPPED:
				_go_home_or_standby(STANDBY_IDLE)
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
			_move_along_path(delta, State.RECHARGING)
		State.RECHARGING:
			pass # Handled entirely in _handle_energy

# ==========================================
# ENERGY SYSTEM
# ==========================================

func _handle_energy(delta: float):
	# --- RECHARGING: Refill energy at home tile ---
	if current_state == State.RECHARGING:
		current_energy += energy_recharge_rate * delta
		if current_energy >= max_energy:
			current_energy = max_energy
			is_limping = false
			current_speed = base_speed * ResearchManager.bot_speed_mult
			current_state = State.IDLE
		return

	# --- DRAINING: Lose energy while actively working or travelling ---
	# Limping bots don't drain — they are already at 0 and guaranteed to make it home
	var active_states = [
		State.MOVING_TO_RESOURCE, State.HARVESTING, 
		State.MOVING_TO_INVENTORY, State.DEPOSITING, 
		State.MOVING_TO_REPAIR, State.REPAIRING, 
		State.MOVING_TO_BUILD, State.BUILDING, 
		State.MOVING_TO_FETCH, State.FETCHING,
		State.MOVING_HOME
	]
	
	if current_state in active_states and not is_limping:
		current_energy -= energy_drain_rate * delta
		
		# --- EXHAUSTION: Drop everything and limp home ---
		if current_energy <= 0:
			current_energy = 0
			is_limping = true
			current_speed = base_speed * 0.4
			
			_clear_reservation()
			action_timer.stop()
			target_tile = Vector2i(-1, -1)
			
			if home_tile != Vector2i(-1, -1) and _request_path_exact(home_tile):
				current_state = State.MOVING_HOME
			else:
				# No home set or path is blocked — recharge on the spot
				current_state = State.RECHARGING

# ==========================================
# BRAIN: DECISION MAKING
# ==========================================

# Entry point for gather modes — finds the nearest unclaimed resource tile
func _find_nearest_resource():
	if carried_amount >= carry_capacity:
		_find_nearest_storage()
		return

	if not level_ref or level_ref.active_grid_objects.is_empty():
		return
		
	_clear_reservation()
		
	var my_grid_pos = level_ref.object_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF
	
	for tile in level_ref.active_grid_objects.keys():
		if unreachable_tiles.has(tile):
			continue
		
		var info = level_ref.active_grid_objects[tile]
		
		# Skip dead or machine-claimed resources
		if info["health"] <= 0:
			continue
		if info.get("harvester_claim_count", 0) > 0:
			continue
			
		# Skip tiles claimed by another bot
		if info.has("reserved_by") and is_instance_valid(info["reserved_by"]) and info["reserved_by"] != self:
			continue
		
		var item_name = info["data"].item_drop.display_name
		
		# Filter by current gather priority
		if current_priority == TaskPriority.GATHER_WOOD and item_name != "Wood":
			continue
		if current_priority == TaskPriority.GATHER_STONE and item_name != "Stone":
			continue

		# If already carrying something, only top up the same item
		if carried_amount > 0 and item_name != carried_item_name:
			continue
			
		var dist = my_grid_pos.distance_squared_to(tile)
		if dist < min_dist:
			min_dist = dist
			best_tile = tile
				
	if best_tile != Vector2i(-1, -1):
		_request_path([best_tile], false)
		if not current_path.is_empty():
			level_ref.active_grid_objects[target_tile]["reserved_by"] = self
			current_state = State.MOVING_TO_RESOURCE
		else:
			current_state = State.IDLE
	else:
		# No resources found — deposit if carrying something, otherwise wait
		if carried_amount > 0:
			_find_nearest_storage()
		else:
			current_state = State.IDLE

# Entry point for MAINTAIN mode — asks the BuildingManager for the highest priority job
func _find_priority_job():
	_clear_reservation()
	if not level_ref or not level_ref.building_manager: return

	var best_job = level_ref.building_manager.get_highest_priority_job(global_position)

	# No jobs exist right now
	if best_job == null:
		if carried_amount > 0:
			_find_nearest_storage()
		else:
			_go_home_or_standby(STANDBY_WAITING)
		return

	# We have a job but are holding the wrong item — go deposit first
	if carried_amount > 0:
		var holding_wrong_item = true
		
		if (best_job is ConstructionSite or best_job is TerraformSite) and not best_job.is_ready_to_build:
			if best_job.required_items.has(carried_item_name):
				var needed = best_job.required_items[carried_item_name]
				var have = best_job.delivered_items.get(carried_item_name, 0)
				if have < needed:
					holding_wrong_item = false
					
		if holding_wrong_item:
			_find_nearest_storage()
			return

	# Execute the job based on what type it is and what state we're in
	if best_job is ConstructionSite or best_job is TerraformSite:
		if carried_amount > 0:
			# Hands full of the right material — deliver it
			_request_path(best_job.occupied_tiles, true)
			if not current_path.is_empty():
				current_state = State.MOVING_TO_INVENTORY
			else:
				current_state = State.IDLE
				
		elif not best_job.is_ready_to_build:
			# Blueprint needs materials — go fetch them
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
			# Fully stocked — hammer it
			_request_path(best_job.occupied_tiles, true)
			if not current_path.is_empty():
				current_state = State.MOVING_TO_BUILD
			else:
				current_state = State.IDLE
				
	else:
		# Damaged building — repair it
		_request_path(best_job.occupied_tiles, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_REPAIR
		else:
			current_state = State.IDLE

# Finds the nearest storage with space for our carried item
func _find_nearest_storage():
	_clear_reservation()
	if not level_ref or not level_ref.building_manager: return
	
	# Quick inventory scan before any pathfinding — stay home if everything is full
	if not _any_storage_has_space():
		full_storages_ignored.clear()
		unreachable_storages.clear()
		_go_home_or_standby(STANDBY_STORAGE_FULL)
		return
	
	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var candidates: Array = []

	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		if b is ConstructionSite: continue
		if b is TowerBuilding: continue
		if not b.has_method("add_item"): continue
		if b in full_storages_ignored: continue
		if b in unreachable_storages: continue

		# Respect dedicated storage filters
		if "is_dedicated_mode" in b and "selected_output_name" in b:
			if b.is_dedicated_mode and b.selected_output_name != "" and b.selected_output_name != carried_item_name:
				continue

		if b.occupied_tiles.size() > 0:
			candidates.append({ 
				"building": b, 
				"tile": b.occupied_tiles[0], 
				"dist": my_pos.distance_squared_to(b.occupied_tiles[0]) 
			})

	# Try candidates closest first, blacklisting any that can't be pathed to
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])

	for candidate in candidates:
		var b_node = candidate["building"]
		_request_path(b_node.occupied_tiles, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_INVENTORY
			return
		else:
			unreachable_storages.append(b_node)

	# All candidates exhausted — wait and retry
	full_storages_ignored.clear()
	unreachable_storages.clear()
	_go_home_or_standby(STANDBY_STORAGE_FULL)

# Scans all buildings to find a stockpile that holds the requested item
func _find_stockpile_with_item(item_name: String):
	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF

	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		
		var has_item = false
		
		if "inventory" in b and typeof(b.inventory) == TYPE_DICTIONARY:
			for key in b.inventory.keys():
				if key is ItemResource and key.display_name == item_name:
					var amount = b.inventory[key]
					if typeof(amount) in [TYPE_INT, TYPE_FLOAT] and amount > 0:
						has_item = true
						break

		if has_item:
			var dist = my_pos.distance_squared_to(b.occupied_tiles[0])
			if dist < min_dist:
				min_dist = dist
				best_tile = b.occupied_tiles[0]
					
	if best_tile != Vector2i(-1, -1):
		carried_item_name = item_name
		var stockpile = level_ref.building_manager.occupied_tiles[best_tile]
		_request_path(stockpile.occupied_tiles, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_FETCH
		else:
			current_state = State.IDLE
	else:
		_go_home_or_standby(STANDBY_WAITING)

# Returns true if any valid storage building has space for our carried item
func _any_storage_has_space() -> bool:
	if not level_ref or not level_ref.building_manager: return false
	
	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		if b is ConstructionSite: continue
		if b is TowerBuilding: continue
		if not b.has_method("add_item"): continue
		
		if "is_dedicated_mode" in b and "selected_output_name" in b:
			if b.is_dedicated_mode and b.selected_output_name != "" and b.selected_output_name != carried_item_name:
				continue
		
		if b.has_method("has_space_for") and b.has_space_for(carried_item_name):
			return true
			
	return false

# ==========================================
# LEGS: MOVEMENT
# ==========================================

# Calculates a path to the nearest standable tile adjacent to the target footprint
func _request_path(target_tiles: Array, is_building: bool = false):
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return
	
	var result = _get_standable_adjacent_tile(target_tiles)
	var standing_tile = result["stand"]
	var interaction_tile = result["target"]
	
	if standing_tile == Vector2i(-1, -1):
		if not is_building:
			unreachable_tiles.append(target_tiles[0])
		current_state = State.IDLE
		return
		
	var target_world = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(standing_tile))
	#use the bot astar grid
	var packed_path = pathfinder.get_path_route(global_position, target_world, true)
	
	if packed_path.is_empty():
		if not is_building:
			unreachable_tiles.append(target_tiles[0])
		current_state = State.IDLE
		return
		
	current_path.clear()
	current_path.append_array(packed_path)
	target_tile = interaction_tile

# Calculates a direct path to an exact grid tile (used for home)
func _request_path_exact(target_grid: Vector2i) -> bool:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return false
	
	if pathfinder.bot_astar.is_point_solid(target_grid):
		return false
		
	var target_world = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(target_grid))
	#use the bot astar grid
	var packed_path = pathfinder.get_path_route(global_position, target_world, true)
	if packed_path.is_empty(): return false
	
	current_path.clear()
	current_path.append_array(packed_path)
	return true

# Steps the bot along its current path, transitioning to next_state on arrival
func _move_along_path(delta: float, next_state: State):
	if current_path.is_empty():
		current_state = next_state
		_start_action()
		return
		
	var actual_speed = current_speed
	
	if level_ref and level_ref.terrain_layer:
		var current_grid_pos = level_ref.terrain_layer.local_to_map(global_position)
		var tile_data = level_ref.terrain_layer.get_cell_tile_data(current_grid_pos)
		
		# If the tile exists and is marked as water, apply the penalty!
		if tile_data and tile_data.get_custom_data("is_water"):
			actual_speed = current_speed * 0.4 # Move at 40% speed while in water
			
	var target_pos = current_path[0]
	var dist = global_position.distance_to(target_pos)
	var move_step = actual_speed * delta
	
	if dist <= move_step:
		global_position = target_pos
		current_path.pop_front()
	else:
		global_position = global_position.move_toward(target_pos, move_step)

# ==========================================
# HANDS: ACTIONS
# ==========================================

# Starts the action timer for whatever state we just arrived at
func _start_action():
	match current_state:
		State.HARVESTING:  action_timer.start(harvest_time)
		State.DEPOSITING:  action_timer.start(0.5)
		State.REPAIRING:   action_timer.start(1.0)
		State.BUILDING:    action_timer.start(1.0)
		State.FETCHING:    action_timer.start(1.0)

func _on_action_timer_timeout():
	match current_state:
		State.HARVESTING:  _do_harvest()
		State.FETCHING:    _do_fetch()
		State.DEPOSITING:  _do_deposit()
		State.REPAIRING:   _do_repair()
		State.BUILDING:    _do_build()
		State.ON_STANDBY:  _do_standby_wake()

func _do_harvest():
	if not level_ref.active_grid_objects.has(target_tile):
		if carried_amount > 0: _find_nearest_storage()
		else: current_state = State.IDLE
		return
		
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
		if carried_amount > 0: _find_nearest_storage()
		else: current_state = State.IDLE
	else:
		action_timer.start(harvest_time) # Keep swinging

func _do_fetch():
	var storage = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	if not storage or not storage.has_method("take_item"):
		carried_item_name = ""
		current_state = State.IDLE
		return
		
	var result = storage.take_item(carried_item_name, carry_capacity)
	
	if result.get("amount", 0) > 0:
		carried_amount = result["amount"]
		carried_item_res = result["resource"]
		inventory_changed.emit()
		current_state = State.IDLE # Brain will route us to the blueprint next tick
	else:
		# Another bot grabbed the last item before us
		carried_item_name = ""
		current_state = State.IDLE

func _do_deposit():
	if carried_amount <= 0:
		current_state = State.IDLE
		return
		
	var storage = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	if not storage or not storage.has_method("add_item") or not is_instance_valid(storage):
		current_state = State.IDLE
		return
		
	var amount_taken = storage.add_item(carried_item_res, carried_amount)
	carried_amount -= amount_taken
	inventory_changed.emit()
	
	if carried_amount <= 0:
		# Successfully deposited everything
		carried_item_name = ""
		carried_item_res = null
		full_storages_ignored.clear()
		unreachable_storages.clear()
		current_state = State.IDLE
	else:
		# Storage was full — blacklist it and try the next one
		full_storages_ignored.append(storage)
		_find_nearest_storage()

func _do_repair():
	var building = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	if not building or not "health" in building or not "max_health" in building:
		current_state = State.IDLE # Building was destroyed
		return
		
	if building.health >= building.max_health:
		current_state = State.IDLE # Already fully healed
		return
		
	building.health = min(building.health + 5, building.max_health)
	
	if building.has_signal("health_changed"):
		building.health_changed.emit(building.health, building.max_health)
		
	if building.health >= building.max_health:
		current_state = State.IDLE # Done!
	else:
		action_timer.start(1.0) # Keep hammering

func _do_build():
	var building = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	if not building or not (building is ConstructionSite or building is TerraformSite):
		current_state = State.IDLE
		return
		
	building.add_build_progress(10)
	
	# Construction site replaces itself when complete — old reference becomes invalid
	if not is_instance_valid(building) or building.is_queued_for_deletion():
		current_state = State.IDLE
	else:
		action_timer.start(1.0) # Keep hammering

func _do_standby_wake():
	# Standby timer expired — clear all blacklists and try again with fresh eyes
	full_storages_ignored.clear()
	unreachable_storages.clear()
	unreachable_tiles.clear()
	current_state = State.IDLE

# ==========================================
# TILE MATH HELPERS
# ==========================================

# Finds the closest walkable tile adjacent to a building footprint
func _get_standable_adjacent_tile(target_tiles: Array) -> Dictionary:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return {"stand": Vector2i(-1, -1), "target": Vector2i(-1, -1)}
	
	var neighbors = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var best_stand = Vector2i(-1, -1)
	var best_target = Vector2i(-1, -1)
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	
	# --- THE FIX: Track Path Length instead of straight-line distance ---
	var shortest_path_length = INF
	
	for t_tile in target_tiles:
		for offset in neighbors:
			var test_tile = t_tile + offset
			if test_tile in target_tiles: continue
				
			if pathfinder.bot_astar.is_in_boundsv(test_tile) and not pathfinder.bot_astar.is_point_solid(test_tile):
				
				# 1. Ask the pathfinder for the actual walking route!
				var path_array = pathfinder.bot_astar.get_id_path(my_grid, test_tile)
				
				# 2. If the array is empty, this tile is completely walled off. Skip it!
				if path_array.is_empty() and my_grid != test_tile:
					continue
					
				# 3. Use the length of the actual path to determine the best tile
				var path_length = path_array.size()
				
				if path_length < shortest_path_length:
					shortest_path_length = path_length
					best_stand = test_tile
					best_target = t_tile
					
	return {"stand": best_stand, "target": best_target}
	
# If the bot is inside a solid tile (e.g. a building was placed on top of it), pop it out
func _escape_trapped_tile() -> bool:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return false
	
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	if not pathfinder.bot_astar.is_point_solid(my_grid): return false
	
	for radius in range(1, 3):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var test_tile = my_grid + Vector2i(x, y)
				if pathfinder.bot_astar.is_in_boundsv(test_tile) and not pathfinder.bot_astar.is_point_solid(test_tile):
					global_position = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(test_tile))
					return true
						
	return false

# ==========================================
# HOME SYSTEM
# ==========================================



func toggle_set_home_mode(enabled: bool):
	is_setting_home = enabled
	
	var reboot_cost = 50.0 # Cost is 50% of the max battery
	current_energy = max(0.0, current_energy - (max_energy/2))
	
	# If this change killed the battery, instantly trigger the limp state!
	if current_energy <= 0.0 and not is_limping:
		is_limping = true
		current_speed = base_speed * 0.4
		current_energy = 0
		
	queue_redraw()
	
func set_home(grid_pos: Vector2i):
	home_tile = grid_pos
	inventory_changed.emit()
	# Interrupt idle/resting states so the bot walks to the new home immediately
	if current_state in [State.IDLE, State.ON_STANDBY, State.MOVING_HOME, State.RECHARGING]:
		current_path.clear()
		action_timer.stop()
		current_state = State.IDLE

func is_valid_home_tile(grid_pos: Vector2i) -> bool:
	if not level_ref or not level_ref.building_manager: return false
	var bm = level_ref.building_manager
	
	# Be inside buildable range
	if not bm.buildable_tiles.has(grid_pos):
		return false
		
	# Cannot sleep in the Corruption!
	if bm.corruption_layer and bm.corruption_layer.get_cell_source_id(grid_pos) != -1:
		return false
		
	# 2. Cannot sleep inside a solid object (Wall, Tower, etc.)
	if bm.pathfinder and bm.pathfinder.bot_astar.is_point_solid(grid_pos):
		return false
		
	return true

# Sends the bot home if possible, otherwise puts it on a timed standby
func _go_home_or_standby(wait_time: float):
	if home_tile != Vector2i(-1, -1):
		var my_grid = level_ref.object_layer.local_to_map(global_position)
		if my_grid != home_tile and _request_path_exact(home_tile):
			current_state = State.MOVING_HOME
			return
	# Already home, no home set, or path is blocked
	current_state = State.ON_STANDBY
	action_timer.start(wait_time)

# ==========================================
# RESERVATION SYSTEM
# ==========================================

# Releases our claim on the current resource tile so other bots can take it
func _clear_reservation():
	if target_tile != Vector2i(-1, -1) and level_ref and level_ref.active_grid_objects.has(target_tile):
		var info = level_ref.active_grid_objects[target_tile]
		if info.has("reserved_by") and info["reserved_by"] == self:
			info["reserved_by"] = null


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
	if current_priority == new_priority: return
	
	current_priority = new_priority as TaskPriority
	_clear_reservation()
	
	# Void carried items that don't match the new priority
	if carried_amount > 0:
		if current_priority == TaskPriority.GATHER_WOOD and carried_item_name != "Wood":
			carried_amount = 0
			carried_item_name = ""
			carried_item_res = null
		elif current_priority == TaskPriority.GATHER_STONE and carried_item_name != "Stone":
			carried_amount = 0
			carried_item_name = ""
			carried_item_res = null
	
	if current_priority == TaskPriority.STOPPED:
		target_tile = Vector2i(-1, -1)
		current_path.clear()
		action_timer.stop()
		current_state = State.IDLE
	else:
		# Interrupt any gather/deposit work in progress
		var interruptible_states = [
			State.IDLE, 
			State.MOVING_TO_RESOURCE, State.HARVESTING,
			State.MOVING_TO_INVENTORY, State.DEPOSITING
		]
		if current_state in interruptible_states:
			target_tile = Vector2i(-1, -1)
			current_path.clear()
			action_timer.stop()
			current_state = State.IDLE
			
	inventory_changed.emit()

func get_inventory_info() -> Dictionary:
	var priority_names = {
		TaskPriority.GATHER_WOOD: "Wood Only",
		TaskPriority.GATHER_STONE: "Stone Only",
		TaskPriority.MAINTAIN: "Maintenance Duty",
		TaskPriority.STOPPED: "Home"
	}
	return {
		"Target": priority_names.get(current_priority, "Unknown"),
		"Carrying": "%s (%d)" % [carried_item_name, carried_amount] if carried_amount > 0 else "Empty"
	}

# ==========================================
# DEBUG VISUALS
# ==========================================

func _draw():
	_draw_path()
	_draw_home_tile()
	_draw_set_home_preview()
	_draw_target_tile()
	_draw_action_bar()
	_draw_energy_bar()

func _draw_path():
	if current_path.is_empty(): return
	
	var points = PackedVector2Array()
	points.append(Vector2.ZERO)
	for p in current_path:
		points.append(to_local(p))
		
	if points.size() > 1:
		draw_polyline(points, Color(0.2, 0.8, 1.0, 0.8), 2.0)
		draw_circle(to_local(current_path[-1]), 4.0, Color(1.0, 0.2, 0.2))

func _draw_home_tile():
	if not is_selected or home_tile == Vector2i(-1, -1): return
	if not level_ref or not level_ref.object_layer: return
	
	var home_local = to_local(level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(home_tile)))
	var rect = Rect2(home_local - Vector2(16, 16), Vector2(32, 32))
	draw_rect(rect, Color(0.2, 0.8, 1.0, 0.2), true)
	draw_rect(rect, Color(0.2, 0.8, 1.0, 0.8), false, 2.0)

func _draw_set_home_preview():
	if not is_setting_home: return
	if not level_ref or not level_ref.object_layer: return
	
	# Follow the mouse and snap to grid
	var mouse_global = get_global_mouse_position()
	var mouse_grid = level_ref.object_layer.local_to_map(level_ref.object_layer.to_local(mouse_global))
	var preview_local = to_local(level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(mouse_grid)))
	
	# Draw the ghost box
	var is_valid = is_valid_home_tile(mouse_grid)
	var box_color = Color(0.2, 0.8, 1.0, 0.8) if is_valid else Color(1.0, 0.2, 0.2) # Green or Red
	
	# Draw the colored ghost box
	var rect = Rect2(preview_local - Vector2(16, 16), Vector2(32, 32))
	draw_rect(rect, Color(box_color.r, box_color.g, box_color.b, 0.2), true)
	draw_rect(rect, Color(box_color.r, box_color.g, box_color.b, 0.8), false, 2.0)

func _draw_target_tile():
	if target_tile == Vector2i(-1, -1): return
	if not (current_state in [State.MOVING_TO_RESOURCE, State.HARVESTING]): return
	if not level_ref or not level_ref.object_layer: return
	
	var target_local = to_local(level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(target_tile)))
	var rect = Rect2(target_local - Vector2(16, 16), Vector2(32, 32))
	draw_rect(rect, Color(1.0, 0.2, 0.2, 0.8), false, 2.0)

func _draw_action_bar():
	var active_states = [State.HARVESTING, State.DEPOSITING, State.REPAIRING, State.ON_STANDBY, State.BUILDING, State.FETCHING]
	if not current_state in active_states: return
	if action_timer.is_stopped() or action_timer.wait_time <= 0: return
	
	var progress = 1.0 - (action_timer.time_left / action_timer.wait_time)
	var bar_pos = Vector2(-12.0, -24.0)
	
	var fill_colors = {
		State.REPAIRING:  Color(0.2, 0.6, 1.0),
		State.BUILDING:   Color(0.524, 0.004, 0.953),
		State.FETCHING:   Color(0.0, 0.8, 0.8),
		State.ON_STANDBY: Color(1.0, 1.0, 1.0)
	}
	var fill_color = fill_colors.get(current_state, Color(0.2, 0.8, 0.2))
	
	draw_rect(Rect2(bar_pos, Vector2(24.0, 4.0)), Color(0.1, 0.1, 0.1, 0.8), true)
	draw_rect(Rect2(bar_pos, Vector2(24.0 * progress, 4.0)), fill_color, true)
	draw_rect(Rect2(bar_pos, Vector2(24.0, 4.0)), Color(0.0, 0.0, 0.0, 1.0), false, 1.0)

func _draw_energy_bar():
	if current_energy >= max_energy: return
	
	var e_pos = Vector2(-12.0, 18.0)
	var energy_colors = {
		true: Color(1.0, 0.2, 0.2),   # Limping
		false: Color(1.0, 0.8, 0.2)   # Normal drain
	}
	var energy_color = energy_colors.get(is_limping, Color(1.0, 0.8, 0.2))
	if current_state == State.RECHARGING:
		energy_color = Color(0.2, 1.0, 0.8)
	
	draw_rect(Rect2(e_pos, Vector2(24.0, 4.0)), Color(0.1, 0.1, 0.1, 0.8), true)
	draw_rect(Rect2(e_pos, Vector2(24.0 * (current_energy / max_energy), 4.0)), energy_color, true)
	draw_rect(Rect2(e_pos, Vector2(24.0, 4.0)), Color(0.0, 0.0, 0.0, 1.0), false, 1.0)

# ==========================================
# SAVE / LOAD SYSTEM (Worker Bot)
# ==========================================
func get_save_data() -> Dictionary:
	return {
		# 1. Exact Pixel Position
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		
		# 2. Grid Memory
		"home_x": home_tile.x,
		"home_y": home_tile.y,
		"target_x": target_tile.x,
		"target_y": target_tile.y,
		
		# 3. Brain State
		"current_priority": current_priority,
		"current_state": current_state,
		"current_energy": current_energy,
		"is_limping": is_limping,
		
		# 4. Inventory
		"carried_item_name": carried_item_name,
		"carried_amount": carried_amount,
		
		# 5. Action Progress (How much time is left on harvesting/repairing)
		"timer_time_left": action_timer.time_left if not action_timer.is_stopped() else 0.0
	}

func load_save_data(data: Dictionary):
	# 1. Restore Position
	global_position = Vector2(data.get("pos_x", 0.0), data.get("pos_y", 0.0))
	
	# 2. Restore Grid Coordinates
	home_tile = Vector2i(data.get("home_x", -1), data.get("home_y", -1))
	target_tile = Vector2i(data.get("target_x", -1), data.get("target_y", -1))
	
	# 3. Restore State & Energy
	current_priority = data.get("current_priority", TaskPriority.STOPPED) as TaskPriority
	current_state = data.get("current_state", State.IDLE) as State
	current_energy = data.get("current_energy", max_energy)
	is_limping = data.get("is_limping", false)
	
	if is_limping:
		current_speed = base_speed * 0.4
		
	# 4. Restore Inventory via ItemDatabase
	carried_amount = data.get("carried_amount", 0)
	carried_item_name = data.get("carried_item_name", "")
	
	if carried_amount > 0 and carried_item_name != "":
		carried_item_res = ItemDatabase.get_item(carried_item_name)
	else:
		carried_item_res = null
		
	# 5. Restore Action Timer
	var time_left = data.get("timer_time_left", 0.0)
	if time_left > 0:
		action_timer.start(time_left)
		
	# 6. Wipe volatile memory so the bot recalculates everything safely
	current_path.clear()
	unreachable_tiles.clear()
	full_storages_ignored.clear()
	unreachable_storages.clear()
	
	var transit_states = [
		State.MOVING_TO_RESOURCE, State.MOVING_TO_INVENTORY,
		State.MOVING_TO_REPAIR, State.MOVING_TO_BUILD,
		State.MOVING_TO_FETCH, State.MOVING_HOME
	]
	
	# If the bot was walking somewhere, cancel the walk and let the brain rethink!
	if current_state in transit_states:
		current_state = State.IDLE
		target_tile = Vector2i(-1, -1)
		action_timer.stop()
	
	# Wake up the UI
	inventory_changed.emit()
