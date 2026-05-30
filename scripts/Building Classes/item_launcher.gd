# ==============================================================================
# Script: Building Classes/item_launcher.gd
# Purpose: Manages loading items, forming bundles, and launching payload projectiles
#          towards linked pneumatic receivers over walls and chasms.
# Dependencies: Inherits Building. Requires global Autoloads (ResearchManager, ItemDatabase, EconomyManager).
# ==============================================================================
extends Building
class_name ItemLauncher

var items_loaded: Array[ItemResource] = []
var target_receiver: Node2D = null
var target_receiver_pos: Vector2i = Vector2i.ZERO

var is_linking_mode: bool = false
var launch_cooldown: float = 4.0
var time_since_last_launch: float = 4.0

var level_ref: Node2D = null



func _ready():
	building_name = "Launcher"
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
	
	add_to_group("Launcher")
	add_to_group("PriorityTarget")
	EconomyManager.register_source(self, false)



func setup(level_instance: Node2D):
	level_ref = level_instance
	if target_receiver_pos != Vector2i.ZERO:
		call_deferred("_restore_linked_receiver")



func _exit_tree():
	EconomyManager.unregister_source(self)



func get_economy_assets() -> Dictionary:
	var assets = {}
	for item in items_loaded:
		assets[item.display_name] = assets.get(item.display_name, 0) + 1
	return assets



func _process(delta: float):
	if is_ghost: return
	
	time_since_last_launch += delta
	
	if items_loaded.size() >= 10 and time_since_last_launch >= launch_cooldown:
		if is_instance_valid(target_receiver) and target_receiver.has_method("is_receiver_ready_for_launch"):
			if target_receiver.is_receiver_ready_for_launch():
				_launch_bundle()



func can_accept_item(_item_res: ItemResource) -> bool:
	if is_ghost: return false
	return items_loaded.size() < 10



func add_item(item_res: ItemResource, amount: int = 1) -> int:
	if is_ghost: return 0
	var space_left = 10 - items_loaded.size()
	if space_left <= 0: return 0
	
	var taken = min(amount, space_left)
	for i in range(taken):
		items_loaded.append(item_res)
		
	inventory_changed.emit()
	return taken



func get_inventory_info() -> Dictionary:
	var info = {}
	if items_loaded.is_empty():
		info["Loaded"] = "0 / 10"
	else:
		info["Loaded"] = "%d / 10" % items_loaded.size()
	
	if is_instance_valid(target_receiver):
		info["Target"] = "Receiver (%s)" % str(target_receiver.grid_origin)
	else:
		info["Target"] = "Unlinked"
		
	return info



func start_linking():
	if not InputManager: return
	is_linking_mode = true
	InputManager.launcher_awaiting_link = self
	InputManager.current_mode = InputManager.InteractionMode.LINK_RECEIVER
	
	var renderer = get_tree().get_first_node_in_group("OverlayRenderer")
	if renderer: renderer.queue_redraw()
	
	var ui = get_tree().get_first_node_in_group("GameUI")
	if ui and ui.has_method("refresh_detail_menu"):
		ui.refresh_detail_menu()



func toggle_linking_mode(active: bool):
	is_linking_mode = active
	var renderer = get_tree().get_first_node_in_group("OverlayRenderer")
	if renderer: renderer.queue_redraw()



func link_receiver(receiver: Node2D):
	target_receiver = receiver
	if receiver:
		target_receiver_pos = receiver.grid_origin
	else:
		target_receiver_pos = Vector2i.ZERO
		
	is_linking_mode = false
	
	var renderer = get_tree().get_first_node_in_group("OverlayRenderer")
	if renderer: renderer.queue_redraw()
	
	if is_selected:
		var hud = get_tree().get_first_node_in_group("MainHUD")
		if hud and hud.has_node("Popup_Layer/DetailMenu"):
			hud.get_node("Popup_Layer/DetailMenu").refresh_ui()



func is_launcher() -> bool:
	return true



func _restore_linked_receiver():
	if not level_ref: return
	var bm = level_ref.building_manager
	if bm and bm.occupied_tiles.has(target_receiver_pos):
		var b = bm.occupied_tiles[target_receiver_pos]
		if b and b.has_method("is_receiver"):
			target_receiver = b



func _launch_bundle():
	time_since_last_launch = 0.0
	
	var bundle_payload: Array[ItemResource] = []
	for i in range(10):
		bundle_payload.append(items_loaded.pop_front())
		
	inventory_changed.emit()
	target_receiver.register_incoming_launch()
	_spawn_visual_payload(bundle_payload)



func _spawn_visual_payload(payload: Array[ItemResource]):
	var flying_sprite = Sprite2D.new()
	if not payload.is_empty() and payload[0].texture:
		flying_sprite.texture = payload[0].texture
	else:
		flying_sprite.texture = load("res://icon.svg")
		
	flying_sprite.scale = Vector2(0.5, 0.5)
	flying_sprite.global_position = global_position
	
	if level_ref:
		level_ref.object_layer.add_child(flying_sprite)
	else:
		get_parent().add_child(flying_sprite)
		
	var start_pos = global_position
	var end_pos = target_receiver.global_position
	
	var tween = create_tween().set_parallel(false)
	
	tween.tween_method(
		func(progress: float):
			if not is_instance_valid(flying_sprite): return
			var curr_pos = start_pos.lerp(end_pos, progress)
			var height = sin(progress * PI) * -96.0
			flying_sprite.global_position = curr_pos + Vector2(0, height)
			flying_sprite.rotation = progress * TAU,
		0.0, 1.0, 1.2
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	tween.finished.connect(func():
		if is_instance_valid(flying_sprite):
			flying_sprite.queue_free()
		if is_instance_valid(target_receiver):
			target_receiver.receive_bundle(payload)
	)



func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	data["target_receiver_pos"] = [target_receiver_pos.x, target_receiver_pos.y]
	
	var loaded_names = []
	for item in items_loaded:
		loaded_names.append(item.display_name)
	data["items_loaded"] = loaded_names
	
	return data



func load_save_data(data: Dictionary):
	super.load_save_data(data)
	if data.has("target_receiver_pos"):
		var pos_array = data["target_receiver_pos"]
		target_receiver_pos = Vector2i(pos_array[0], pos_array[1])
		
	items_loaded.clear()
	if data.has("items_loaded"):
		var loaded_names = data["items_loaded"]
		for item_name in loaded_names:
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				items_loaded.append(item_res)
				
	inventory_changed.emit()
