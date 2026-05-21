# ==============================================================================
# Script: Managers/resource_manager.gd
# Purpose: Governs environmental object harvesting, coordinates tree regrowth queues/timers, and tracks individual resource extraction cooldowns for manual/automatic mining.
# Dependencies: Requires TileDataResource resource structures.
# Signals:
#   - resource_state_changed: Emitted when a resource tile's depletion state transitions (Full, Harvesting, Depleted).
#   - resource_destroyed: Emitted when a non-regrowable resource tile is fully depleted.
# ==============================================================================
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
signal resource_destroyed(tile: Vector2i)

# --- UPDATED: Now returns an int! ---
func request_harvest(tile: Vector2i, object_info: Dictionary, amount: int = -1) -> int:
	
	# Early Exits (Return 0 items)
	if active_regrowth_tasks.has(tile): return 0
	if mining_cooldowns.has(tile): return 0

	var data = object_info["data"] as TileDataResource
	
	# START COOLDOWN
	mining_cooldowns[tile] = data.mining_time

	# THE MATH
	var requested_amount = amount if amount > 0 else data.amount_per_mine
	
	# Safely calculate exactly how much we can actually take
	var actual_yield = min(requested_amount, object_info["health"])
	
	object_info["health"] -= actual_yield

	# State Decision
	if object_info["health"] <= 0:
		object_info["health"] = 0
		_handle_depletion(tile, data, object_info)
	else:
		_handle_hit(tile, data)

	# Return the exact amount we successfully mined!
	return actual_yield

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

# Internal Logic

func _handle_hit(tile: Vector2i, data: TileDataResource):
	# Tell Level to show "Leafless" or "Cracked" sprite
	resource_state_changed.emit(tile, ResourceState.HARVESTING, data)

func _handle_depletion(tile: Vector2i, data: TileDataResource, object_info: Dictionary):
	if data.can_regrow:
		# It's a tree! Tell Level to show the "Stump" sprite.
		resource_state_changed.emit(tile, ResourceState.DEPLETED, data)
		
		active_regrowth_tasks[tile] = {
			"timer": data.regrow_time,
			"data": data,
			"target_dict": object_info 
		}
	else:
		# It's gone forever.
		resource_destroyed.emit(tile)


func _finish_regrowth(tile: Vector2i):
	var task = active_regrowth_tasks[tile]
	var data = task["data"]
	var target_dict = task["target_dict"]
	
	# THE MATH (Reset Health)
	# Because we stored the reference, this updates the dictionary inside Level.gd!
	target_dict["health"] = data.total_resources
	
	# Cleanup
	active_regrowth_tasks.erase(tile)
	
	# Visuals
	resource_state_changed.emit(tile, ResourceState.FULL, data)
