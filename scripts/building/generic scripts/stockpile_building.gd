extends Building
class_name StockpileBuilding

@export var capacity := 50   # Max total items stored

var inventory: Dictionary = {}  # ItemResource → amount


func _ready():
	super() #run building class ready as well
	building_name = "Stockpile"
	size = Vector2i(4, 4)
	health = max_health
	EconomyManager.register_source(self)

func _exit_tree():
	# 2. Unregister Self
	EconomyManager.unregister_source(self)

# --------------------------------------------------
# ITEM INTERFACE (called by Item / Conveyor systems)
# --------------------------------------------------

# Accept items on ANY tile we occupy
func accepts_item_at(tile: Vector2i) -> bool:
	return tile in occupied_tiles


func can_accept_item(item: ItemResource) -> bool:
	return get_total_items() < capacity


func accept_item(item: ItemResource) -> bool:
	print('accepting item')
	if not can_accept_item(item):
		return false

	inventory[item] = inventory.get(item, 0) + 1
	
	# Emit inventory changed signal for ui
	inventory_changed.emit()
	
	# NEW: Update Global Economy
	# We use the item's name (e.g., "Wood") to match the Economy variable
	EconomyManager.add_resources(item.display_name, 1)
	
	return true


# --------------------------------------------------
# HELPERS
# --------------------------------------------------

func get_total_items() -> int:
	var total := 0
	for amount in inventory.values():
		total += amount
	return total


func get_item_amount(item: ItemResource) -> int:
	return inventory.get(item, 0)
	
func get_inventory_info() -> Dictionary:
	return inventory
	
func get_economy_assets() -> Dictionary:
	var assets = {}
	
	# Translate Internal Inventory (ItemResource -> int)
	# Into Economy Format (String -> int)
	for item in inventory:
		if item is ItemResource:
			# Example: We have <Resource:Wood>.
			# We grab its name "Wood" and use that as the key.
			assets[item.display_name] = inventory[item]
			
	return assets
	
# 3. Implement Consumption Logic
func consume_resources(remaining_bill: Dictionary):
	# We iterate over the items we NEED to pay
	# (Use .keys() to duplicate the list so we can modify the dictionary safely)
	var needed_items = remaining_bill.keys()
	
	for resource_name in needed_items:
		var amount_needed = remaining_bill[resource_name]
		
		# Find the item object in our inventory that matches the string name
		var item_ref = _find_item_by_name(resource_name)
		
		if item_ref:
			var amount_we_have = inventory[item_ref]
			var amount_to_take = min(amount_needed, amount_we_have)
			
			# A. Remove from Internal Inventory
			inventory[item_ref] -= amount_to_take
			if inventory[item_ref] <= 0:
				inventory.erase(item_ref)
			
			# B. Update the Bill (Tell Manager we paid this much)
			remaining_bill[resource_name] -= amount_to_take
			if remaining_bill[resource_name] <= 0:
				remaining_bill.erase(resource_name)
	
	inventory_changed.emit()

# Helper to find <Resource:Wood> when given "Wood" string
func _find_item_by_name(name: String) -> ItemResource:
	for item in inventory:
		if item is ItemResource and item.display_name == name:
			return item
	return null
