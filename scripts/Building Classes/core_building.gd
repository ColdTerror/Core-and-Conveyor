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

# Bots (and later Conveyors) will call this to drop things off
func add_item(item_name: String, amount: int) -> int:
	var current_amount = inventory.get(item_name, 0)
	var space_left = max_capacity_per_item - current_amount
	
	if space_left <= 0:
		return 0 # Core is completely full of this item!
		
	# Only take what we have space for
	var amount_to_take = min(amount, space_left)
	
	inventory[item_name] = current_amount + amount_to_take
	
	# Ping the Global Economy UI
	EconomyManager.add_resources(item_name, amount_to_take)
	inventory_changed.emit()
	
	return amount_to_take

# The EconomyManager calls this when you buy a building
func consume_resources(remaining_bill: Dictionary):
	var needed_items = remaining_bill.keys()
	
	for res in needed_items:
		if inventory.has(res):
			# Figure out how much we need vs how much the Core actually has
			var take = min(remaining_bill[res], inventory[res])
			
			inventory[res] -= take
			if inventory[res] <= 0:
				inventory.erase(res)
				
			remaining_bill[res] -= take
			if remaining_bill[res] <= 0:
				remaining_bill.erase(res)
				
	inventory_changed.emit()

# Tells the Hover UI what to display if you click on the Core!
func get_economy_assets() -> Dictionary:
	return inventory.duplicate()
	
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
