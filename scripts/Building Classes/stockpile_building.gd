# ==============================================================================
# Script: Building Classes/stockpile_building.gd
# Purpose: Modular warehousing structures supporting mixed or dedicated item inventories, manual or automatic outputs dynamically cycled via UI selection, bot retrieval requests, resource consumption requests, and save state serialization for inventory dictionaries.
# Dependencies: Inherits Building. Requires global Autoloads EconomyManager, ItemDatabase, and @export var generic_item_scene to spawn items visually.
# Signals: Emits inventory_changed (inherited from Building).
# ==============================================================================
extends Building
class_name StockpileBuilding

@export var generic_item_scene: PackedScene

@export var max_mixed_capacity: int = 25
@export var max_dedicated_capacity: int = 100

var is_dedicated_mode: bool = false
var dedicated_item_name: String = ""

var inventory: Dictionary = {}

var selected_output_name: String = ""
var available_types: Array = []

var level_ref: Node2D
var last_output_port_pos: Vector2i = Vector2i(-99999, -99999)


## Configures stockpile structures with level references.
func setup(level_instance: Node2D):
	level_ref = level_instance


## Registers stockpile vault spaces as global economy storage targets.
func _ready():
	super()
	add_to_group("PriorityTarget")
	building_name = "Stockpile"
	health = max_health - 10
	EconomyManager.register_source(self, true)



## Emits item consumption events to erase physical items from UI ledgers when destroyed.
func die():
	var assets = get_economy_assets()
	
	if not assets.is_empty():
		EconomyManager.remove_resources_from_global(assets)
		
		for item_name in assets.keys():
			var amount_lost = assets[item_name]
			EconomyManager.log_item_consumed(item_name, amount_lost)
			
	inventory.clear()
	super()



## Unregisters stockpile vaults from the global economy registries when removed.
func _exit_tree():
	EconomyManager.unregister_source(self)



## Runs stockpile tick, trying to dispense selected item buffers onto output directions.
func building_tick(delta: float) -> void:
	if selected_output_name != "":
		_try_output_item()



## Cycles active visual output selection modes between discovered inventories and off.
func cycle_output_mode():
	for item in inventory.keys():
		var n = item.display_name
		if not n in available_types:
			available_types.append(n)
	
	if available_types.is_empty(): 
		selected_output_name = ""
		return

	if selected_output_name == "":
		selected_output_name = available_types[0]
	else:
		var idx = available_types.find(selected_output_name)
		if idx == -1 or idx + 1 >= available_types.size():
			selected_output_name = ""
		else:
			selected_output_name = available_types[idx + 1]
			
	print("Stockpile Output set to: ", selected_output_name if selected_output_name != "" else "OFF")


func select_output_mode(item_name: String):
	if item_name == "OFF" or item_name == "":
		selected_output_name = ""
	else:
		selected_output_name = item_name
		
	if is_dedicated_mode and selected_output_name != "":
		dedicated_item_name = selected_output_name
		
	print("Stockpile Output set to: ", selected_output_name if selected_output_name != "" else "OFF")
	inventory_changed.emit()



func _try_output_item():
	if not level_ref: return
	var item_res = _find_item_by_name(selected_output_name)
	if not item_res or inventory.get(item_res, 0) <= 0:
		return
		
	var manager = level_ref.building_manager
	var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	var ports = []
	for tile in occupied_tiles:
		for offset in push_directions:
			var adj_pos = tile + offset
			if occupied_tiles.has(adj_pos):
				continue
				
			if manager.occupied_tiles.has(adj_pos):
				var neighbor = manager.occupied_tiles[adj_pos]
				if neighbor and neighbor.has_method("accept_item_node"):
					var can_output = false
					
					if neighbor is RouterBuilding:
						can_output = true
					elif neighbor is ConveyorBuilding or neighbor is FilterBuilding:
						if neighbor.direction == offset:
							can_output = true
					else:
						can_output = true
						
					if can_output:
						ports.append({
							"source_tile": tile,
							"offset": offset,
							"target_pos": adj_pos,
							"neighbor": neighbor
						})
						
	if ports.is_empty():
		return
		
	var start_idx = 0
	if last_output_port_pos != Vector2i(-99999, -99999):
		for i in range(ports.size()):
			if ports[i].target_pos == last_output_port_pos:
				start_idx = (i + 1) % ports.size()
				break
				
	var next_start_idx = start_idx
	for k in range(ports.size()):
		var idx = (next_start_idx + k) % ports.size()
		var port = ports[idx]
		
		if _spawn_item_into_conveyor(port.neighbor, port.source_tile, port.offset):
			last_output_port_pos = port.target_pos
			return



## Instantiates visual nodes, snaps coordinates, and passes items to adjacent receptors.
func _spawn_item_into_conveyor(receiver: Node, source_tile: Vector2i, direction_offset: Vector2i) -> bool:
	var item_res = _find_item_by_name(selected_output_name)
	if not item_res or inventory.get(item_res, 0) <= 0:
		return false
	
	if not generic_item_scene: return false
	
	var new_item_node = generic_item_scene.instantiate()
	if new_item_node.has_method("setup"): new_item_node.setup(level_ref)
	new_item_node.item_data = item_res
	
	# PERFECT POSITION SNAPPING
	var tile_center_px = level_ref.object_layer.map_to_local(source_tile)
	var edge_px = tile_center_px + (Vector2(direction_offset) * 16.0)
	new_item_node.global_position = edge_px
	
	if new_item_node.has_method("_ready"): new_item_node._ready() 
	
	if receiver.accept_item_node(new_item_node):
		inventory[item_res] -= 1
		if inventory[item_res] <= 0:
			inventory.erase(item_res)
			_prune_available_types()
			
		EconomyManager.remove_resources_from_global({ item_res.display_name: 1 })
		
		inventory_changed.emit()
		return true
	else:
		new_item_node.queue_free()
		return false



## Accepts items from belts, updating inventories and syncing with dedicated capacity states.
func add_item(item_res: ItemResource, amount: int = 1) -> int:
	var current_total = get_total_items()
	var space_left = 0

	if is_dedicated_mode:
		if current_total == 0 and dedicated_item_name == "":
			dedicated_item_name = item_res.display_name
			
		if dedicated_item_name != "" and item_res.display_name != dedicated_item_name:
			return 0 
			
		space_left = max_dedicated_capacity - current_total
	else:
		var current_amount = inventory.get(item_res, 0)
		space_left = max_mixed_capacity - current_amount

	if space_left <= 0:
		return 0

	var amount_to_take = min(amount, space_left)

	if not item_res.display_name in available_types:
		available_types.append(item_res.display_name)

	inventory[item_res] = inventory.get(item_res, 0) + amount_to_take
	EconomyManager.add_resources(item_res.display_name, amount_to_take)
	
	inventory_changed.emit()
	return amount_to_take



## Verifies if stockpile capacities allow incoming cargo items.
func can_accept_item(item_res: ItemResource) -> bool:
	if is_dedicated_mode:
		if dedicated_item_name != "" and dedicated_item_name != item_res.display_name:
			return false
		return get_total_items() < max_dedicated_capacity
	else:
		var current_amount = inventory.get(item_res, 0)
		return current_amount < max_mixed_capacity



## Dispenses a specified cargo type to visiting worker bots, syncing economy registries.
func take_item(item_name: String, requested_amount: int) -> Dictionary:
	for item_res in inventory.keys():
		if item_res.display_name == item_name:
			var available = inventory[item_res]
			
			if available <= 0: continue
			
			var amount_to_take = min(requested_amount, available)
			
			inventory[item_res] -= amount_to_take
			
			if inventory[item_res] <= 0:
				inventory.erase(item_res)
				_prune_available_types()
				
			inventory_changed.emit()
			
			EconomyManager.remove_resources_from_global({ item_name: amount_to_take })
			
			return { "resource": item_res, "amount": amount_to_take }
			
	return { "amount": 0 }



## Verifies space availability for specific item types.
func has_space_for(item_name: String) -> bool:
	if is_dedicated_mode:
		if dedicated_item_name != "" and dedicated_item_name != item_name:
			return false
		return get_total_items() < max_dedicated_capacity
	else:
		var item_res = _find_item_by_name(item_name)
		var current = inventory.get(item_res, 0) if item_res else 0
		return current < max_mixed_capacity



## Summarizes totals of all mixed stored items.
func get_total_items() -> int:
	var total := 0
	for amount in inventory.values():
		total += amount
	return total


## Returns specific stock quantities of an item resource.
func get_item_amount(item: ItemResource) -> int:
	return inventory.get(item, 0)



## Returns raw item-drop capacity values to update info panels.
func get_inventory_info() -> Dictionary:
	return inventory


## Returns a simplified string mapping of active stock quantities.
func get_economy_assets() -> Dictionary:
	var assets = {}
	for item in inventory:
		if item is ItemResource:
			assets[item.display_name] = inventory[item]
	return assets



## Consumes items to fund gameplay construction bills.
func consume_resources(remaining_bill: Dictionary):
	var needed_items = remaining_bill.keys()
	
	for resource_name in needed_items:
		var amount_needed = remaining_bill[resource_name]
		var item_ref = _find_item_by_name(resource_name)
		
		if item_ref:
			var amount_we_have = inventory[item_ref]
			var amount_to_take = min(amount_needed, amount_we_have)
			
			inventory[item_ref] -= amount_to_take
			if inventory[item_ref] <= 0:
				inventory.erase(item_ref)
			
			remaining_bill[resource_name] -= amount_to_take
			if remaining_bill[resource_name] <= 0:
				remaining_bill.erase(resource_name)
	
	_prune_available_types()
	inventory_changed.emit()



## Returns cached ItemResource matches based on display names.
func _find_item_by_name(name: String) -> ItemResource:
	for item in inventory:
		if item is ItemResource and item.display_name == name:
			return item
	return null



## Toggles between dedicated and mixed capacity states, purging conflicting stocks.
func toggle_inventory_mode():
	is_dedicated_mode = not is_dedicated_mode
	
	if is_dedicated_mode:
		if inventory.size() > 0:
			var target_item_ref: ItemResource = null
			
			if selected_output_name != "":
				target_item_ref = _find_item_by_name(selected_output_name)
				
			if target_item_ref == null:
				var max_count: int = -1
				for item in inventory.keys():
					if inventory[item] > max_count:
						max_count = inventory[item]
						target_item_ref = item

			dedicated_item_name = target_item_ref.display_name
			print("Switched to Dedicated. Locked to: ", dedicated_item_name)
			
			var assets_to_remove = {}
			var items_to_erase = []
			
			for item in inventory.keys():
				if item != target_item_ref:
					assets_to_remove[item.display_name] = inventory[item]
					items_to_erase.append(item)
					
			if not assets_to_remove.is_empty():
				EconomyManager.remove_resources_from_global(assets_to_remove)
				
				for item in items_to_erase:
					inventory.erase(item)
					
				available_types.clear()
				available_types.append(dedicated_item_name)
				
				if selected_output_name != "" and selected_output_name != dedicated_item_name:
					selected_output_name = ""
					
		else:
			dedicated_item_name = selected_output_name
			print("Switched to Dedicated. Locked to: ", dedicated_item_name if dedicated_item_name != "" else "waiting for first item...")
	else:
		dedicated_item_name = ""
		print("Switched to Mixed mode.")
		
		var assets_to_remove = {}
		for item in inventory.keys():
			var excess = inventory[item] - max_mixed_capacity
			if excess > 0:
				inventory[item] = max_mixed_capacity
				assets_to_remove[item.display_name] = excess
		
		if not assets_to_remove.is_empty():
			EconomyManager.remove_resources_from_global(assets_to_remove)
	
	inventory_changed.emit()



## Purges all stored items, updating global economy UI values and daily ledgers.
func void_inventory():
	var assets = get_economy_assets()
	if not assets.is_empty():
		EconomyManager.remove_resources_from_global(assets)
		
		for item_name in assets.keys():
			var amount = assets[item_name]
			EconomyManager.log_item_consumed(item_name, amount)
		
	inventory.clear()
	available_types.clear()
	selected_output_name = ""
	
	if is_dedicated_mode:
		dedicated_item_name = "" 
	
	inventory_changed.emit()



## Re-evaluates available items list after extractions or voids.
func _prune_available_types():
	var current_names = []
	for item in inventory.keys():
		current_names.append(item.display_name)
		
	if selected_output_name != "" and not current_names.has(selected_output_name):
		current_names.append(selected_output_name)
		
	if is_dedicated_mode and dedicated_item_name != "" and not current_names.has(dedicated_item_name):
		current_names.append(dedicated_item_name)
		
	available_types = current_names



## Packs stockpile inventories, modes, output selectors, and lists for saves.
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	var saved_inventory = {}
	for item_res in inventory.keys():
		saved_inventory[item_res.display_name] = inventory[item_res]
		
	data["inventory"] = saved_inventory
	data["is_dedicated_mode"] = is_dedicated_mode
	data["dedicated_item_name"] = dedicated_item_name
	data["selected_output_name"] = selected_output_name
	data["available_types"] = available_types
	
	return data


## Restores stockpile inventories, modes, and output settings from saved files.
func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	is_dedicated_mode = data.get("is_dedicated_mode", false)
	dedicated_item_name = data.get("dedicated_item_name", "")
	selected_output_name = data.get("selected_output_name", "")
	available_types = data.get("available_types", [])
	
	inventory.clear()
	if data.has("inventory"):
		var saved_inv = data["inventory"]
		for item_name in saved_inv.keys():
			var item_res = _load_item_resource_by_name(item_name)
			if item_res:
				inventory[item_res] = int(saved_inv[item_name])
				
	inventory_changed.emit()


## Finds database entries for restored item keys.
func _load_item_resource_by_name(item_name: String) -> ItemResource:
	return ItemDatabase.get_item(item_name)
