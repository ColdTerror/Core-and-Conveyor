# ==============================================================================
# Script: Building Classes/item_receiver.gd
# Purpose: Receives item payload bundles and unloads them onto all adjacent
#          conveyor belts as fast as possible.
# Dependencies: Inherits Building. Requires global Autoloads (EconomyManager, ItemDatabase).
# ==============================================================================
extends Building
class_name ItemReceiver

var items_buffered: Array[ItemResource] = []
var incoming_bundle_flying: bool = false

var level_ref: Node2D = null



func _ready():
	building_name = "Receiver"
	size = Vector2i(2, 2)
	max_health = 200
	
	var wood_cost = CostData.new()
	wood_cost.item_name = "Wood"
	wood_cost.amount = 20
	var stone_cost = CostData.new()
	stone_cost.item_name = "Stone"
	stone_cost.amount = 15
	build_costs = [wood_cost, stone_cost]
	
	super()
	
	add_to_group("Receiver")
	add_to_group("PriorityTarget")
	EconomyManager.register_source(self, false)



func setup(level_instance: Node2D):
	level_ref = level_instance



func _exit_tree():
	EconomyManager.unregister_source(self)



func get_economy_assets() -> Dictionary:
	var assets = {}
	for item in items_buffered:
		assets[item.display_name] = assets.get(item.display_name, 0) + 1
	return assets



func _process(_delta: float):
	if is_ghost: return
	
	if not items_buffered.is_empty():
		_unload_items_to_belts()



func is_receiver() -> bool:
	return true



func is_receiver_ready_for_launch() -> bool:
	if is_ghost: return false
	return items_buffered.is_empty() and not incoming_bundle_flying



func register_incoming_launch():
	incoming_bundle_flying = true



func receive_bundle(payload: Array[ItemResource]):
	incoming_bundle_flying = false
	for item in payload:
		items_buffered.append(item)
		
	inventory_changed.emit()
	
	if is_selected:
		var hud = get_tree().get_first_node_in_group("MainHUD")
		if hud and hud.has_node("Popup_Layer/DetailMenu"):
			hud.get_node("Popup_Layer/DetailMenu").refresh_ui()



func _unload_items_to_belts():
	if not level_ref or not level_ref.building_manager: return
	
	var bm = level_ref.building_manager
	var footprint = get_footprint(grid_origin)
	
	var push_directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	for tile in footprint:
		for offset in push_directions:
			if items_buffered.is_empty():
				return
				
			var adj_pos = tile + offset
			if footprint.has(adj_pos):
				continue
				
			if bm.occupied_tiles.has(adj_pos):
				var b = bm.occupied_tiles[adj_pos]
				if b:
					var next_item = items_buffered[0]
					
					# 1. Adjacent standard buildings (using add_item/can_accept_item)
					if b.has_method("add_item") and b.has_method("can_accept_item"):
						if b.can_accept_item(next_item):
							var accepted = b.add_item(next_item, 1)
							if accepted > 0:
								items_buffered.remove_at(0)
								inventory_changed.emit()
								
								if is_selected:
									var hud = get_tree().get_first_node_in_group("MainHUD")
									if hud and hud.has_node("Popup_Layer/DetailMenu"):
										hud.get_node("Popup_Layer/DetailMenu").refresh_ui()
										
					# 2. Adjacent logistics belts/routers/filters/bridges (using accept_item_node)
					elif b.has_method("accept_item_node") and b.has_method("accepts_item_at"):
						if b.accepts_item_at(adj_pos):
							var can_output = false
							if b is RouterBuilding:
								can_output = true
							elif b is ConveyorBuilding or b is FilterBuilding:
								if b.direction == offset:
									can_output = true
							else:
								can_output = true
								
							if can_output:
								var item_scene = load("res://scenes/buildings & related/belts & items/item.tscn")
								var new_item = item_scene.instantiate()
								if new_item.has_method("setup"): new_item.setup(level_ref)
								new_item.item_data = next_item
								
								# Snapping position to the edge of the footprint tile in the direction of the offset
								var tile_center_px = level_ref.object_layer.map_to_local(tile)
								var edge_px = tile_center_px + (Vector2(offset) * 16.0)
								new_item.global_position = edge_px
								
								if new_item.has_method("_ready"): new_item._ready()
								
								var success = b.accept_item_node(new_item, null)
								if success:
									items_buffered.remove_at(0)
									inventory_changed.emit()
									
									if is_selected:
										var hud = get_tree().get_first_node_in_group("MainHUD")
										if hud and hud.has_node("Popup_Layer/DetailMenu"):
											hud.get_node("Popup_Layer/DetailMenu").refresh_ui()
								else:
									new_item.queue_free()



func get_inventory_info() -> Dictionary:
	var info = {}
	if items_buffered.is_empty():
		info["Buffered"] = "Empty"
	else:
		info["Buffered"] = "%d / 10" % items_buffered.size()
		
	if incoming_bundle_flying:
		info["Status"] = "INBOUND PAYLOAD"
	else:
		info["Status"] = "Idle"
		
	return info



func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	var item_names = []
	for item in items_buffered:
		item_names.append(item.display_name)
	data["items_buffered"] = item_names
	data["incoming_bundle_flying"] = incoming_bundle_flying
	
	return data



func load_save_data(data: Dictionary):
	super.load_save_data(data)
	items_buffered.clear()
	if data.has("items_buffered"):
		var item_names = data["items_buffered"]
		for item_name in item_names:
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				items_buffered.append(item_res)
				
	incoming_bundle_flying = data.get("incoming_bundle_flying", false)
	inventory_changed.emit()
