extends Building
class_name StockpileBuilding

@export var capacity := 50   # Max total items stored

var inventory: Dictionary = {}  # ItemResource → amount


func _ready():
	super() #run building class ready as well
	building_name = "Stockpile"
	size = Vector2i(4, 4)
	health = max_health


# --------------------------------------------------
# ITEM INTERFACE (called by Item / Conveyor systems)
# --------------------------------------------------

# Accept items on ANY tile we occupy
func accepts_item_at(tile: Vector2i) -> bool:
	return tile in occupied_tiles


func can_accept_item(item: ItemResource) -> bool:
	return get_total_items() < capacity


func accept_item(item: ItemResource) -> bool:
	if not can_accept_item(item):
		return false

	inventory[item] = inventory.get(item, 0) + 1
	
	# Emit inventory changed signal for ui
	inventory_changed.emit()
	
	
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
