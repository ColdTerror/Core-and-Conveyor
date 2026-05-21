# ==============================================================================
# Script: Building Classes/processor_building.gd
# Purpose: Class representing processor structures (e.g., factories, refiners) that consume specific item ingredients according to selected recipes to craft new products over time, handle input/output item buffers, push finished products orthogonally to adjacent networks, support visual progress bar scales, and package local inventory/recipe indices into save/load states.
# Dependencies: Inherits Building. Requires global Autoloads EconomyManager, ItemDatabase, expects RecipeResource instances, and a @export var generic_item_scene to instantiate physical item nodes.
# Signals: Inherits signals from Building (such as inventory_changed).
# ==============================================================================
extends Building
class_name ProcessorBuilding

@export_group("Settings")
@export var recipes: Array[RecipeResource] = [] 
@export var generic_item_scene: PackedScene 

@export var crafting_time_multiplier: float = 1.5

var current_recipe_index: int = 0
var active_recipe: RecipeResource:
	get:
		if recipes.size() > 0:
			return recipes[current_recipe_index]
		return null

var input_inventory: Dictionary = {} 
var output_inventory: int = 0
@export var buffer_capacity: int = 10 

var work_timer: float = 0.0
var is_working: bool = false
var level_ref: Node2D


## Configures the processor with the active level instance reference.
func setup(level_instance: Node2D):
	level_ref = level_instance


## Registers the processor as an active economic production source and runs base ready updates.
func _ready():
	EconomyManager.register_source(self, false)
	super()



## Emits item consumption events for all inputs and products inside buffers when destroyed.
func die():
	for item_res in input_inventory.keys():
		EconomyManager.log_item_consumed(item_res.display_name, input_inventory[item_res])
	input_inventory.clear()
	
	if output_inventory > 0 and active_recipe and active_recipe.output_item:
		EconomyManager.log_item_consumed(active_recipe.output_item.display_name, output_inventory)
	output_inventory = 0
	
	super()



## Checks whether this processor accepts items entering through the specified tile.
func accepts_item_at(_tile: Vector2i) -> bool:
	return true



## Deposits resources into input or output buffers during upgrades or normal gameplay.
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	if not active_recipe: return 0
	
	if item_res == active_recipe.output_item:
		var out_space_left = buffer_capacity - output_inventory
		if out_space_left <= 0: return 0
		
		var out_take = min(amount, out_space_left)
		output_inventory += out_take
		inventory_changed.emit()
		return out_take
		
	if not active_recipe.inputs.has(item_res): return 0 
	
	var current_stored = input_inventory.get(item_res, 0)
	var space_left = buffer_capacity - current_stored
	
	if space_left <= 0: return 0
	
	var amount_to_take = min(amount, space_left)
	input_inventory[item_res] = current_stored + amount_to_take
	inventory_changed.emit() 
	
	return amount_to_take



## Verifies if the processor has room in its input buffer for a specific resource type.
func can_accept_item(item_res: ItemResource) -> bool:
	if not active_recipe: return false
	if not active_recipe.inputs.has(item_res): return false 
	
	var current_stored = input_inventory.get(item_res, 0)
	return current_stored < buffer_capacity



## Runs the periodic processing, crafting, and finished-product dispensing loop.
func building_tick(delta: float) -> void:
	if not level_ref or not active_recipe: return

	if output_inventory > 0:
		_try_output_item()

	if is_working:
		_process_work(delta)
	else:
		_check_can_start_work()



## Evaluates recipes and input buffer quantities to consume ingredients and begin crafting.
func _check_can_start_work():
	if not active_recipe: return
	if output_inventory + active_recipe.output_count > buffer_capacity: return

	for req_item in active_recipe.inputs:
		var req_amount = active_recipe.inputs[req_item]
		var stored_amount = input_inventory.get(req_item, 0)
		
		if stored_amount < req_amount:
			return

	for req_item in active_recipe.inputs:
		var req_amount = active_recipe.inputs[req_item]
		input_inventory[req_item] -= req_amount
		EconomyManager.log_item_consumed(req_item.display_name, req_amount)

	inventory_changed.emit()
	is_working = true
	
	# Apply craft speed multiplier
	work_timer = active_recipe.craft_time * crafting_time_multiplier



## Tracks remaining crafting progress time and transitions to completion when finished.
func _process_work(delta: float):
	if not active_recipe: return

	work_timer -= delta
	if work_timer <= 0:
		_finish_work()



## Increments output product buffers, logs production, and checks for subsequent crafting cycles.
func _finish_work():
	if not active_recipe: return

	is_working = false
	output_inventory += active_recipe.output_count
	
	EconomyManager.log_item_produced(active_recipe.output_item.display_name, active_recipe.output_count)
	
	inventory_changed.emit()
	_check_can_start_work()



## Iterates occupied coordinates to locate orthongonal neighbors that can receive outputs.
func _try_output_item():
	if not level_ref: return
	var manager = level_ref.building_manager

	for my_tile in occupied_tiles:
		var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		
		for offset in push_directions:
			var target_pos = my_tile + offset
			
			if occupied_tiles.has(target_pos): continue
			
			if manager.occupied_tiles.has(target_pos):
				var neighbor = manager.occupied_tiles[target_pos]
				
				if neighbor.has_method("accept_item_node"):
					var can_output = false
					
					if neighbor is RouterBuilding:
						can_output = true
						
					elif neighbor is ConveyorBuilding or neighbor is FilterBuilding:
						if neighbor.direction == offset:
							can_output = true
							
					else:
						can_output = true
							
					if can_output:
						if _spawn_item_into_conveyor(neighbor, my_tile, offset):
							return



## Instantiates visual nodes, snaps coordinates, and passes items to adjacent receptors.
func _spawn_item_into_conveyor(receiver: Node, source_tile: Vector2i, direction_offset: Vector2i) -> bool:
	if not generic_item_scene or not active_recipe or not active_recipe.output_item: return false
	
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	if "item_data" in new_item_node: new_item_node.item_data = active_recipe.output_item
	
	# PERFECT POSITION SNAPPING
	var tile_center_px = level_ref.object_layer.map_to_local(source_tile)
	var edge_px = tile_center_px + (Vector2(direction_offset) * 16.0)
	new_item_node.global_position = edge_px
	
	if new_item_node.has_method("_ready"): new_item_node._ready() 
	
	if receiver.accept_item_node(new_item_node):
		output_inventory -= 1
		inventory_changed.emit()
		return true
		
	else:
		new_item_node.queue_free()
		return false



## Summarizes all buffered inputs and finished product quantities for upgrade carrying.
func get_economy_assets() -> Dictionary:
	var assets = {}
	
	for item_res in input_inventory.keys():
		if input_inventory[item_res] > 0:
			assets[item_res.display_name] = input_inventory[item_res]
			
	if output_inventory > 0 and active_recipe and active_recipe.output_item:
		var out_name = active_recipe.output_item.display_name
		assets[out_name] = assets.get(out_name, 0) + output_inventory 
		
	return assets



## Packs current recipes, input inventories, and output buffer counts for info panels.
func get_inventory_info() -> Dictionary:
	var info = {}
	if active_recipe:
		info["Recipe"] = active_recipe.recipe_name 
		
		for item in input_inventory.keys():
			if input_inventory[item] > 0:
				info[item.display_name] = input_inventory[item]
				
		if output_inventory > 0:
			info[active_recipe.output_item.display_name] = output_inventory
	else:
		info["Status"] = "No Recipe"
		
	return info



## Computes crafting percentage metrics with recipe speed multipliers.
func get_progress_ratio() -> float:
	if not is_working or not active_recipe or active_recipe.craft_time == 0:
		return 0.0
		
	var total_time = active_recipe.craft_time * crafting_time_multiplier
	return 1.0 - (work_timer / total_time)



## Cycles active recipes, discarding active inputs and products on changes.
func cycle_recipe():
	if recipes.size() <= 1: return
	
	if is_working or not input_inventory.is_empty() or output_inventory > 0:
		input_inventory.clear()
		output_inventory = 0
		is_working = false

	current_recipe_index = (current_recipe_index + 1) % recipes.size()
	print("Switched to recipe: " + active_recipe.recipe_name)
	inventory_changed.emit()



## Serializes ingredients lists, recipe indices, work tickers, and buffers for saves.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	var saved_input = {}
	for item_res in input_inventory.keys():
		saved_input[item_res.display_name] = input_inventory[item_res]
	data["input_inventory"] = saved_input
	
	data["output_inventory"] = output_inventory
	data["current_recipe_index"] = current_recipe_index
	data["work_timer"] = work_timer
	data["is_working"] = is_working
	
	return data


## Restores ingredients inventories, active recipe indices, work tickers, and buffers from saved records.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	output_inventory = data.get("output_inventory", 0)
	current_recipe_index = data.get("current_recipe_index", 0)
	work_timer = data.get("work_timer", 0.0)
	is_working = data.get("is_working", false)
	
	input_inventory.clear()
	if data.has("input_inventory"):
		var saved_inv = data["input_inventory"]
		for item_name in saved_inv.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				input_inventory[item_res] = int(saved_inv[item_name])
				
	inventory_changed.emit()
