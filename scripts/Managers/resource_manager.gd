# ==============================================================================
# Script: Managers/resource_manager.gd
# Purpose: Governs environmental object harvesting and coordinates tree regrowth queues/timers.
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


signal resource_state_changed(tile: Vector2i, state: ResourceState, data: TileDataResource)
signal resource_destroyed(tile: Vector2i)



## Validates environmental harvest states, calculates yield, adjusts node health,
## and returns the harvested item quantity.
func request_harvest(tile: Vector2i, object_info: Dictionary, amount: int) -> int:
	# Early Exits (Return 0 items)
	if active_regrowth_tasks.has(tile): return 0

	var data = object_info["data"] as TileDataResource
	
	# Safely calculate exactly how much we can actually take
	var actual_yield = min(amount, object_info["health"])
	
	object_info["health"] -= actual_yield

	# State Decision
	if object_info["health"] <= 0:
		object_info["health"] = 0
		_handle_depletion(tile, data, object_info)
	else:
		_handle_hit(tile, data)

	# Return the exact amount we successfully mined!
	return actual_yield



## Processes frame-rate delta, updating active regrowth queues.
func _process(delta):
	# Handle Forest Regrowth
	_process_regrowth(delta)



## Processes regrowth timers for depleted tiles and triggers recovery upon timer completion.
func _process_regrowth(delta: float):
	if active_regrowth_tasks.is_empty(): return

	var regrowth_multiplier = 1.0
	var time_mgr = get_tree().get_first_node_in_group("TimeManager")
	if time_mgr:
		match time_mgr.get_current_season():
			time_mgr.Season.SPRING:
				regrowth_multiplier = 1.0
			time_mgr.Season.SUMMER:
				regrowth_multiplier = 1.5
			time_mgr.Season.AUTUMN:
				regrowth_multiplier = 0.5
			time_mgr.Season.WINTER:
				regrowth_multiplier = 0.0

	if regrowth_multiplier == 0.0:
		return

	var scaled_delta = delta * regrowth_multiplier
	var finished_regrowth := []

	for tile in active_regrowth_tasks:
		var task = active_regrowth_tasks[tile]
		task["timer"] -= scaled_delta
		if task["timer"] <= 0:
			finished_regrowth.append(tile)

	for tile in finished_regrowth:
		_finish_regrowth(tile)



## Emits hit visual state signals when a resource tile takes mining impact.
func _handle_hit(tile: Vector2i, data: TileDataResource):
	resource_state_changed.emit(tile, ResourceState.HARVESTING, data)



## Evaluates regrowth potential of a depleted tile, placing it in regrowth queue or destroying it.
func _handle_depletion(tile: Vector2i, data: TileDataResource, object_info: Dictionary):
	if data.can_regrow:
		# It's a tree! Tell Level to show the "Stump" sprite.
		resource_state_changed.emit(tile, ResourceState.DEPLETED, data)
		
		active_regrowth_tasks[tile] = {
			"timer": data.regrow_time,
			"data": data,
			"target_dict": object_info 
		}
	elif data.atlas_coords_depleted != Vector2i(-1, -1):
		# It does not regrow, but leaves depleted debris (like depleted iron ore)
		resource_state_changed.emit(tile, ResourceState.DEPLETED, data)
	else:
		# It's gone forever.
		resource_destroyed.emit(tile)



## Resets a tile's resource health to full and restores its active state.
func _finish_regrowth(tile: Vector2i):
	var task = active_regrowth_tasks[tile]
	var data = task["data"]
	var target_dict = task["target_dict"]
	
	# THE MATH (Reset Health)
	# Because we stored the reference, this updates the dictionary inside Level.gd!
	target_dict["health"] = target_dict.get("max_health", data.total_resources)
	
	active_regrowth_tasks.erase(tile)
	
	resource_state_changed.emit(tile, ResourceState.FULL, data)
