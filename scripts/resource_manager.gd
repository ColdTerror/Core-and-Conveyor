# ResourceManager.gd
extends Node

enum ResourceState {
	FULL,
	HARVESTING,
	DEPLETED
}

# Key: Vector2i -> { "timer": float, "data": TileDataResource, "target_dict": Dictionary }
var active_regrowth_tasks := {}

# NEW: Key: Vector2i -> float (Time remaining)
var mining_cooldowns := {} 

signal resource_state_changed(tile: Vector2i, state: ResourceState, data: TileDataResource)

# ---------------------------------------------------------
# HARVEST LOGIC
# ---------------------------------------------------------
func request_harvest(tile: Vector2i, object_info: Dictionary, amount: int = -1):
	
	# 1. CHECK: Is the tile regrowing?
	if active_regrowth_tasks.has(tile):
		return

	# 2. NEW CHECK: Is the tile on mining cooldown?
	if mining_cooldowns.has(tile):
		return

	var data = object_info["data"] as TileDataResource
	
	# 3. START COOLDOWN
	# We prevent this tile from being hit again for 'mining_time' seconds
	mining_cooldowns[tile] = data.mining_time

	# 4. THE MATH
	var final_amount = amount if amount > 0 else data.amount_per_mine
	object_info["health"] -= final_amount
	print("Harvested! HP: %d. Cooldown started: %.1fs" % [object_info["health"], data.mining_time])

	# 5. State Decision
	if object_info["health"] <= 0:
		object_info["health"] = 0
		_handle_depletion(tile, data, object_info)
	else:
		_handle_hit(tile, data)

# ---------------------------------------------------------
# PROCESS LOOPS
# ---------------------------------------------------------
func _process(delta):
	# Loop 1: Handle Mining Cooldowns (The new logic)
	_process_mining_cooldowns(delta)
	
	# Loop 2: Handle Forest Regrowth (The existing logic)
	_process_regrowth(delta)

func _process_mining_cooldowns(delta: float):
	if mining_cooldowns.is_empty(): return
	
	var finished_cooldowns := []
	
	for tile in mining_cooldowns:
		mining_cooldowns[tile] -= delta
		if mining_cooldowns[tile] <= 0:
			finished_cooldowns.append(tile)
			
	for tile in finished_cooldowns:
		mining_cooldowns.erase(tile)
		# Optional: Emit a signal here if you want to show a "Ready to mine" UI icon

func _process_regrowth(delta: float):
	if active_regrowth_tasks.is_empty(): return

	var finished_regrowth := []

	for tile in active_regrowth_tasks:
		var task = active_regrowth_tasks[tile]
		task["timer"] -= delta
		if task["timer"] <= 0:
			finished_regrowth.append(tile)

	for tile in finished_regrowth:
		_finish_regrowth(tile)

# ... (Keep _handle_hit, _handle_depletion, and _finish_regrowth exactly as they were) ...

# --- Internal Logic ---

func _handle_hit(tile: Vector2i, data: TileDataResource):
	# Tell Level to show "Leafless" or "Cracked" sprite
	resource_state_changed.emit(tile, ResourceState.HARVESTING, data)

func _handle_depletion(tile: Vector2i, data: TileDataResource, object_info: Dictionary):
	# Tell Level to show "Stump"
	resource_state_changed.emit(tile, ResourceState.DEPLETED, data)
	
	if data.can_regrow:
		active_regrowth_tasks[tile] = {
			"timer": data.regrow_time,
			"data": data,
			"target_dict": object_info # Store reference so we can heal it later!
		}


func _finish_regrowth(tile: Vector2i):
	var task = active_regrowth_tasks[tile]
	var data = task["data"]
	var target_dict = task["target_dict"]
	
	# 1. THE MATH (Reset Health)
	# Because we stored the reference, this updates the dictionary inside Level.gd!
	target_dict["health"] = data.total_resources
	
	# 2. Cleanup
	active_regrowth_tasks.erase(tile)
	
	# 3. Visuals
	resource_state_changed.emit(tile, ResourceState.FULL, data)
