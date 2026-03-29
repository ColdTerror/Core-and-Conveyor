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

func _ready():
	super()
	
	add_to_group("Core")
	add_to_group("PriorityTarget")
	
	var ui = get_tree().get_first_node_in_group("GameUI")
	if ui and ui.has_method("_on_core_destroyed"):
		core_destroyed.connect(ui._on_core_destroyed)
		
	# --- NEW: Register as a physical storage container ---
	EconomyManager.register_source(self)

func _exit_tree():
	# If the core dies, unregister it so the economy doesn't try to pull from a dead building
	EconomyManager.unregister_source(self)


func start_research(r_name: String, cost: Dictionary):
	if active_research_name != "":
		print("Already researching something!")
		return
		
	active_research_name = r_name
	research_bill = cost.duplicate()
	research_bill_max = cost.duplicate()
	
	# --- Immediately consume any matching items already in the core ---
	for item_res in inventory.keys():
		if research_bill.has(item_res):
			var needed = research_bill[item_res]
			var available = inventory[item_res]
			var consumed = min(needed, available)
			
			research_bill[item_res] -= consumed
			inventory[item_res] -= consumed
			
			# Clean up empty slots
			if inventory[item_res] <= 0:
				inventory.erase(item_res)
			if research_bill[item_res] <= 0:
				research_bill.erase(item_res)
				
	# Sync the economy since we just removed items
	var consumed_amounts = {}
	for res in research_bill_max.keys():
		var originally_needed = research_bill_max[res]
		var still_needed = research_bill.get(res, 0)
		var consumed = originally_needed - still_needed
		if consumed > 0:
			consumed_amounts[res.display_name] = consumed

	if not consumed_amounts.is_empty():
		EconomyManager.remove_resources_from_global(consumed_amounts)
		
	# Check if existing items already completed the research entirely
	_check_research_completion()
	
	inventory_changed.emit()
	
# ==========================================
# INVENTORY LOGIC
# ==========================================

# Bots (and Conveyors) will call this to drop things off
func add_item(item_res: ItemResource, amount: int) -> int:
	var item_name = item_res.display_name
	var amount_left_to_store = amount
	var total_consumed = 0
	
	# 1. INTERCEPT FOR RESEARCH
	if active_research_name != "" and research_bill.has(item_res):
		
		var needed = research_bill[item_res]
		var consumed_for_research = min(amount_left_to_store, needed)
		
		research_bill[item_res] -= consumed_for_research
		amount_left_to_store -= consumed_for_research
		total_consumed += consumed_for_research
		
		# Did we finish this specific item requirement?
		if research_bill[item_res] <= 0:
			research_bill.erase(item_res)
			
		_check_research_completion()
		
		# If the core ate everything for research, stop here!
		if amount_left_to_store <= 0:
			inventory_changed.emit()
			return total_consumed
			
	# 2. STORE LEFTOVERS IN REGULAR INVENTORY
	# (Your existing code goes here, but use 'amount_left_to_store' instead of 'amount')
	var current_amount = inventory.get(item_res, 0)
	var space_left = max_capacity_per_item - current_amount
	
	if space_left <= 0:
		inventory_changed.emit()
		return total_consumed # Return what we ate for research, even if storage is full
		
	var amount_stored = min(amount_left_to_store, space_left)
	inventory[item_res] = current_amount + amount_stored
	
	EconomyManager.add_resources(item_name, amount_stored)
	inventory_changed.emit()
	
	return total_consumed + amount_stored


func has_space_for(item_name: String) -> bool:
	for item_res in inventory.keys():
		if item_res.display_name == item_name:
			return inventory[item_res] < max_capacity_per_item
	return true # Item not in inventory yet, so there's definitely space
	
# --- NEW HELPER ---
func _check_research_completion():
	if research_bill.is_empty() and active_research_name != "":
		print("RESEARCH COMPLETE: ", active_research_name)
		# TODO: Apply the actual global buffs here!
		ResearchManager.complete_research(active_research_name)
		active_research_name = ""
		research_bill_max.clear()
		inventory_changed.emit()

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
	var needed_items = remaining_bill.keys() # e.g., ["Wood", "Stone"]
	
	for res_name in needed_items:
		# Search our physical inventory for the matching resource
		for inv_res in inventory.keys():
			if inv_res.display_name == res_name:
				
				var take = min(remaining_bill[res_name], inventory[inv_res])
				
				inventory[inv_res] -= take
				if inventory[inv_res] <= 0:
					inventory.erase(inv_res)
					
				remaining_bill[res_name] -= take
				if remaining_bill[res_name] <= 0:
					remaining_bill.erase(res_name)
					
				break # Found it, move to the next item on the bill!
				
	inventory_changed.emit()

# Translates the physical inventory back into Strings for the UI and Manager
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
	_trigger_game_over()
	
func _trigger_game_over():
	print("CORE DESTROYED! GAME OVER!")
	core_destroyed.emit()
	get_tree().paused = true
