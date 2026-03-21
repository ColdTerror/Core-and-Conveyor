extends Building
class_name CoreBuilding

signal core_destroyed

@export_group("Storage")
@export var max_capacity_per_item: int = 50

# --- INTERNAL INVENTORY ---
var inventory: Dictionary = {} # Key: String (Item Name), Value: int
# -------------------------------

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

# ==========================================
# INVENTORY LOGIC
# ==========================================

# Bots (and Conveyors) will call this to drop things off
func add_item(item_res: ItemResource, amount: int) -> int:
	var current_amount = inventory.get(item_res, 0)
	var space_left = max_capacity_per_item - current_amount
	
	if space_left <= 0:
		return 0 # Core is completely full of this item!
		
	# Only take what we have space for
	var amount_to_take = min(amount, space_left)
	
	inventory[item_res] = current_amount + amount_to_take
	
	# Ping the Global Economy UI (Translate to String for the UI!)
	EconomyManager.add_resources(item_res.display_name, amount_to_take)
	inventory_changed.emit()
	
	return amount_to_take

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
