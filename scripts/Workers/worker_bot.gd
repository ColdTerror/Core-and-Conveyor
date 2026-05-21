# ==============================================================================
# Script: Workers/worker_bot.gd
# Purpose: Massive state-machine driven worker bot governing resource gathering, home relocation recharge paths, building/repairing tasks, ammo fetching, veterancy leveling XP, and enemy damage panic sprints.
# Dependencies: Requires parent Level reference, child ActionTimer, ActionAudio, MoveAudio, Sprite2D nodes, and global autoloads (ResearchManager, EconomyManager, AudioManager, ItemDatabase, InputManager).
# Signals:
#   - inventory_changed: Fired whenever carried items change — UI listens to this.
#   - hovered: Fired when the mouse enters the bot's Area2D.
#   - unhovered: Fired when the mouse leaves the bot's Area2D.
# ==============================================================================
class_name WorkerBot
extends Node2D

signal inventory_changed          # Fired whenever carried items change — UI listens to this
signal hovered(bot: WorkerBot)    # Fired when the mouse enters the bot's Area2D
signal unhovered(bot: WorkerBot)  # Fired when the mouse leaves the bot's Area2D

# Enums

# What high-level job the player has assigned this bot.
# STOPPED is the default/idle assignment — the bot will go home and wait.
enum TaskPriority { GATHER_WOOD, GATHER_STONE, MAINTAIN, STOPPED }

# The bot's internal execution state — what it is actually doing right now.
# States come in MOVING/ACTION pairs: the bot walks to a target, then acts on it.
# PANIC states override everything and send the bot sprinting home when hit.
enum State { 
	IDLE,                              # Brain is active and choosing the next task
	MOVING_TO_RESOURCE, HARVESTING,    # Walking to a tree/rock, then chopping/mining
	MOVING_TO_INVENTORY, DEPOSITING,   # Walking to a storage building, then depositing
	ON_STANDBY,                        # Waiting on a timer before trying again (nothing to do)
	MOVING_TO_REPAIR, REPAIRING,       # Walking to a damaged building, then hammering it
	MOVING_TO_BUILD, BUILDING,         # Walking to a construction site, then building it
	MOVING_TO_FETCH, FETCHING,         # Walking to a stockpile to pick up materials
	MOVING_HOME, RECHARGING,           # Walking to the home tile, then resting until full energy
	PANIC_MOVING_HOME, PANIC_WAITING   # Emergency sprint home after taking damage
}

# Identity variables
var building_name: String = "Worker Bot"
var health: int = 100
var max_health: int = 100

# --- VETERANCY SYSTEM ---
# Bots gain XP by harvesting, depositing, repairing, and building.
# Levelling up permanently improves speed, carry capacity, and max health.
# The global max level is gated by ResearchManager so the player must research it first.
var bot_level: int = 1
var current_xp: int = 0
# Index = level - 1. A bot starts at level 1 (threshold 0), levels up at 50 XP, etc.
const XP_THRESHOLDS: Array[int] = [0, 50, 150, 300] # Thresholds for levels 1, 2, 3, 4

# Configuration variables
@export_group("Base Stats")
@export var base_speed: float = 75.0    # Pixels per second before any buffs
@export var carry_capacity: int = 5     # Max items the bot can hold at once
@export var harvest_time: float = 1.0   # Seconds per harvest swing

@export_group("Energy")
@export var max_energy: float = 100.0
@export var energy_drain_rate: float = 2.0    # Energy lost per second while working/moving
@export var energy_recharge_rate: float = 25.0 # Energy gained per second while resting at home
@export var health_recharge_rate: float = 10.0 # HP gained per second while resting at home
@export var low_battery_threshold: float = 0.1

# Runtime State variables (do not tweak in the inspector)

# --- Task & Movement ---
var current_priority: TaskPriority = TaskPriority.STOPPED
var current_state: State = State.IDLE

# Single source of truth for the bot's fully-buffed normal speed.
# _recalculate_stats() is the ONLY place this is written to.
# All speed modifiers (limp, panic, water) multiply from this value, ensuring
# level bonuses and research buffs are always included in the final speed.
var _normal_speed: float

# Throttle the IDLE brain so it runs at most 5 times per second rather than
# every frame. Pathfinding and building scans are expensive — this saves a lot of CPU.
var _think_cooldown: float = 0.0

# --- Standby Durations ---
# How long the bot waits before retrying after hitting a dead end.
# Longer waits for rarer events (storage full) to avoid thrashing.
const STANDBY_IDLE: float = 1.0         # Nothing to do right now — check again soon
const STANDBY_WAITING: float = 2.0      # Waiting for a job or materials to appear
const STANDBY_STORAGE_FULL: float = 5.0 # All storage is full — wait for space to open up

# --- Speed Multipliers ---
# Applied to _normal_speed to get the actual speed in each movement mode.
# Defined as constants so designers can tune them in one place.
const SPEED_MULT_LIMP: float = 0.4   # Bot is exhausted — slow shuffle home
const SPEED_MULT_PANIC: float = 1.5  # Bot was just hit — adrenaline sprint home
const SPEED_MULT_WATER: float = 0.4  # Bot is wading through water tiles

# --- Inventory ---
var carried_item_name: String = ""    # Display name of the item being carried (e.g. "Wood")
var carried_amount: int = 0           # How many of that item are being carried
var carried_item_res: Resource = null # The ItemResource reference, needed to call add_item()

# --- Energy ---
var current_energy: float = 100.0
# is_limping is set when energy hits 0. The bot immediately heads home at reduced speed.
# While limping, energy does NOT drain further (it's already 0) so the bot is guaranteed
# to reach home without stopping mid-path.
var is_limping: bool = false
# Accumulates fractional HP from health_recharge_rate so we only apply whole-number heals.
var _health_accumulator: float = 0.0

# --- Navigation ---
var target_tile: Vector2i = Vector2i(-1, -1) # The grid tile the bot is interacting with
var current_path: Array[Vector2] = []         # World-space waypoints from the pathfinder

# --- Home ---
# The bot walks home to recharge when energy is low, when STOPPED, or when panicking.
# is_setting_home is true while the player is dragging a new home location for this bot.
var is_setting_home: bool = false
var home_tile: Vector2i = Vector2i(-1, -1)    # (-1,-1) means no home has been assigned yet

# --- Blacklists ---
# When the bot can't reach a target or a storage is full, it adds it to a blacklist
# and tries the next best option. Blacklists are cleared when the bot goes on standby
# so it retries everything with fresh eyes after a short wait.
var unreachable_tiles: Array[Vector2i] = []    # Resource tiles that had no walkable path
var full_storages_ignored: Array[Node2D] = []  # Storages that rejected our deposit attempt
var unreachable_storages: Array[Node2D] = []   # Storages we couldn't find a path to

# --- References ---
var level_ref: Node2D        # Set by the spawner via setup() — gives access to the game world
var is_selected: bool = false # True while the player has this bot's UI panel open

@onready var action_timer = $ActionTimer  # One-shot timer drives all timed actions (harvest, deposit, etc.)


# --- Audio ---
@onready var action_audio = $ActionAudio
@onready var move_audio = $MoveAudio
var _step_cooldown: float = 0.0

# --- Visual State ---
var last_facing_dir: Vector2 = Vector2.DOWN # Default to facing the camera
@onready var sprite = $Sprite2D # Make sure this matches your actual node name!

# _ready() fires after the node is fully in the tree.

func _ready():
	# Allow the research tree to set a higher starting level (e.g. from a factory upgrade)
	if ResearchManager.has_method("get_bot_start_level"):
		bot_level = ResearchManager.get_bot_start_level()
		# Give the bot the minimum XP for their starting level so XP thresholds stay consistent
		current_xp = XP_THRESHOLDS[bot_level - 1]
		
	current_energy = max_energy
	add_to_group("WorkerBots")
	# _recalculate_stats() sets both _normal_speed and current_speed, so no manual
	# speed initialisation is needed here.
	_recalculate_stats()
	
	_update_sprite()

# Main process loop (handles energy drain and drives state machine)
func _process(delta):
	queue_redraw() # Redraw debug overlays (path line, bars, home tile) every frame
	_handle_energy(delta)
	
	match current_state:
		State.IDLE:
			# Safety check: if a building was placed on top of the bot, pop it out first
			if _escape_trapped_tile():
				return
			
			# A limping bot has no energy left — its only job is to get home and rest
			if is_limping:
				_go_home_or_standby(STANDBY_IDLE)
				return
			
			# Throttle the decision-making brain to ~5 times/second
			_think_cooldown -= delta
			if _think_cooldown > 0:
				return
			_think_cooldown = 0.2
			
			if current_priority == TaskPriority.STOPPED:
				_go_home_or_standby(STANDBY_IDLE)
				return
			if current_priority == TaskPriority.MAINTAIN:
				_find_priority_job()     # Ask BuildingManager for the most urgent task
			else:
				_find_nearest_resource() # Scan for nearby Wood/Stone to harvest
			
		# Each MOVING state advances the bot along its path.
		# When the path is exhausted, _move_along_path() transitions to the paired action state.
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
		State.PANIC_MOVING_HOME:
			_move_along_path(delta, State.PANIC_WAITING)
		
		# RECHARGING and PANIC_WAITING are fully driven by _handle_energy() each frame.
		# No movement or action logic is needed here.
		State.RECHARGING, State.PANIC_WAITING:
			pass
			
# UI and debug drawing for the bot
func _draw():
	_draw_path()
	_draw_home_tile()
	_draw_set_home_preview()
	_draw_target_tile()
	_draw_action_bar()
	_draw_energy_bar()
	
# setup() is called by the spawner before the node enters the scene tree.

func setup(level: Node2D):
	level_ref = level
	action_timer.timeout.connect(_on_action_timer_timeout)
	
	if has_node("Area2D"):
		$Area2D.mouse_entered.connect(_on_mouse_entered)
		$Area2D.mouse_exited.connect(_on_mouse_exited)
	
	# Default home to spawn position so the bot has somewhere to recharge immediately
	if level_ref and level_ref.object_layer:
		home_tile = level_ref.object_layer.local_to_map(global_position)



# Stats Recalculation (called on spawn, level-up, and research unlock)
func _recalculate_stats():
	# Start from the designer-set base values
	var calc_speed = base_speed
	var calc_carry = 5
	var calc_max_hp = 100
	
	# Level bonuses are cumulative — a level 3 bot gets BOTH the level 2 AND level 3 bonuses
	if bot_level >= 2:
		calc_speed *= 1.25
	if bot_level >= 3:
		calc_speed *= 1.5
		calc_carry += 2
	if bot_level >= 4:
		calc_carry += 3
		calc_max_hp += 50
		
	
	# Store as the authoritative normal speed. Nothing else should write to _normal_speed.
	_normal_speed = calc_speed


	carry_capacity = calc_carry
	
	# Scale current health proportionally to the new max so a level-up doesn't
	# silently heal or damage the bot (e.g. going from 80/100 to 120/150, not 80/150).
	var hp_ratio = float(health) / float(max_health)
	max_health = calc_max_hp
	health = int(max_health * hp_ratio)

# XP & Leveling logic
func _add_xp(amount: int):
	# Respect the global max level gate set by the research tree.
	# A bot at the current cap simply stops accumulating XP.
	var global_max = 2 # Fallback if ResearchManager doesn't implement the method yet
	if ResearchManager.has_method("get_bot_max_level"):
		global_max = ResearchManager.get_bot_max_level()
		
	if bot_level >= global_max:
		return
		
	current_xp += amount
	
	# XP_THRESHOLDS[bot_level] is the threshold for the NEXT level
	# (e.g. at level 1, index 1 = 50 XP needed to reach level 2)
	var next_level_threshold = XP_THRESHOLDS[bot_level]
	if current_xp >= next_level_threshold:
		bot_level += 1
		_recalculate_stats() # Immediately apply stat bonuses for the new level
		
func _get_speed() -> float:
	var mult := 1.0

	# State modifiers
	if is_limping:
		mult *= SPEED_MULT_LIMP
	elif current_state == State.PANIC_MOVING_HOME:
		mult *= SPEED_MULT_PANIC

	# Terrain modifier
	if level_ref and level_ref.terrain_layer:
		var grid = level_ref.terrain_layer.local_to_map(global_position)
		var tile = level_ref.terrain_layer.get_cell_tile_data(grid)
		if tile and tile.get_custom_data("is_water"):
			mult *= SPEED_MULT_WATER

	return _normal_speed * mult

# Energy system logic
func _handle_energy(delta: float):
	# --- RECHARGING: Bot is resting at home ---
	if current_state == State.RECHARGING or current_state == State.PANIC_WAITING:
		current_energy += energy_recharge_rate * delta
		
		if health < max_health:
			_health_accumulator += health_recharge_rate * delta
			if _health_accumulator >= 1.0:
				var heal_amount = int(_health_accumulator)
				health = min(health + heal_amount, max_health)
				_health_accumulator -= heal_amount 
				
		if current_energy >= max_energy:
			current_energy = max_energy
			is_limping = false
			current_state = State.IDLE     # Wake up and get back to work
		return  

	# --- DRAINING: Bot is actively working ---
	var active_states = [
		State.MOVING_TO_RESOURCE, State.HARVESTING,
		State.MOVING_TO_INVENTORY, State.DEPOSITING,
		State.MOVING_TO_REPAIR, State.REPAIRING,
		State.MOVING_TO_BUILD, State.BUILDING,
		State.MOVING_TO_FETCH, State.FETCHING,
		State.MOVING_HOME  # Still drains while walking home normally
	]
	
	if current_state in active_states and not is_limping:
		current_energy -= energy_drain_rate * delta
		
		# --- 1. EXHAUSTION: Energy hit zero (Limp Mode) ---
		if current_energy <= 0:
			current_energy = 0
			is_limping = true
			
			_clear_reservation()
			action_timer.stop()
			target_tile = Vector2i(-1, -1)
			
			if home_tile != Vector2i(-1, -1) and _request_path_exact(home_tile):
				current_state = State.MOVING_HOME
			else:
				current_state = State.RECHARGING

		# --- 2. LOW BATTERY: 10% (Smart Return) ---
		elif current_energy <= (max_energy * low_battery_threshold):
			
			# Make sure we don't constantly interrupt the bot if it's already heading home!
			if current_state != State.MOVING_HOME:
				_clear_reservation()
				action_timer.stop()
				target_tile = Vector2i(-1, -1)
				
				# Route home at full normal speed
				if home_tile != Vector2i(-1, -1) and _request_path_exact(home_tile):
					current_state = State.MOVING_HOME
				else:
					current_state = State.RECHARGING
					
# Brain: Decision Making (runs from IDLE state only)

# Entry point for GATHER_WOOD / GATHER_STONE modes.
# Scans active_grid_objects for the nearest unclaimed resource and paths to it.
func _find_nearest_resource():
	# If already carrying a full load, skip the search and go deposit instead
	if carried_amount >= carry_capacity:
		_find_nearest_storage()
		return

	if not level_ref or level_ref.active_grid_objects.is_empty():
		return
		
	_clear_reservation() # Release any old claim before claiming a new tile
		
	var my_grid_pos = level_ref.object_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF
	
	for tile in level_ref.active_grid_objects.keys():
		# Skip tiles we already know we can't reach this trip
		if unreachable_tiles.has(tile):
			continue
		
		var info = level_ref.active_grid_objects[tile]
		
		if info["health"] <= 0:
			continue  # Resource is depleted
		if info.get("harvester_claim_count", 0) > 0:
			continue  # A machine (extractor etc.) has a hard claim — bots don't compete with machines
			
		# Skip tiles another bot has soft-reserved this tick
		if info.has("reserved_by") and is_instance_valid(info["reserved_by"]) and info["reserved_by"] != self:
			continue
		
		var item_name = info["data"].item_drop.display_name
		
		# Filter to only the item type matching the current priority
		if current_priority == TaskPriority.GATHER_WOOD and item_name != "Wood":
			continue
		if current_priority == TaskPriority.GATHER_STONE and item_name != "Stone":
			continue

		# If mid-carry, only top up the same item type to avoid mixed loads
		if carried_amount > 0 and item_name != carried_item_name:
			continue
			
		# Use squared distance — avoids a sqrt per tile and is fine for comparison
		var dist = my_grid_pos.distance_squared_to(tile)
		if dist < min_dist:
			min_dist = dist
			best_tile = tile
				
	if best_tile != Vector2i(-1, -1):
		_request_path([best_tile], false)
		if not current_path.is_empty():
			# Soft-reserve the tile so other bots skip it while we're en route
			level_ref.active_grid_objects[target_tile]["reserved_by"] = self
			current_state = State.MOVING_TO_RESOURCE
		else:
			current_state = State.IDLE  # _request_path already blacklisted the tile
	else:
		# No valid resources found
		if carried_amount > 0:
			_find_nearest_storage()  # Carry what we have to storage
		else:
			current_state = State.IDLE  # Nothing to do — IDLE will retry next think tick

# Entry point for MAINTAIN mode.
# Delegates job selection to BuildingManager so priority is managed centrally.
func _find_priority_job():
	_clear_reservation()
	if not level_ref or not level_ref.building_manager: return

	# BuildingManager scores all pending jobs (repairs, builds, fetches) and returns the best one
	var best_job = level_ref.building_manager.get_highest_priority_job(global_position)

	if best_job == null:
		# No jobs exist right now — deposit if holding something, otherwise wait
		if carried_amount > 0:
			_find_nearest_storage()
		else:
			_go_home_or_standby(STANDBY_WAITING)
		return

	# Check if what we're carrying is actually useful for the best job
	if carried_amount > 0:
		var holding_wrong_item = true
		
		if (best_job is ConstructionSite or best_job is TerraformSite):
			if not best_job.is_ready_to_build:
				if best_job.required_items.has(carried_item_name):
					var needed = best_job.required_items[carried_item_name]
					var have = best_job.delivered_items.get(carried_item_name, 0)
					if have < needed:
						holding_wrong_item = false
			else:
				# Ready to build — carrying anything is fine, just go hammer it
				holding_wrong_item = false
			
		# If we're holding something useless, dump it first before taking the job
		if holding_wrong_item:
			_find_nearest_storage()
			return

	# Route to the correct action based on what the job needs from us right now
	if best_job is ConstructionSite or best_job is TerraformSite:
		if best_job.is_ready_to_build:
			# Blueprint is fully stocked — go build it regardless of what we're carrying
			_request_path(best_job.occupied_tiles, true)
			if not current_path.is_empty():
				current_state = State.MOVING_TO_BUILD
			else:
				current_state = State.IDLE
				
		elif carried_amount > 0:
			# Still needs materials and we're holding some — deliver them
			_request_path(best_job.occupied_tiles, true)
			if not current_path.is_empty():
				current_state = State.MOVING_TO_INVENTORY
			else:
				current_state = State.IDLE
				
		else:
			# Still needs materials and hands are empty — go fetch from stockpile
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
		# It's a damaged building — walk up and start repairing
		_request_path(best_job.occupied_tiles, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_REPAIR
		else:
			current_state = State.IDLE

# Finds the nearest storage building that has space for our carried item.
# Uses a blacklist-and-retry pattern: if a storage rejects us, we blacklist it
# and try the next nearest one rather than giving up entirely.
func _find_nearest_storage():
	_clear_reservation()
	if not level_ref or not level_ref.building_manager: return
	
	# Pre-flight check: if no storage has space at all, don't bother pathfinding.
	# This avoids pathing to every building just to get rejected by all of them.
	if not _any_storage_has_space():
		# Clear blacklists so we start fresh on the next attempt
		full_storages_ignored.clear()
		unreachable_storages.clear()
		if current_priority == TaskPriority.MAINTAIN:
			# Maintenance bots just drop their load and find something else to do
			_drop_inventory_and_work()
			return
		_go_home_or_standby(STANDBY_STORAGE_FULL)
		return
	
	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var candidates: Array = []

	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		if b is ConstructionSite: continue  # Construction sites aren't storage
		if b is TowerBuilding: continue     # Towers don't store items
		if not b.has_method("add_item"): continue  # Not a storage building
		if b in full_storages_ignored: continue    # Already rejected us this trip
		if b in unreachable_storages: continue     # Already proven unreachable

		# Respect dedicated-mode storage: a Warehouse set to "Wood only" will
		# reject Stone, so don't waste time pathing there.
		if "is_dedicated_mode" in b and "selected_output_name" in b:
			if b.is_dedicated_mode and b.selected_output_name != "" and b.selected_output_name != carried_item_name:
				continue

		if b.occupied_tiles.size() > 0:
			candidates.append({
				"building": b,
				"tile": b.occupied_tiles[0],
				"dist": my_pos.distance_squared_to(b.occupied_tiles[0])
			})

	# Sort by distance so we always try the closest option first
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])

	# Try each candidate in order, blacklisting those we can't path to
	for candidate in candidates:
		var b_node = candidate["building"]
		_request_path(b_node.occupied_tiles, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_INVENTORY
			return
		else:
			unreachable_storages.append(b_node)

	# All candidates exhausted — clear blacklists and wait before retrying
	full_storages_ignored.clear()
	unreachable_storages.clear()
	if current_priority == TaskPriority.MAINTAIN:
		_drop_inventory_and_work()
		return
	_go_home_or_standby(STANDBY_STORAGE_FULL)

# Scans all buildings for one that stocks the requested material.
# Used by MAINTAIN bots to fetch supplies for a construction blueprint.
func _find_stockpile_with_item(item_name: String):
	var my_pos = level_ref.terrain_layer.local_to_map(global_position)
	var best_tile = Vector2i(-1, -1)
	var min_dist = INF

	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		
		var has_item = false
		
		# Inventory is a Dictionary keyed by ItemResource — check all entries
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
		# Set the item name now so FETCHING logic knows what we're picking up
		carried_item_name = item_name
		var stockpile = level_ref.building_manager.occupied_tiles[best_tile]
		_request_path(stockpile.occupied_tiles, true)
		if not current_path.is_empty():
			current_state = State.MOVING_TO_FETCH
		else:
			current_state = State.IDLE
	else:
		# No stockpile holds this material — wait for one to appear
		_go_home_or_standby(STANDBY_WAITING)

# Quick scan to check if ANY valid storage has room before doing heavy pathfinding.
# Returns false only when every eligible storage is completely full.
func _any_storage_has_space() -> bool:
	if not level_ref or not level_ref.building_manager: return false
	
	for b in level_ref.building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		if b is ConstructionSite: continue
		if b is TowerBuilding: continue
		if not b.has_method("add_item"): continue
		
		# Respect dedicated-mode filter here too
		if "is_dedicated_mode" in b and "selected_output_name" in b:
			if b.is_dedicated_mode and b.selected_output_name != "" and b.selected_output_name != carried_item_name:
				continue
		
		if b.has_method("has_space_for") and b.has_space_for(carried_item_name):
			return true
			
	return false

# Legs: Movement and path calculation

# Builds a path to the nearest walkable tile adjacent to a building's footprint.
# Used for multi-tile buildings — the bot can't stand inside the building, so we
# find the best neighboring tile to stand on while interacting.
func _request_path(target_tiles: Array, is_building: bool = false):
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return
	
	# Find the best standable tile next to the target and which target tile faces it
	var result = _get_standable_adjacent_tile(target_tiles)
	var standing_tile = result["stand"]     # Where the bot will stand
	var interaction_tile = result["target"] # Which tile of the building to "face"
	
	if standing_tile == Vector2i(-1, -1):
		# No adjacent walkable tile found — blacklist so we don't retry immediately
		if not is_building:
			unreachable_tiles.append(target_tiles[0])
		current_state = State.IDLE
		return
		
	var target_world = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(standing_tile))
	var packed_path = pathfinder.get_path_route(global_position, target_world, true)
	
	if packed_path.is_empty():
		# Pathfinder found no route — blacklist and bail
		if not is_building:
			unreachable_tiles.append(target_tiles[0])
		current_state = State.IDLE
		return
		
	current_path.clear()
	current_path.append_array(packed_path)
	target_tile = interaction_tile  # Save which tile to interact with on arrival

# Builds a direct path to an exact grid tile, used for home navigation.
# Returns true if a valid path was found, false if unreachable.
func _request_path_exact(target_grid: Vector2i) -> bool:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return false
	
	# Don't try to path into a solid tile (home was valid when set but something was built there)
	if pathfinder.bot_astar.is_point_solid(target_grid):
		return false
		
	var target_world = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(target_grid))
	var packed_path = pathfinder.get_path_route(global_position, target_world, true)
	if packed_path.is_empty(): return false
	
	current_path.clear()
	current_path.append_array(packed_path)
	return true

# Steps the bot along its pre-calculated path each frame.
# When the last waypoint is reached, transitions to next_state and fires _start_action().
func _move_along_path(delta: float, next_state: State):
	if current_path.is_empty():
		move_audio.stop()
		# Arrived at destination — transition to the action state
		current_state = next_state
		_start_action()
		return
		
	
	if level_ref and level_ref.terrain_layer:
		var current_grid_pos = level_ref.terrain_layer.local_to_map(global_position)
		var tile_data = level_ref.terrain_layer.get_cell_tile_data(current_grid_pos)
		

	# --- THE FOOTSTEP LOOP ---
	_step_cooldown -= delta
	
	if _step_cooldown <= 0.0:
		var grass_steps = AudioManager.sfx_playlists["walk_grass"]
		move_audio.stream = grass_steps.pick_random()
		move_audio.play()
		
		# Reset the timer! 
		# We divide a "magic number" (like 25.0) by the bot's current speed.
		# If speed is 75, a step plays every 0.33 seconds.
		# If it panics and speed jumps to 150, a step plays every 0.16 seconds!
		_step_cooldown = 30.0 / max(_get_speed(), 1.0)
		
	var target_pos = current_path[0]
	var dist = global_position.distance_to(target_pos)
	var move_step = _get_speed() * delta
	
	var move_dir = target_pos - global_position
	_update_sprite(move_dir)
	
	if dist <= move_step:
		# Close enough — snap to the waypoint exactly, then advance to the next one
		global_position = target_pos
		current_path.pop_front()
	else:
		global_position = global_position.move_toward(target_pos, move_step)

# Hands: Timer-driven actions

# Starts the action timer for the current state. Duration varies by action type.
func _start_action():
	_update_sprite()
	
	match current_state:
		State.HARVESTING:  action_timer.start(harvest_time)
		State.DEPOSITING:  action_timer.start(0.5)
		State.REPAIRING:   action_timer.start(1.0)
		State.BUILDING:    action_timer.start(1.0)
		State.FETCHING:    action_timer.start(1.0)
		State.PANIC_WAITING: action_timer.start(30.0)



# Attempts to harvest one unit from the target tile.
# If the resource isn't gone yet, re-starts the timer to keep harvesting automatically.
func _do_harvest():
	# Resource may have been depleted by another bot or machine since we started walking
	if not level_ref.active_grid_objects.has(target_tile):
		if carried_amount > 0: _find_nearest_storage()
		else: current_state = State.IDLE
		return
		
	var info = level_ref.active_grid_objects[target_tile]
	# ResourceManager arbitrates the actual harvest to handle machine-claimed tiles cleanly
	var harvested_amount = ResourceManager.request_harvest(target_tile, info, 1)
	
	if harvested_amount > 0:
		carried_item_res = info["data"].item_drop
		carried_item_name = carried_item_res.display_name
		carried_amount += harvested_amount
		inventory_changed.emit()
		_add_xp(1)
		
		EconomyManager.log_item_produced(carried_item_name, harvested_amount)
		
		# ---Play the correct sound based on the item! ---
		if carried_item_name == "Wood":
			action_audio.stream = AudioManager.sfx_tracks["wood"]
		elif carried_item_name == "Stone":
			action_audio.stream = AudioManager.sfx_tracks["stone"]
		action_audio.pitch_scale = randf_range(0.85, 1.15)
		action_audio.play()
		
	if carried_amount >= carry_capacity:
		_find_nearest_storage()           # Full — go deposit
	elif info["health"] <= 0:
		if carried_amount > 0: _find_nearest_storage()
		else: current_state = State.IDLE  # Resource exhausted mid-swing
	else:
		action_timer.start(harvest_time)  # Still alive — keep swinging

# Picks up materials from a stockpile for delivery to a construction blueprint.
func _do_fetch():
	var storage = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	if not storage or not storage.has_method("take_item"):
		carried_item_name = ""
		current_state = State.IDLE
		return
		
	# take_item returns a dict with the amount taken and the ItemResource reference
	var result = storage.take_item(carried_item_name, carry_capacity)
	
	if result.get("amount", 0) > 0:
		carried_amount = result["amount"]
		carried_item_res = result["resource"]
		inventory_changed.emit()
		# Return to IDLE — the brain will route us to the blueprint on the next think tick
		current_state = State.IDLE
	else:
		# Another bot grabbed the last item before us — clear name and retry
		carried_item_name = ""
		current_state = State.IDLE

# Deposits carried items into the storage building at target_tile.
# If the storage is full, blacklists it and finds the next nearest one.
func _do_deposit():
	if carried_amount <= 0:
		current_state = State.IDLE
		return
		
	var storage = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	if not storage or not storage.has_method("add_item") or not is_instance_valid(storage):
		current_state = State.IDLE
		return
		
	# add_item returns how many it actually accepted (may be less if partially full)
	var amount_taken = storage.add_item(carried_item_res, carried_amount)
	carried_amount -= amount_taken
	inventory_changed.emit()
	
	if carried_amount <= 0:
		# Everything deposited — clear inventory and go find more work
		carried_item_name = ""
		carried_item_res = null
		full_storages_ignored.clear()
		unreachable_storages.clear()
		current_state = State.IDLE
		_add_xp(1)
	else:
		# --- UPGRADED: Smart Blueprint Chaining ---
		if storage is ConstructionSite or storage is TerraformSite:
			# We partially filled a blueprint. Don't panic dump the rest!
			# Go IDLE so the brain can instantly assign us the next blueprint that needs this material.
			current_state = State.IDLE
		else:
			# It's an actual Storage box and it's full — blacklist it and try another
			full_storages_ignored.append(storage)
			_find_nearest_storage()

# Repairs the building at target_tile by 5 HP per second.
# Re-starts its own timer until the building is at full health.
func _do_repair():
	var building = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	# Building may have been destroyed while we were walking to it
	if not building or not "health" in building or not "max_health" in building:
		current_state = State.IDLE
		return
		
	if building.health >= building.max_health:
		current_state = State.IDLE  # Already at full health (another bot beat us to it)
		return
		
	building.health = min(building.health + 5, building.max_health)
	
	# Notify the building's UI (health bar) if it has one
	if building.has_signal("health_changed"):
		building.health_changed.emit(building.health, building.max_health)
	
	_add_xp(1)
	action_audio.stream = AudioManager.sfx_tracks["hammer"]
	action_audio.pitch_scale = randf_range(0.85, 1.15)
	action_audio.play()
		
	if building.health >= building.max_health:
		current_state = State.IDLE  # Done repairing
	else:
		action_timer.start(1.0) # Keep hammering

# Advances a construction site by 10 build progress points per second.
# The construction site replaces itself with the finished building when complete,
# so we must guard against an invalid reference after each add_build_progress() call.
func _do_build():
	var building = level_ref.building_manager.occupied_tiles.get(target_tile, null)
		
	if not building or not (building is ConstructionSite or building is TerraformSite):
		current_state = State.IDLE
		return
		
	building.add_build_progress(10)
	_add_xp(1)
	action_audio.stream = AudioManager.sfx_tracks["hammer"]
	action_audio.pitch_scale = randf_range(0.85, 1.15)
	action_audio.play()
	
	# Construction site deletes itself and spawns the real building on completion,
	# making the old reference invalid — check before re-queuing the timer.
	if not is_instance_valid(building) or building.is_queued_for_deletion():
		current_state = State.IDLE
	else:
		action_timer.start(1.0) # Keep building

# Called when the ON_STANDBY timer expires.
# Clears all blacklists so the bot retries with fresh eyes.
func _do_standby_wake():
	full_storages_ignored.clear()
	unreachable_storages.clear()
	unreachable_tiles.clear()
	current_state = State.IDLE

# Silently discards the bot's inventory and returns to IDLE.
# Used by MAINTAIN bots when storage is full — it's better to drop the load
# and find a build/repair job than to stand around waiting indefinitely.
func _drop_inventory_and_work():
	if carried_amount > 0 and carried_item_name != "":
		EconomyManager.log_item_consumed(carried_item_name, carried_amount)
		
	carried_amount = 0
	carried_item_name = ""
	carried_item_res = null
	inventory_changed.emit()
	current_state = State.IDLE

# Tile Math Helpers

# Finds the best tile to stand on when interacting with a multi-tile building.
# Checks all tiles adjacent to the target footprint and returns the one with the
# shortest actual walking path (not straight-line distance, which ignores walls).
func _get_standable_adjacent_tile(target_tiles: Array) -> Dictionary:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return {"stand": Vector2i(-1, -1), "target": Vector2i(-1, -1)}
	
	var neighbors = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var best_stand = Vector2i(-1, -1)
	var best_target = Vector2i(-1, -1)
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	
	var shortest_path_length = INF
	
	for t_tile in target_tiles:
		for offset in neighbors:
			var test_tile = t_tile + offset
			# Don't stand inside the building's own footprint
			if test_tile in target_tiles: continue
				
			if pathfinder.bot_astar.is_in_boundsv(test_tile) and not pathfinder.bot_astar.is_point_solid(test_tile):
				# Use actual path length, not straight-line distance, so bots don't
				# pick tiles that look close but are separated by a wall.
				var path_array = pathfinder.bot_astar.get_id_path(my_grid, test_tile)
				
				# Empty path means the tile is walled off — skip it
				if path_array.is_empty() and my_grid != test_tile:
					continue
					
				var path_length = path_array.size()
				
				if path_length < shortest_path_length:
					shortest_path_length = path_length
					best_stand = test_tile
					best_target = t_tile
					
	return {"stand": best_stand, "target": best_target}

# If a building was placed on the tile the bot is standing on, it'll be stuck
# inside a solid tile and unable to move. This pops the bot out to the nearest open tile.
func _escape_trapped_tile() -> bool:
	var pathfinder = level_ref.building_manager.pathfinder
	if not pathfinder: return false
	
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	if not pathfinder.bot_astar.is_point_solid(my_grid): return false  # Not trapped
	
	# Search outward in expanding rings until we find an open tile
	for radius in range(1, 3):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var test_tile = my_grid + Vector2i(x, y)
				if pathfinder.bot_astar.is_in_boundsv(test_tile) and not pathfinder.bot_astar.is_point_solid(test_tile):
					global_position = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(test_tile))
					return true
						
	return false  # Completely surrounded — give up and let the next frame try again

# Home System logic (recharge station and location costs)

# Enables/disables the "pick a new home" drag mode, toggled by the UI.
func toggle_set_home_mode(enabled: bool):
	is_setting_home = enabled
	queue_redraw()  # Redraw to show or hide the home placement ghost

# Called when the player clicks a valid tile to set as the new home.
func set_home(grid_pos: Vector2i):
	home_tile = grid_pos
	
	# Moving home costs half the bot's current energy — a deliberate design tax
	# to make home placement a meaningful choice rather than something spammed freely.
	current_energy = max(0.0, current_energy - (max_energy / 2.0))
	if current_energy <= 0.0 and not is_limping:
		is_limping = true
		current_energy = 0.0
		
	inventory_changed.emit()
	
	if is_limping:
		# Immediately route the limping bot to the new home
		_clear_reservation()
		action_timer.stop()
		target_tile = Vector2i(-1, -1)
		
		if _request_path_exact(home_tile):
			current_state = State.MOVING_HOME
		else:
			current_state = State.RECHARGING  # Home is blocked — recharge in place
		return  # Early return — don't fall through to the IDLE reset below
	
	# For non-limping bots: interrupt rest/idle states so the bot walks to the
	# new home immediately rather than waiting for the current action to finish.
	if current_state in [State.IDLE, State.ON_STANDBY, State.MOVING_HOME, State.RECHARGING]:
		current_path.clear()
		action_timer.stop()
		current_state = State.IDLE

# Returns true if the given grid tile is a valid home location.
# A valid home must be inside the buildable zone, outside corruption, and walkable.
func is_valid_home_tile(grid_pos: Vector2i) -> bool:
	if not level_ref or not level_ref.building_manager: return false
	var bm = level_ref.building_manager
	
	if not bm.buildable_tiles.has(grid_pos):
		return false  # Outside the buildable area
		
	if bm.corruption_layer and bm.corruption_layer.get_cell_source_id(grid_pos) != -1:
		return false  # Tile is corrupted — unsafe to sleep here
		
	if bm.pathfinder and bm.pathfinder.bot_astar.is_point_solid(grid_pos):
		return false  # Something solid is already here (wall, building, etc.)
		
	return true

# Sends the bot to its home tile if reachable, otherwise puts it on standby.
# Called whenever the bot has nothing useful to do right now.
func _go_home_or_standby(wait_time: float):
	if home_tile != Vector2i(-1, -1):
		var my_grid = level_ref.object_layer.local_to_map(global_position)
		# Don't re-path if already standing on the home tile
		if my_grid != home_tile and _request_path_exact(home_tile):
			current_state = State.MOVING_HOME
			return
	# No home, already home, or path is blocked — stand by and retry after wait_time seconds
	current_state = State.ON_STANDBY
	action_timer.start(wait_time)

# Combat & Panic logic (adrenaline sprint home when damaged)

func take_damage(damage: int, source: Node2D = null):
	action_audio.stream = AudioManager.sfx_tracks["pain"]
	action_audio.pitch_scale = randf_range(0.85, 1.15)
	action_audio.play()
	health -= damage
	
	if health <= 0:
		die()
		return
		
	# Don't restart panic if already panicking — adrenaline is already pumping
	if current_state != State.PANIC_MOVING_HOME and current_state != State.PANIC_WAITING:
		_drop_inventory_and_work()  # Drop load immediately so we can run at full speed
		is_limping = false          # Adrenaline overrides exhaustion
		
		var my_grid = Vector2i(-1, -1)
		if level_ref and level_ref.object_layer:
			my_grid = level_ref.object_layer.local_to_map(global_position)
			
		if home_tile != Vector2i(-1, -1) and my_grid == home_tile:
			# Already home — no need to run anywhere, just cower
			current_state = State.PANIC_WAITING
			_start_action()
		else:
			#sprint home	
			if home_tile != Vector2i(-1, -1) and _request_path_exact(home_tile):
				current_state = State.PANIC_MOVING_HOME
			else:
				# No home set or completely blocked — cower in place
				current_state = State.PANIC_WAITING
				_start_action()

func die():
	_clear_reservation()
	unhovered.emit(self)
	
	if carried_amount > 0 and carried_item_name != "":
		EconomyManager.log_item_consumed(carried_item_name, carried_amount)
		
	# Clear hover/selection state in InputManager so the UI doesn't hold a dead reference
	if InputManager.hovered_bot == self:
		InputManager.hovered_bot = null
	if is_selected:
		InputManager.object_selected.emit(null)
			
	queue_free()

# Called when the PANIC_WAITING timer expires — the bot has calmed down and is ready to work.
func _end_panic():
	current_state = State.IDLE

# Reservation System logic (soft lock on resource tiles)

func _clear_reservation():
	if target_tile != Vector2i(-1, -1) and level_ref and level_ref.active_grid_objects.has(target_tile):
		var info = level_ref.active_grid_objects[target_tile]
		# Only clear our own reservation — don't stomp another bot's claim
		if info.has("reserved_by") and info["reserved_by"] == self:
			info["reserved_by"] = null



# Called by the UI when the player changes the task dropdown for this bot.
func set_priority(new_priority: int):
	if current_priority == new_priority: return
	
	current_priority = new_priority as TaskPriority
	_clear_reservation()
	
	# Void any carried items that don't match the new priority so the bot doesn't
	# deposit Stone during a wood run or vice versa. The items are simply discarded —
	# the player is intentionally changing the bot's job so this is acceptable.
	if carried_amount > 0:
		if current_priority == TaskPriority.GATHER_WOOD and carried_item_name != "Wood":
			EconomyManager.log_item_consumed(carried_item_name, carried_amount)
			carried_amount = 0
			carried_item_name = ""
			carried_item_res = null
		elif current_priority == TaskPriority.GATHER_STONE and carried_item_name != "Stone":
			EconomyManager.log_item_consumed(carried_item_name, carried_amount)
			carried_amount = 0
			carried_item_name = ""
			carried_item_res = null
	
	if current_priority == TaskPriority.STOPPED:
		# Immediately halt whatever the bot is doing
		target_tile = Vector2i(-1, -1)
		current_path.clear()
		action_timer.stop()
		current_state = State.IDLE
	else:
		# Only interrupt gather/deposit work — don't interrupt a repair or build
		# mid-swing when the player switches away from MAINTAIN mode.
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
	
	_update_sprite(Vector2.ZERO)

# Returns a snapshot of the bot's current task for the info panel.
func get_inventory_info() -> Dictionary:
	var priority_names = {
		TaskPriority.GATHER_WOOD: "Wood Only",
		TaskPriority.GATHER_STONE: "Stone Only",
		TaskPriority.MAINTAIN: "Maintain",
		TaskPriority.STOPPED: "Home"
	}
	return {
		"Target": priority_names.get(current_priority, "Unknown"),
		"Carrying": "%s (%d)" % [carried_item_name, carried_amount] if carried_amount > 0 else "Empty"
	}

# Visuals & Animation updates
func _update_sprite(move_dir: Vector2 = Vector2.ZERO):
	if not sprite: return
	
	# 1. Update our facing direction if we are actually moving
	if move_dir.length_squared() > 0.1:
		last_facing_dir = move_dir.normalized()
		
	# --- ACTION OVERRIDE ---
	# If the bot is actively working on a tile, force it to face that tile!
	var action_states = [State.HARVESTING, State.DEPOSITING, State.REPAIRING, State.BUILDING, State.FETCHING]
	if current_state in action_states and target_tile != Vector2i(-1, -1) and level_ref and level_ref.object_layer:
		var target_world_pos = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(target_tile))
		last_facing_dir = (target_world_pos - global_position).normalized()
		
	# --- HOME OVERRIDE ---
	# Only face DOWN if actively resting, OR if fully stopped and done walking (IDLE)
	elif current_state in [State.RECHARGING, State.PANIC_WAITING] or (current_priority == TaskPriority.STOPPED and current_state == State.IDLE):
		last_facing_dir = Vector2.DOWN
		
	# 2. Determine base X coordinate based on task priority
	var base_x: int = 8 # Default to the White "Zz" (Stopped) sprites
	
	match current_priority:
		TaskPriority.GATHER_STONE: base_x = 0  # Blue
		TaskPriority.GATHER_WOOD: base_x = 2   # Green
		TaskPriority.MAINTAIN: 
			base_x = 4 # Default to Yellow Hammer
			
			# --- NEW: SMART SHOVEL OVERRIDE ---
			# If the bot has a target, check if it's a terraform job!
			if target_tile != Vector2i(-1, -1) and level_ref and level_ref.building_manager:
				var job = level_ref.building_manager.occupied_tiles.get(target_tile, null)
				if job is TerraformSite:
					base_x = 6 # Swap to Pink Shovel!
		TaskPriority.STOPPED: base_x = 8       # White

	# 3. Determine the exact frame coordinates based on direction
	var final_x: int = base_x
	var final_y: int = 0
	
	# Determine dominant axis (are we moving more horizontally or vertically?)
	if abs(last_facing_dir.x) > abs(last_facing_dir.y):
		# SIDEWAYS MOVEMENT (Bottom Row)
		final_y = 1 
		if last_facing_dir.x < 0:
			final_x = base_x      # Moving Left (First side column)
			sprite.flip_h = false # Adjust flip_h if your sprite is drawn facing right!
		else:
			final_x = base_x + 1  # Moving Right (Second side column)
			sprite.flip_h = false 
	else:
		# VERTICAL MOVEMENT (Top Row)
		final_y = 0 
		sprite.flip_h = false # Never flip vertical sprites
		if last_facing_dir.y < 0:
			final_x = base_x      # Moving Up (Back of bot)
		else:
			final_x = base_x + 1  # Moving Down (Front screen of bot)
			
	# Apply the grid coordinates to the sprite!
	sprite.frame_coords = Vector2i(final_x, final_y)

# Debug Visuals (visual-only, no effect on game logic)



# Draws a line from the bot to its next waypoint, with a dot at the final destination.
func _draw_path():
	if current_path.is_empty(): return
	
	var points = PackedVector2Array()
	points.append(Vector2.ZERO)  # Start from the bot's own position (local origin)
	for p in current_path:
		points.append(to_local(p))
		
	if points.size() > 1:
		draw_polyline(points, Color(0.2, 0.8, 1.0, 0.8), 2.0)
		draw_circle(to_local(current_path[-1]), 4.0, Color(1.0, 0.2, 0.2))

# Highlights the bot's home tile in blue when it's selected.
func _draw_home_tile():
	if not is_selected or home_tile == Vector2i(-1, -1): return
	if not level_ref or not level_ref.object_layer: return
	
	var home_local = to_local(level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(home_tile)))
	var rect = Rect2(home_local - Vector2(16, 16), Vector2(32, 32))
	draw_rect(rect, Color(0.2, 0.8, 1.0, 0.2), true)      # Filled, semi-transparent
	draw_rect(rect, Color(0.2, 0.8, 1.0, 0.8), false, 2.0) # Border

# Draws a ghost box under the cursor snapped to the grid while the player is
# picking a new home tile. Green = valid placement, red = invalid.
func _draw_set_home_preview():
	if not is_setting_home: return
	if not level_ref or not level_ref.object_layer: return
	
	var mouse_global = get_global_mouse_position()
	var mouse_grid = level_ref.object_layer.local_to_map(level_ref.object_layer.to_local(mouse_global))
	var preview_local = to_local(level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(mouse_grid)))
	
	var is_valid = is_valid_home_tile(mouse_grid)
	var box_color = Color(0.2, 0.8, 1.0, 0.8) if is_valid else Color(1.0, 0.2, 0.2)
	
	var rect = Rect2(preview_local - Vector2(16, 16), Vector2(32, 32))
	draw_rect(rect, Color(box_color.r, box_color.g, box_color.b, 0.2), true)
	draw_rect(rect, Color(box_color.r, box_color.g, box_color.b, 0.8), false, 2.0)

# Draws a red outline on the resource tile the bot is currently walking to or harvesting.
func _draw_target_tile():
	if target_tile == Vector2i(-1, -1): return
	if not (current_state in [State.MOVING_TO_RESOURCE, State.HARVESTING]): return
	if not level_ref or not level_ref.object_layer: return
	
	var target_local = to_local(level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(target_tile)))
	var rect = Rect2(target_local - Vector2(16, 16), Vector2(32, 32))
	draw_rect(rect, Color(1.0, 0.2, 0.2, 0.8), false, 2.0)

# Draws a small progress bar above the bot while it's performing a timed action.
# Color changes by action type (green = harvest/deposit, blue = repair, purple = build, etc.)
func _draw_action_bar():
	var active_states = [State.HARVESTING, State.DEPOSITING, State.REPAIRING, State.ON_STANDBY, State.BUILDING, State.FETCHING]
	if not current_state in active_states: return
	if action_timer.is_stopped() or action_timer.wait_time <= 0: return
	
	var progress = 1.0 - (action_timer.time_left / action_timer.wait_time)
	var bar_pos = Vector2(-12.0, -24.0)
	
	# --- NEW: DYNAMIC COLOR SELECTION ---
	var fill_color: Color = Color(0.8, 0.8, 0.8) # Fallback Gray
	
	match current_state:
		State.ON_STANDBY:
			fill_color = Color(1.0, 1.0, 1.0) # White (Zz screen)
			
		State.HARVESTING, State.DEPOSITING, State.FETCHING:
			# Match the resource type!
			if carried_item_name == "Wood" or current_priority == TaskPriority.GATHER_WOOD:
				fill_color = Color(0.2, 0.8, 0.2) # Green (Axe)
			elif carried_item_name == "Stone" or current_priority == TaskPriority.GATHER_STONE:
				fill_color = Color(0.2, 0.6, 1.0) # Blue (Pickaxe)
			else:
				fill_color = Color(0.0, 0.8, 0.8) # Cyan (Fallback)
				
		State.REPAIRING, State.BUILDING:
			# Assume Yellow Hammer by default...
			fill_color = Color(1.0, 0.8, 0.2) 
			
			# ...but check the Smart Swap override for the Pink Shovel!
			if target_tile != Vector2i(-1, -1) and level_ref and level_ref.building_manager:
				var job = level_ref.building_manager.occupied_tiles.get(target_tile, null)
				if job is TerraformSite:
					fill_color = Color(0.9, 0.3, 0.8) # Pink/Magenta
	
	# --- DRAWING ---
	draw_rect(Rect2(bar_pos, Vector2(24.0, 4.0)), Color(0.1, 0.1, 0.1, 0.8), true)        # Background
	draw_rect(Rect2(bar_pos, Vector2(24.0 * progress, 4.0)), fill_color, true)             # Fill
	draw_rect(Rect2(bar_pos, Vector2(24.0, 4.0)), Color(0.0, 0.0, 0.0, 1.0), false, 1.0)  # Border

# Draws a small energy bar below the bot whenever energy isn't full.
# Color: yellow while draining normally, red while limping, teal while recharging.
func _draw_energy_bar():
	if current_energy >= max_energy: return  # Don't clutter the screen when full
	
	var e_pos = Vector2(-12.0, 18.0)
	var energy_colors = {
		true:  Color(1.0, 0.2, 0.2), # Red — limping
		false: Color(1.0, 0.8, 0.2)  # Yellow — normal drain
	}
	var energy_color = energy_colors.get(is_limping, Color(1.0, 0.8, 0.2))
	if current_state == State.RECHARGING:
		energy_color = Color(0.2, 1.0, 0.8) # Teal — actively recharging
	
	draw_rect(Rect2(e_pos, Vector2(24.0, 4.0)), Color(0.1, 0.1, 0.1, 0.8), true)
	draw_rect(Rect2(e_pos, Vector2(24.0 * (current_energy / max_energy), 4.0)), energy_color, true)
	draw_rect(Rect2(e_pos, Vector2(24.0, 4.0)), Color(0.0, 0.0, 0.0, 1.0), false, 1.0)

# Save / Load System

func get_save_data() -> Dictionary:
	return {
		# Exact pixel position so the bot spawns in the same spot
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		
		# Grid coordinates — stored separately since Vector2i isn't JSON-serialisable
		"home_x": home_tile.x,
		"home_y": home_tile.y,
		"target_x": target_tile.x,
		"target_y": target_tile.y,
		
		# Brain state
		"current_priority": current_priority,
		"current_state": current_state,
		"current_energy": current_energy,
		"is_limping": is_limping,
		"health": health,
		
		# Veterancy — saved so level bonuses persist between sessions
		"bot_level": bot_level,
		"current_xp": current_xp,
		
		# Inventory
		"carried_item_name": carried_item_name,
		"carried_amount": carried_amount,
		
		# Save remaining action timer so a harvest mid-swing resumes correctly
		"timer_time_left": action_timer.time_left if not action_timer.is_stopped() else 0.0
	}

func load_save_data(data: Dictionary):
	# 1. Restore position
	global_position = Vector2(data.get("pos_x", 0.0), data.get("pos_y", 0.0))
	
	# 2. Restore grid coordinates
	home_tile = Vector2i(data.get("home_x", -1), data.get("home_y", -1))
	target_tile = Vector2i(data.get("target_x", -1), data.get("target_y", -1))
	
	# 3. Restore veterancy and recalculate derived stats BEFORE restoring health,
	#    so max_health is correct when we apply the saved health value below.
	bot_level = data.get("bot_level", 1)
	current_xp = data.get("current_xp", 0)
	_recalculate_stats() # Sets _normal_speed, max_health, carry_capacity
	
	# 4. Restore state, health, and energy
	current_priority = data.get("current_priority", TaskPriority.STOPPED) as TaskPriority
	current_state = data.get("current_state", State.IDLE) as State
	current_energy = data.get("current_energy", max_energy)
	health = data.get("health", max_health)
	is_limping = data.get("is_limping", false)

		
	# 5. Restore inventory — look up the ItemResource from the saved display name
	carried_amount = data.get("carried_amount", 0)
	carried_item_name = data.get("carried_item_name", "")
	
	if carried_amount > 0 and carried_item_name != "":
		carried_item_res = ItemDatabase.get_item(carried_item_name)
	else:
		carried_item_res = null
		
	# 6. Restore the action timer if the bot was mid-action when saved
	var time_left = data.get("timer_time_left", 0.0)
	if time_left > 0:
		action_timer.start(time_left)
		
	# 7. Clear all volatile runtime data — paths and blacklists can't be meaningfully
	#    restored (the world may have changed) so we start fresh and let the brain rethink.
	current_path.clear()
	unreachable_tiles.clear()
	full_storages_ignored.clear()
	unreachable_storages.clear()
	
	# 8. If the bot was walking somewhere when saved, reset it to IDLE.
	#    The world layout may have changed, so blindly resuming a stale path is unsafe.
	var transit_states = [
		State.MOVING_TO_RESOURCE, State.MOVING_TO_INVENTORY,
		State.MOVING_TO_REPAIR, State.MOVING_TO_BUILD,
		State.MOVING_TO_FETCH, State.MOVING_HOME,
		State.PANIC_MOVING_HOME
	]
	
	if current_state in transit_states:
		current_state = State.IDLE
		target_tile = Vector2i(-1, -1)
		action_timer.stop()
	
	inventory_changed.emit() # Wake up any listening UI
	
# UI Interaction & Priority Logic

func _on_mouse_entered():
	hovered.emit(self)
	InputManager.hovered_bot = self  # Let InputManager know so click handling works

func _on_mouse_exited():
	unhovered.emit(self)
	if InputManager.hovered_bot == self:
		InputManager.hovered_bot = null
		

# Action Timer callback
func _on_action_timer_timeout():
	match current_state:
		State.HARVESTING:    _do_harvest()
		State.FETCHING:      _do_fetch()
		State.DEPOSITING:    _do_deposit()
		State.REPAIRING:     _do_repair()
		State.BUILDING:      _do_build()
		State.ON_STANDBY:    _do_standby_wake()
		State.PANIC_WAITING: _end_panic()
