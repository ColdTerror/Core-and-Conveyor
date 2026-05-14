extends Building
class_name CoreBuilding

signal core_destroyed

@export_group("Storage")
@export var max_capacity_per_item: int = 50

# --- INTERNAL INVENTORY ---
var inventory: Dictionary = {} # Key: String (Item Name), Value: int
# -------------------------------

# --- RESEARCH TRACKING ---
var active_research_name: String = ""
var research_bill: Dictionary = {}
var research_bill_max: Dictionary = {} # Keeps track of the original cost for the UI

# ==========================================
# --- NEW: BOT CONSTRUCTION TRACKING ---
# ==========================================
var is_building_bot: bool = false
var bot_bill: Dictionary = {}
var bot_bill_max: Dictionary = {}

# Make sure the Core has access to the level to spawn things!
var level_ref: Node2D 

func _ready():
	super()
	
	add_to_group("Core")
	add_to_group("PriorityTarget")
	
	var ui = get_tree().get_first_node_in_group("GameUI")
	if ui and ui.has_method("_on_core_destroyed"):
		core_destroyed.connect(ui._on_core_destroyed)
		
	# Register as a physical storage container
	EconomyManager.register_source(self)

func setup(level_instance: Node2D):
	level_ref = level_instance

func _exit_tree():
	# If the core dies, unregister it so the economy doesn't try to pull from a dead building
	EconomyManager.unregister_source(self)


# ==========================================
# ---  BOT COST DEFINITION ---
# ==========================================
func get_bot_cost() -> Dictionary:
	var cost = {}
	
	# Grab your items from the database
	var wood_res = ItemDatabase.get_item("Wood")
	var stone_res = ItemDatabase.get_item("Stone")
	
	# Define the price
	if wood_res: cost[wood_res] = 50
	if stone_res: cost[stone_res] = 20
	
	return cost
	
# ==========================================
# BILL MANAGEMENT (Research & Bots)
# ==========================================

func start_research(r_name: String, cost: Dictionary):
	if active_research_name != "":
		print("Already researching something!")
		return
		
	active_research_name = r_name
	research_bill = cost.duplicate()
	research_bill_max = cost.duplicate()
	
	_consume_existing_inventory_for_bill(research_bill, research_bill_max)
	_check_research_completion()
	inventory_changed.emit()

func start_bot_construction():
	if is_building_bot:
		print("Already building a bot!")
		return
		
	var current_bots = get_tree().get_nodes_in_group("Workers").size()
	var max_bots = ResearchManager.max_bots_allowed if Engine.has_singleton("ResearchManager") else 2
	if current_bots >= max_bots:
		print("Max bots reached!")
		return
		
	# Ask ourselves what the cost is!
	var cost = get_bot_cost()
		
	is_building_bot = true
	bot_bill = cost.duplicate()
	bot_bill_max = cost.duplicate()
	
	_consume_existing_inventory_for_bill(bot_bill, bot_bill_max)
	_check_bot_completion()
	inventory_changed.emit()

func _consume_existing_inventory_for_bill(target_bill: Dictionary, target_bill_max: Dictionary):
	# Immediately consume any matching items already in the core
	for item_res in inventory.keys():
		if target_bill.has(item_res):
			var needed = target_bill[item_res]
			var available = inventory[item_res]
			var consumed = min(needed, available)
			
			target_bill[item_res] -= consumed
			inventory[item_res] -= consumed
			
			EconomyManager.log_item_consumed(item_res.display_name, consumed)
			
			# Clean up empty slots
			if inventory[item_res] <= 0:
				inventory.erase(item_res)
			if target_bill[item_res] <= 0:
				target_bill.erase(item_res)
				
	# Sync the economy since we just removed items
	var consumed_amounts = {}
	for res in target_bill_max.keys():
		var originally_needed = target_bill_max[res]
		var still_needed = target_bill.get(res, 0)
		var consumed = originally_needed - still_needed
		if consumed > 0:
			consumed_amounts[res.display_name] = consumed

	if not consumed_amounts.is_empty():
		EconomyManager.remove_resources_from_global(consumed_amounts)

# ==========================================
# INVENTORY LOGIC
# ==========================================

# Bots (and Conveyors) will call this to drop things off
func add_item(item_res: ItemResource, amount: int) -> int:
	var item_name = item_res.display_name
	var amount_left_to_store = amount
	var total_consumed = 0
	
	# 1. INTERCEPT FOR BOT CONSTRUCTION
	if is_building_bot and bot_bill.has(item_res):
		var needed = bot_bill[item_res]
		var consumed_for_bot = min(amount_left_to_store, needed)
		
		bot_bill[item_res] -= consumed_for_bot
		amount_left_to_store -= consumed_for_bot
		total_consumed += consumed_for_bot
		
		EconomyManager.log_item_consumed(item_name, consumed_for_bot)
		
		if bot_bill[item_res] <= 0:
			bot_bill.erase(item_res)
			
		_check_bot_completion()
		
		if amount_left_to_store <= 0:
			inventory_changed.emit()
			return total_consumed

	# 2. INTERCEPT FOR RESEARCH
	if active_research_name != "" and research_bill.has(item_res):
		var needed = research_bill[item_res]
		var consumed_for_research = min(amount_left_to_store, needed)
		
		research_bill[item_res] -= consumed_for_research
		amount_left_to_store -= consumed_for_research
		total_consumed += consumed_for_research
		
		EconomyManager.log_item_consumed(item_name, consumed_for_research)
		
		if research_bill[item_res] <= 0:
			research_bill.erase(item_res)
			
		_check_research_completion()
		
		if amount_left_to_store <= 0:
			inventory_changed.emit()
			return total_consumed
			
	# 3. STORE LEFTOVERS IN REGULAR INVENTORY
	var current_amount = inventory.get(item_res, 0)
	var space_left = max_capacity_per_item - current_amount
	
	if space_left <= 0:
		inventory_changed.emit()
		return total_consumed 
		
	var amount_stored = min(amount_left_to_store, space_left)
	inventory[item_res] = current_amount + amount_stored
	
	EconomyManager.add_resources(item_name, amount_stored)
	inventory_changed.emit()
	
	return total_consumed + amount_stored

func can_accept_item(item_res: ItemResource) -> bool:
	# 1. BOT OVERRIDE
	if is_building_bot and bot_bill.has(item_res):
		return true
		
	# 2. RESEARCH OVERRIDE
	if active_research_name != "" and research_bill.has(item_res):
		return true
		
	# 3. STANDARD STORAGE
	var current_amount = inventory.get(item_res, 0)
	return current_amount < max_capacity_per_item
	
func has_space_for(item_name: String) -> bool:
	for item_res in inventory.keys():
		if item_res.display_name == item_name:
			return inventory[item_res] < max_capacity_per_item
	return true 

# ==========================================
# COMPLETION LOGIC
# ==========================================

func _check_research_completion():
	if research_bill.is_empty() and active_research_name != "":
		print("RESEARCH COMPLETE: ", active_research_name)
		ResearchManager.complete_research(active_research_name)
		active_research_name = ""
		research_bill_max.clear()
		inventory_changed.emit()

func _check_bot_completion():
	if bot_bill.is_empty() and is_building_bot:
		print("BOT CONSTRUCTION COMPLETE!")
		is_building_bot = false
		bot_bill_max.clear()
		
		_spawn_new_bot()
		inventory_changed.emit()

func _spawn_new_bot():
	if not level_ref:
		level_ref = get_tree().get_first_node_in_group("Level")
	if not level_ref: return
	
	var bot_scene = load("res://scenes/Workers/WorkerBot.tscn")
	var new_bot = bot_scene.instantiate()
	
	level_ref.object_layer.add_child(new_bot)
	
	# Ask the BuildingManager for an empty tile right next to the core!
	var bm = level_ref.building_manager
	if bm and bm.has_method("_get_empty_tiles_around"):
		var empty_tiles = bm._get_empty_tiles_around(self, 1)
		if empty_tiles.size() > 0:
			var tile = empty_tiles[0] # Grab the first open spot
			new_bot.global_position = level_ref.object_layer.to_global(level_ref.object_layer.map_to_local(tile))
		else:
			new_bot.global_position = global_position # Fallback to center if completely surrounded
	else:
		new_bot.global_position = global_position
		
	if new_bot.has_method("setup"):
		new_bot.setup(level_ref)
		
	# Connect global inputs
	if InputManager:
		new_bot.hovered.connect(InputManager._on_object_hovered)
		new_bot.unhovered.connect(InputManager._on_object_unhovered)
		
	# --- APPLY RESEARCH LEVELS ---
	if "bot_level" in new_bot and Engine.has_singleton("ResearchManager"):
		new_bot.bot_level = ResearchManager.bot_start_level


# ==========================================
# BOT RETRIEVAL LOGIC
# ==========================================
func take_item(item_name: String, requested_amount: int) -> Dictionary:
	# Search our inventory for the actual ItemResource the bot wants
	for item_res in inventory.keys():
		if item_res.display_name == item_name:
			var available = inventory[item_res]
			
			if available <= 0: continue
			
			var amount_to_take = min(requested_amount, available)
			
			inventory[item_res] -= amount_to_take
			
			# Clean up empty slots
			if inventory[item_res] <= 0:
				inventory.erase(item_res)
				
			inventory_changed.emit()
			
			# SYNC GLOBAL ECONOMY
			EconomyManager.remove_resources_from_global({ item_name: amount_to_take })
			
			# Return the REAL Resource data AND the amount
			return { "resource": item_res, "amount": amount_to_take }
			
	# We didn't have it!
	return { "amount": 0 }


func consume_resources(remaining_bill: Dictionary):
	var needed_items = remaining_bill.keys() 
	
	for res_name in needed_items:
		for inv_res in inventory.keys():
			if inv_res.display_name == res_name:
				
				var take = min(remaining_bill[res_name], inventory[inv_res])
				
				inventory[inv_res] -= take
				if inventory[inv_res] <= 0:
					inventory.erase(inv_res)
					
				remaining_bill[res_name] -= take
				if remaining_bill[res_name] <= 0:
					remaining_bill.erase(res_name)
					
				break 
				
	inventory_changed.emit()

func get_economy_assets() -> Dictionary:
	var string_inventory = {}
	for res in inventory.keys():
		string_inventory[res.display_name] = inventory[res]
	return string_inventory
	
func get_inventory_info() -> Dictionary:
	return inventory

# ==========================================
# GAME OVER LOGIC
# ==========================================
func take_damage(amount: int):
	super(amount)
	if health <= 0:
		_trigger_game_over()

func die():
	var lost_items_dict = {}
	
	for item_res in inventory.keys():
		var amount_lost = inventory[item_res]
		var item_name = item_res.display_name
		
		EconomyManager.log_item_consumed(item_name, amount_lost)
		lost_items_dict[item_name] = amount_lost
		
	if not lost_items_dict.is_empty():
		EconomyManager.remove_resources_from_global(lost_items_dict)
		
	inventory.clear()
	
	_trigger_game_over()
	
func _trigger_game_over():
	print("CORE DESTROYED! GAME OVER!")
	core_destroyed.emit()
	get_tree().paused = true
	
# ==========================================
# SAVE / LOAD SYSTEM (Core)
# ==========================================
func get_save_data() -> Dictionary:
	var data = super.get_save_data()
	
	# 1. Translate the Inventory
	var saved_inventory = {}
	for item_res in inventory.keys():
		saved_inventory[item_res.display_name] = inventory[item_res]
	data["inventory"] = saved_inventory
	
	# 2. Translate the Active Research Bill
	var saved_bill = {}
	for item_res in research_bill.keys():
		saved_bill[item_res.display_name] = research_bill[item_res]
	data["research_bill"] = saved_bill
		
	var saved_bill_max = {}
	for item_res in research_bill_max.keys():
		saved_bill_max[item_res.display_name] = research_bill_max[item_res]
	data["research_bill_max"] = saved_bill_max
	
	data["active_research_name"] = active_research_name
	
	# 3. Translate the Bot Construction Bill
	data["is_building_bot"] = is_building_bot
	
	var saved_bot_bill = {}
	for item_res in bot_bill.keys():
		saved_bot_bill[item_res.display_name] = bot_bill[item_res]
	data["bot_bill"] = saved_bot_bill
	
	var saved_bot_bill_max = {}
	for item_res in bot_bill_max.keys():
		saved_bot_bill_max[item_res.display_name] = bot_bill_max[item_res]
	data["bot_bill_max"] = saved_bot_bill_max
	
	return data

func load_save_data(data: Dictionary):
	super.load_save_data(data)
	
	active_research_name = data.get("active_research_name", "")
	is_building_bot = data.get("is_building_bot", false)
	
	inventory.clear()
	if data.has("inventory"):
		var saved_inv = data["inventory"]
		for item_name in saved_inv.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				inventory[item_res] = int(saved_inv[item_name])
				
	research_bill.clear()
	if data.has("research_bill"):
		var saved_bill = data["research_bill"]
		for item_name in saved_bill.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				research_bill[item_res] = int(saved_bill[item_name])
				
	research_bill_max.clear()
	if data.has("research_bill_max"):
		var saved_bill_max = data["research_bill_max"]
		for item_name in saved_bill_max.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				research_bill_max[item_res] = int(saved_bill_max[item_name])

	bot_bill.clear()
	if data.has("bot_bill"):
		var saved_bot_bill = data["bot_bill"]
		for item_name in saved_bot_bill.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				bot_bill[item_res] = int(saved_bot_bill[item_name])
				
	bot_bill_max.clear()
	if data.has("bot_bill_max"):
		var saved_bot_bill_max = data["bot_bill_max"]
		for item_name in saved_bot_bill_max.keys():
			var item_res = ItemDatabase.get_item(item_name)
			if item_res:
				bot_bill_max[item_res] = int(saved_bot_bill_max[item_name])
				
	inventory_changed.emit()
